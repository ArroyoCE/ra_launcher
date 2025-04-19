import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

class PCFXHasher {
  static const int SECTOR_SIZE = 2048;
  static const List<int> PCFX_IDENTIFIER = [80, 67, 45, 70, 88, 58, 72, 117, 95, 67, 68, 45, 82, 79, 77]; // "PC-FX:Hu_CD-ROM"
  
  /// Hashes a PC-FX file
  static Future<String?> hashFile(String filePath) async {
    try {
      if (filePath.toLowerCase().endsWith('.chd')) {
        return await _hashChdFile(filePath);
      } else if (filePath.toLowerCase().endsWith('.cue')) {
        return await _hashCueFile(filePath);
      } else {
        return await _hashBinFile(filePath);
      }
    } catch (e, stack) {
      debugPrint('Error hashing PC-FX file: $e');
      debugPrint('Stack trace: $stack');
      return null;
    }
  }
  
  /// Hashes a CHD file
  static Future<String?> _hashChdFile(String filePath) async {
    try {
      // Use a process to call the chd-hash utility
      final result = await Process.run('chd-hash', ['--pcfx', filePath]);
      if (result.exitCode == 0 && result.stdout != null) {
        final output = result.stdout.toString().trim();
        final hashRegex = RegExp(r'([a-f0-9]{32})');
        final match = hashRegex.firstMatch(output);
        if (match != null) {
          return match.group(1);
        }
      }
      
      debugPrint('CHD utility failed, falling back to native implementation');
      return await _nativeHashChdFile(filePath);
    } catch (e) {
      debugPrint('Error running CHD utility: $e');
      return await _nativeHashChdFile(filePath);
    }
  }
  
  /// Native implementation for hashing CHD files
  static Future<String?> _nativeHashChdFile(String filePath) async {
    // Implementation details would go here
    // This would need to read the CHD format directly
    debugPrint('Native CHD implementation not available');
    return null;
  }
  
  /// Hashes a CUE file by finding the associated BIN file
  static Future<String?> _hashCueFile(String filePath) async {
    try {
      final cueFile = File(filePath);
      if (!await cueFile.exists()) {
        debugPrint('CUE file not found: $filePath');
        return null;
      }
      
      // Extract BIN file path
      final cueContent = await cueFile.readAsString();
      final fileRegExp = RegExp(r'FILE\s+"(.+?)"\s+BINARY', caseSensitive: false);
      final match = fileRegExp.firstMatch(cueContent);
      
      if (match != null && match.group(1) != null) {
        final binFileName = match.group(1)!;
        final directory = File(filePath).parent.path;
        final binPath = '$directory${Platform.pathSeparator}$binFileName';
        
        if (await File(binPath).exists()) {
          debugPrint('Found BIN file: $binPath');
          return await _hashBinFile(binPath);
        } else {
          debugPrint('BIN file not found: $binPath');
          return null;
        }
      } else {
        debugPrint('Could not find FILE statement in CUE');
        return null;
      }
    } catch (e) {
      debugPrint('Error processing CUE file: $e');
      return null;
    }
  }
  
  /// Hashes a BIN file directly
  static Future<String?> _hashBinFile(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        debugPrint('File does not exist: $filePath');
        return null;
      }
      
      final randomAccessFile = await file.open(mode: FileMode.read);
      try {
        // Detect the sector format
        final formatInfo = await _detectSectorFormat(randomAccessFile);
        if (formatInfo == null) {
          debugPrint('Could not detect PC-FX sector format');
          return null;
        }
        
        final sectorSize = formatInfo['sectorSize'] as int;
        final dataOffset = formatInfo['dataOffset'] as int;
        
        debugPrint('PC-FX format detected: ${formatInfo['name']} (sectorSize: $sectorSize, dataOffset: $dataOffset)');
        
        // Read sector 0 to check for PC-FX identifier
        final sector0Data = await _readSector(randomAccessFile, 0, sectorSize, dataOffset, SECTOR_SIZE);
        if (sector0Data == null) {
          debugPrint('Failed to read PC-FX sector 0');
          return null;
        }
        
        // Check for PC-FX identifier
        if (!_findIdentifier(sector0Data, PCFX_IDENTIFIER)) {
          debugPrint('PC-FX identifier not found in sector 0');
          return null;
        }
        
        // Read sector 1 for program info
        final sector1Data = await _readSector(randomAccessFile, 1, sectorSize, dataOffset, SECTOR_SIZE);
        if (sector1Data == null || sector1Data.length < 128) {
          debugPrint('Failed to read PC-FX sector 1 or data too small');
          return null;
        }
        
        // Get 128 bytes of program info
        final programInfo = sector1Data.length > 128 ? 
                          sector1Data.sublist(0, 128) : 
                          sector1Data;
        
        // Extract program parameters (32-bit values at offset 32 and 36)
        final programSector = programInfo[32] | 
                             (programInfo[33] << 8) | 
                             (programInfo[34] << 16) | 
                             (programInfo[35] << 24);
        
        final numSectors = programInfo[36] | 
                          (programInfo[37] << 8) | 
                          (programInfo[38] << 16) | 
                          (programInfo[39] << 24);
        
        debugPrint('PC-FX program sector: $programSector, sectors: $numSectors');
        
        // Create hash buffer starting with program info
        final hashBuffer = BytesBuilder();
        hashBuffer.add(programInfo);
        
        // Read program data if valid
        if (programSector > 0 && numSectors > 0 && numSectors < 4096) {
          final programData = await _readSectors(randomAccessFile, programSector, numSectors, sectorSize, dataOffset);
          if (programData != null) {
            hashBuffer.add(programData);
            debugPrint('Added ${programData.length} bytes of PC-FX program data');
          }
        } else {
          debugPrint('Invalid PC-FX program parameters, using only program info for hash');
        }
        
        // Calculate MD5 hash
        final digest = md5.convert(hashBuffer.toBytes());
        final hash = digest.toString();
        debugPrint('Generated PC-FX hash: $hash');
        return hash;
      } finally {
        await randomAccessFile.close();
      }
    } catch (e) {
      debugPrint('Error hashing PC-FX BIN file: $e');
      return null;
    }
  }
  
  /// Reads sectors from a file
  static Future<Uint8List?> _readSectors(RandomAccessFile file, int startSector, int numSectors, int sectorSize, int dataOffset) async {
    try {
      // Safety limit
      final safeSectors = numSectors > 4096 ? 4096 : numSectors;
      
      final buffer = Uint8List(safeSectors * SECTOR_SIZE);
      var totalBytes = 0;
      
      for (var i = 0; i < safeSectors; i++) {
        final sectorData = await _readSector(file, startSector + i, sectorSize, dataOffset, SECTOR_SIZE);
        if (sectorData == null) break;
        
        final bytesToCopy = sectorData.length > SECTOR_SIZE ? 
                            SECTOR_SIZE : sectorData.length;
        
        buffer.setRange(totalBytes, totalBytes + bytesToCopy, sectorData);
        totalBytes += bytesToCopy;
      }
      
      if (totalBytes == 0) return null;
      return buffer.sublist(0, totalBytes);
    } catch (e) {
      debugPrint('Error reading PC-FX sectors: $e');
      return null;
    }
  }
  
  /// Reads a single sector
  static Future<Uint8List?> _readSector(RandomAccessFile file, int sectorNumber, int sectorSize, int dataOffset, int bytesToRead) async {
    try {
      final position = sectorNumber * sectorSize + dataOffset;
      await file.setPosition(position);
      
      final buffer = Uint8List(bytesToRead);
      final bytesRead = await file.readInto(buffer);
      
      if (bytesRead < bytesToRead) {
        return buffer.sublist(0, bytesRead);
      }
      
      return buffer;
    } catch (e) {
      debugPrint('Error reading PC-FX sector $sectorNumber: $e');
      return null;
    }
  }
  
  /// Detects sector format by trying common formats
  static Future<Map<String, dynamic>?> _detectSectorFormat(RandomAccessFile file) async {
    final fileSize = await file.length();
    debugPrint('PC-FX file size: $fileSize bytes');
    
    // Common sector formats to try
    final formats = [
      {'sectorSize': 2352, 'dataOffset': 16, 'name': 'CDDA (2352 bytes/sector with 16 byte header)'},
      {'sectorSize': 2048, 'dataOffset': 0, 'name': 'DATA (2048 bytes/sector)'},
      {'sectorSize': 2336, 'dataOffset': 0, 'name': 'MODE2 (2336 bytes/sector)'},
      // Add more formats if needed
    ];
    
    for (var format in formats) {
      final sectorSize = format['sectorSize'] as int;
      final dataOffset = format['dataOffset'] as int;
      
      // Read sector 0 and check for PC-FX marker
      final data = await _readSector(file, 0, sectorSize, dataOffset, 32);
      if (data != null && _findIdentifier(data, PCFX_IDENTIFIER)) {
        return format;
      }
    }
    
    // Try to deduce from file size
    if (fileSize % 2352 == 0) {
      // Try again with deduced sector size
      const sectorSize = 2352;
      for (var dataOffset in [16, 24, 0]) {
        final data = await _readSector(file, 0, sectorSize, dataOffset, 32);
        if (data != null && _findIdentifier(data, PCFX_IDENTIFIER)) {
          return {'sectorSize': sectorSize, 'dataOffset': dataOffset, 'name': 'Deduced CDDA format'};
        }
      }
    }
    
    return null;
  }
  
  /// Finds identifier anywhere in buffer
  static bool _findIdentifier(Uint8List data, List<int> identifier) {
    // Check all possible positions
    final maxOffset = data.length - identifier.length;
    for (var offset = 0; offset <= maxOffset; offset++) {
      var found = true;
      for (var i = 0; i < identifier.length; i++) {
        if (data[offset + i] != identifier[i]) {
          found = false;
          break;
        }
      }
      if (found) return true;
    }
    return false;
  }
}

/// Integration with existing PCFXHashIntegration
class PCFXHashIntegration {
  Future<Map<String, String>> hashPCFXFilesInFolders(
    List<String> folders,
    {void Function(int current, int total)? progressCallback}
  ) async {
    debugPrint('Starting PC-FX hashing in ${folders.length} folders');
    
    final Map<String, String> hashes = {};
    final validExtensions = ['.bin', '.img', '.chd', '.cue'];
    
    try {
      // Find all files with valid extensions
      final allFiles = await _findFilesWithExtensions(folders, validExtensions);
      final total = allFiles.length;
      
      debugPrint('Found ${allFiles.length} PC-FX files to process');
      
      // Process each file
      for (int i = 0; i < allFiles.length; i++) {
        final filePath = allFiles[i];
        
        if (filePath.toLowerCase().endsWith('.m3u')) {
          debugPrint('Skipping M3U file: $filePath');
          continue;
        }
        
        try {
          final hash = await PCFXHasher.hashFile(filePath);
          
          if (hash != null && hash.isNotEmpty) {
            hashes[filePath] = hash;
            debugPrint('Successfully hashed PC-FX: $filePath -> $hash');
          } else {
            debugPrint('Failed to hash PC-FX: $filePath');
          }
        } catch (e) {
          debugPrint('Error processing PC-FX file $filePath: $e');
        }
        
        // Update progress
        if (progressCallback != null) {
          progressCallback(i + 1, total);
        }
      }
      
      debugPrint('Completed PC-FX hashing: ${hashes.length} of $total files');
      return hashes;
    } catch (e) {
      debugPrint('Error in PC-FX hashFilesInFolders: $e');
      return hashes;
    }
  }
  
  /// Find files with specific extensions in folders
  Future<List<String>> _findFilesWithExtensions(
    List<String> folders,
    List<String> extensions
  ) async {
    final List<String> result = [];
    
    for (final folder in folders) {
      try {
        final directory = Directory(folder);
        if (!await directory.exists()) {
          debugPrint('Directory does not exist: $folder');
          continue;
        }
        
        await for (final entity in directory.list(recursive: true)) {
          if (entity is File) {
            final lowerPath = entity.path.toLowerCase();
            if (extensions.any((ext) => lowerPath.endsWith(ext))) {
              result.add(entity.path);
            }
          }
        }
      } catch (e) {
        debugPrint('Error scanning directory $folder: $e');
      }
    }
    
    return result;
  }
}