// ps2_hash.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

import '../CHD/isolate_chd_processor.dart';

/// Class to handle hashing PS2 files
class Ps2HashCalculator {
  // Constants for PS2 disc images
  static const String _bootKey = "BOOT2";
  static const String _cdromPrefix = "cdrom0:";

  /// Hash PS2 files in the provided folders
  Future<Map<String, String>> hashPs2FilesInFolders(List<String> folders) async {
    final Map<String, String> hashes = {};
    
    // Valid PS2 file extensions
    final validExtensions = ['.iso', '.bin', '.chd'];
    
    for (final folder in folders) {
      try {
        final dir = Directory(folder);
        if (!await dir.exists()) continue;
        
        // Get all files in directory
        final List<FileSystemEntity> entities = await dir.list(recursive: true).toList();
        final List<File> files = entities
            .whereType<File>()
            .where((file) => validExtensions.contains(path.extension(file.path).toLowerCase()))
            .toList();
        
        debugPrint('Found ${files.length} PS2 files in $folder');
        
        // Process each file
        for (int i = 0; i < files.length; i++) {
          final file = files[i];
          final filePath = file.path;
          
          try {
            debugPrint('Processing ${i+1}/${files.length}: $filePath');
            String? hash;
            
            // Process based on file extension
            if (path.extension(filePath).toLowerCase() == '.chd') {
              // CHD files use the isolate processor
              hash = await _hashPs2Chd(filePath);
            } else {
              // ISO/BIN files
              hash = await _hashPs2File(filePath);
            }
            
            if (hash != null && hash.isNotEmpty) {
              hashes[filePath] = hash;
              debugPrint('✓ Hashed: $filePath -> $hash');
            } else {
              debugPrint('✗ Failed to hash: $filePath');
            }
          } catch (e) {
            debugPrint('Error hashing PS2 file $filePath: $e');
          }
        }
      } catch (e) {
        debugPrint('Error processing folder $folder: $e');
      }
    }
    
    return hashes;
  }
  
  /// Hash a PS2 CHD file using the isolate processor
  Future<String?> _hashPs2Chd(String filePath) async {
    // Use the isolate processor to handle CHD files
    return await IsolateChdProcessor.processChd(filePath);
  }
  
  /// Hash a PS2 ISO/BIN file
  Future<String?> _hashPs2File(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) return null;
    
    try {
      // First find the SYSTEM.CNF file in the filesystem
      final systemCnfData = await _findAndReadSystemCnf(file);
      if (systemCnfData == null) {
        debugPrint('Could not find or read SYSTEM.CNF in $filePath');
        return null;
      }
      
      // Parse SYSTEM.CNF to find the boot executable
      final exePath = _findBootExecutable(systemCnfData);
      if (exePath == null) {
        debugPrint('Could not find boot executable path in SYSTEM.CNF');
        return null;
      }
      
      debugPrint('Found boot executable: $exePath');
      
      // Find and read the executable
      final exeData = await _findAndReadFile(file, exePath);
      if (exeData == null) {
        debugPrint('Could not find or read executable: $exePath');
        return null;
      }
      
      // Check for ELF header (0x7F, 0x45, 0x4C, 0x46)
      if (exeData.length >= 4) {
        if (exeData[0] != 0x7F || exeData[1] != 0x45 || 
            exeData[2] != 0x4C || exeData[3] != 0x46) {
          debugPrint('Warning: Executable does not have ELF header signature');
        }
      }
      
      // Create hash from both the executable name and content (matching the C implementation)
      final digest = crypto.md5.convert(utf8.encode(exePath) + exeData);
      return digest.toString();
    } catch (e, stackTrace) {
      debugPrint('Error hashing PS2 file: $e');
      debugPrint('Stack trace: $stackTrace');
      return null;
    }
  }
  
  /// Find and read the SYSTEM.CNF file from a PS2 disc image
  Future<Uint8List?> _findAndReadSystemCnf(File file) async {
    // Find the root directory
    final rootDirSector = await _findRootDirectorySector(file);
    if (rootDirSector == null) return null;
    
    // Find SYSTEM.CNF in the root directory
    return await _findAndReadFile(file, 'SYSTEM.CNF', rootDirSector: rootDirSector);
  }
  
  /// Find and read a file from the ISO filesystem
  Future<Uint8List?> _findAndReadFile(File file, String filePath, {int? rootDirSector}) async {
    try {
      // If root directory sector not provided, find it
      rootDirSector ??= await _findRootDirectorySector(file);
      if (rootDirSector == null) return null;
      
      // Find the file in the directory structure
      final fileInfo = await _findFileInDirectory(file, rootDirSector, filePath);
      if (fileInfo == null) return null;
      
      // Read the file data
      return await _readSectors(file, fileInfo.lba, fileInfo.size);
    } catch (e) {
      debugPrint('Error finding/reading file: $e');
      return null;
    }
  }
  
  /// Find the root directory sector in an ISO file
  Future<int?> _findRootDirectorySector(File file) async {
    try {
      // In ISO9660, the Primary Volume Descriptor starts at sector 16
      final pvdData = await _readSector(file, 16);
      if (pvdData == null || pvdData.length < 166) return null;
      
      // Check for ISO9660 identifier "CD001"
      if (pvdData[1] != 0x43 || pvdData[2] != 0x44 || 
          pvdData[3] != 0x30 || pvdData[4] != 0x30 || 
          pvdData[5] != 0x31) {
        return null; // Not an ISO9660 filesystem
      }
      
      // Extract the root directory location (bytes 156-159)
      final rootDirLba = pvdData[156 + 2] | 
                         (pvdData[156 + 3] << 8) | 
                         (pvdData[156 + 4] << 16) | 
                         (pvdData[156 + 5] << 24);
      
      return rootDirLba;
    } catch (e) {
      debugPrint('Error finding root directory: $e');
      return null;
    }
  }
  
  /// Find a file in a directory sector
  Future<_FileInfo?> _findFileInDirectory(File file, int sectorLba, String fileName) async {
    try {
      // Normalize filename: Convert to uppercase and handle path separators
      fileName = fileName.toUpperCase().replaceAll('\\', '/');
      
      // Handle path components
      if (fileName.contains('/')) {
        final pathParts = fileName.split('/');
        final firstPart = pathParts.first;
        
        // Find the subdirectory
        final dirEntry = await _findDirectoryEntry(file, sectorLba, firstPart, true);
        if (dirEntry == null) return null;
        
        // Recurse into the subdirectory
        return await _findFileInDirectory(
          file, 
          dirEntry.lba, 
          pathParts.sublist(1).join('/')
        );
      }
      
      // Find the file entry
      final fileEntry = await _findDirectoryEntry(file, sectorLba, fileName, false);
      if (fileEntry == null) return null;
      
      return _FileInfo(lba: fileEntry.lba, size: fileEntry.size);
    } catch (e) {
      debugPrint('Error finding file in directory: $e');
      return null;
    }
  }
  
  /// Find a directory entry by name
  Future<_DirectoryEntry?> _findDirectoryEntry(
    File file, 
    int sectorLba, 
    String targetName,
    bool isDirectory
  ) async {
    int currentSector = sectorLba;
    bool continueReading = true;
    
    while (continueReading) {
      final sectorData = await _readSector(file, currentSector);
      if (sectorData == null) return null;
      
      // Process directory entries in this sector
      int offset = 0;
      while (offset < 2048) {
        // Directory record length is at offset 0
        final recordLength = sectorData[offset];
        if (recordLength == 0) {
          // Advance to the next sector boundary
          offset = (offset ~/ 2048 + 1) * 2048;
          if (offset >= 2048) {
            currentSector++;
            continueReading = true;
            break;
          }
          continue;
        }
        
        if (offset + recordLength > 2048) {
          // Entry spans sectors - not handling this case
          currentSector++;
          continueReading = true;
          break;
        }
        
        // File flags (bit 1 = directory)
        final fileFlags = sectorData[offset + 25];
        final entryIsDirectory = (fileFlags & 0x02) != 0;
        
        // Skip if we're looking for a directory but this isn't one
        // or if we're looking for a file but this is a directory
        if ((isDirectory && !entryIsDirectory) || (!isDirectory && entryIsDirectory)) {
          offset += recordLength;
          continue;
        }
        
        // File name length is at offset 32
        final nameLength = sectorData[offset + 32];
        if (nameLength == 0) {
          offset += recordLength;
          continue;
        }
        
        // Extract the name
        String name = '';
        for (int i = 0; i < nameLength; i++) {
          name += String.fromCharCode(sectorData[offset + 33 + i]);
        }
        
        // Strip version number (;1)
        final semicolonPos = name.indexOf(';');
        if (semicolonPos >= 0) {
          name = name.substring(0, semicolonPos);
        }
        
        // Check if this matches our target
        if (name == targetName) {
          // Extract LBA and size
          final entryLba = sectorData[offset + 2] | 
                         (sectorData[offset + 3] << 8) | 
                         (sectorData[offset + 4] << 16) | 
                         (sectorData[offset + 5] << 24);
          
          final entrySize = sectorData[offset + 10] | 
                         (sectorData[offset + 11] << 8) | 
                         (sectorData[offset + 12] << 16) | 
                         (sectorData[offset + 13] << 24);
          
          return _DirectoryEntry(
            name: name,
            lba: entryLba,
            size: entrySize,
            isDirectory: entryIsDirectory
          );
        }
        
        offset += recordLength;
      }
      
      // If we didn't break out of the loop to continue to the next sector,
      // we've processed all entries
      continueReading = false;
    }
    
    return null; // Entry not found
  }
  
  /// Find boot executable path in SYSTEM.CNF
  String? _findBootExecutable(Uint8List data) {
    try {
      // Convert to string with allowMalformed to handle potential encoding issues
      final content = utf8.decode(data, allowMalformed: true);
      
      // Look for the boot key pattern
      final bootPattern = RegExp('$_bootKey\\s*=\\s*$_cdromPrefix\\\\?([^;\\s\\r\\n]+)');
      final match = bootPattern.firstMatch(content);
      
      if (match != null && match.groupCount >= 1) {
        String execPath = match.group(1)!;
        
        // Sanitize the path
        execPath = execPath.split(';').first.trim();
        
        return execPath;
      }
      
      return null;
    } catch (e) {
      debugPrint('Error parsing SYSTEM.CNF: $e');
      return null;
    }
  }
  
  /// Read a single sector from the file
  Future<Uint8List?> _readSector(File file, int sector) async {
    return await _readSectors(file, sector, 2048); // Standard ISO sector size
  }
  
  /// Read multiple sectors from the file
  Future<Uint8List?> _readSectors(File file, int startSector, int size) async {
    try {
      const sectorSize = 2048; // Standard ISO sector size
      final position = startSector * sectorSize;
      
      final raf = await file.open(mode: FileMode.read);
      try {
        await raf.setPosition(position);
        return await raf.read(size);
      } finally {
        await raf.close();
      }
    } catch (e) {
      debugPrint('Error reading sectors: $e');
      return null;
    }
  }
}

/// Helper class to store file information
class _FileInfo {
  final int lba;
  final int size;
  
  _FileInfo({required this.lba, required this.size});
}

/// Helper class to store directory entry information
class _DirectoryEntry {
  final String name;
  final int lba;
  final int size;
  final bool isDirectory;
  
  _DirectoryEntry({
    required this.name,
    required this.lba,
    required this.size,
    required this.isDirectory,
  });
}