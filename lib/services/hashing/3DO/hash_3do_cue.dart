// File: lib/3do/hash_3do.dart (renamed to be more generic)

import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:path/path.dart' as path;

/// Handler for 3DO disc image files (CUE, BIN, ISO)
class Hash3DOCalculator {
  static const List<int> OPERA_FS_IDENTIFIER = [0x01, 0x5A, 0x5A, 0x5A, 0x5A, 0x5A, 0x01];
  

  /// Calculate hash for a 3DO disc image file
  /// Returns the MD5 hash as a hex string, or null if an error occurs
  static Future<String?> calculateHash(String filePath) async {
    final File sourceFile = File(filePath);
    if (!await sourceFile.exists()) {
      return null;
    }
    
    final String fileExtension = path.extension(filePath).toLowerCase();
    
    if (fileExtension == '.cue') {
      return _processCueFile(filePath);
    } else if (fileExtension == '.bin' || fileExtension == '.iso') {
      return _processDiscImageFile(filePath);
    } else {
      // Unsupported file type
      return null;
    }
  }

  /// Process a CUE file by finding the associated BIN file
  static Future<String?> _processCueFile(String cuePath) async {
    final File cueFile = File(cuePath);
    final String cueContent = await cueFile.readAsString();
    final String? binPath = _extractBinPath(cueContent, cuePath);
    
    if (binPath == null) {
      return null;
    }
    
    return _processDiscImageFile(binPath);
  }
  
  /// Process a disc image file (BIN or ISO)
  static Future<String?> _processDiscImageFile(String imagePath) async {
    final File imageFile = File(imagePath);
    if (!await imageFile.exists()) {
      return null;
    }
    
    // Default values for BIN/ISO files
    final Map<String, int> imageInfo = {
      'mode': 1,        // Default: MODE1
      'sectorSize': 2352,  // Default: 2352 bytes
      'dataOffset': 16     // Default: 16 byte offset for MODE1
    };
    
    // For ISO files, we need to adjust these defaults
    if (path.extension(imagePath).toLowerCase() == '.iso') {
      imageInfo['sectorSize'] = 2048;  // ISO files are typically 2048 bytes per sector
      imageInfo['dataOffset'] = 0;     // No header in ISO files
    }
    
    // Open the disc image file and read the first sector
    final RandomAccessFile imageHandle = await imageFile.open(mode: FileMode.read);
    
    try {
      final int sectorSize = imageInfo['sectorSize']!;
      final int dataOffset = imageInfo['dataOffset']!;
      
      // Read the first sector to check for Opera filesystem
      final Uint8List sectorData = Uint8List(sectorSize);
      final int bytesRead = await imageHandle.readInto(sectorData);
      
      if (bytesRead < sectorSize) {
        return null;
      }
      
      // First look for the Opera filesystem at the expected offset
      bool found = false;
      int fsOffset = 0;
      
      if (dataOffset > 0 && sectorData.length >= dataOffset + OPERA_FS_IDENTIFIER.length) {
        found = _compareBytes(sectorData, dataOffset, 
                          Uint8List.fromList(OPERA_FS_IDENTIFIER), 0, 
                          OPERA_FS_IDENTIFIER.length);
        if (found) {
          fsOffset = dataOffset;
        }
      }
      
      // If not found at the standard offset, scan the entire sector
      if (!found) {
        for (int i = 0; i < sectorData.length - OPERA_FS_IDENTIFIER.length; i++) {
          if (_compareBytes(sectorData, i, Uint8List.fromList(OPERA_FS_IDENTIFIER), 0, OPERA_FS_IDENTIFIER.length)) {
            found = true;
            fsOffset = i;
            break;
          }
        }
      }
      
      // If still not found, try sector 16 (sometimes used as start sector)
      if (!found) {
        await imageHandle.setPosition(16 * sectorSize);
        final bytesRead = await imageHandle.readInto(sectorData);
        
        if (bytesRead < sectorSize) {
          return null;
        }
        
        // First look for the Opera filesystem at the expected offset
        if (dataOffset > 0 && sectorData.length >= dataOffset + OPERA_FS_IDENTIFIER.length) {
          found = _compareBytes(sectorData, dataOffset, 
                            Uint8List.fromList(OPERA_FS_IDENTIFIER), 0, 
                            OPERA_FS_IDENTIFIER.length);
          if (found) fsOffset = dataOffset;
        }
        
        // If not found at the standard offset, scan the entire sector
        if (!found) {
          for (int i = 0; i < sectorData.length - OPERA_FS_IDENTIFIER.length; i++) {
            if (_compareBytes(sectorData, i, Uint8List.fromList(OPERA_FS_IDENTIFIER), 0, OPERA_FS_IDENTIFIER.length)) {
              found = true;
              fsOffset = i;
              break;
            }
          }
        }
      }
      
      if (!found) {
        return null;
      }
      
      // Parse the block size and root directory location from the header
      final blockSize = _getBlockSize(sectorData, fsOffset);
      final rootBlockLocation = _getRootBlockLocation(sectorData, fsOffset) * blockSize;
      
      // Find the LaunchMe file
      final launchMeInfo = await _findLaunchMeFile(imageHandle, sectorSize, fsOffset, rootBlockLocation, blockSize);
      if (launchMeInfo == null) {
        return null;
      }
      
      final launchMeLocation = launchMeInfo['location'] as int;
      final launchMeSize = launchMeInfo['size'] as int;
      
      // Create a list to hold all bytes to hash
      final List<int> allBytes = [];
      
      // First add the volume header (132 bytes)
      allBytes.addAll(sectorData.sublist(fsOffset, fsOffset + 132));
      
      // Then add the LaunchMe file contents
      int sector = launchMeLocation ~/ 2048;
      int remaining = launchMeSize;
      
      while (remaining > 0) {
        await imageHandle.setPosition(sector * sectorSize);
        final buffer = Uint8List(sectorSize);
        final bytesRead = await imageHandle.readInto(buffer);
        
        if (bytesRead < sectorSize) {
          return null;
        }
        
        final bytesToHash = remaining > 2048 ? 2048 : remaining;
        final sectorData = buffer.sublist(fsOffset, fsOffset + bytesToHash);
        
        // Add data to the list
        allBytes.addAll(sectorData);
        
        sector++;
        remaining -= bytesToHash;
      }
      
      // Calculate the final hash
      const md5 = crypto.md5;
      final finalDigest = md5.convert(allBytes);
      
      return finalDigest.toString();
      
    } finally {
      await imageHandle.close();
    }
  }

  /// Extract the BIN file path from the CUE content
  static String? _extractBinPath(String cueContent, String cuePath) {
    final RegExp fileRegex = RegExp(r'FILE\s+"([^"]+)"\s+BINARY', caseSensitive: false);
    final match = fileRegex.firstMatch(cueContent);
    
    if (match == null) return null;
    
    String binFileName = match.group(1)!;
    
    // If the BIN path is relative, resolve it relative to the CUE file
    if (!binFileName.startsWith('/') && !RegExp(r'^[A-Za-z]:').hasMatch(binFileName)) {
      // Get directory of the CUE file
      final cueDir = path.dirname(cuePath);
      binFileName = path.join(cueDir, binFileName);
    }
    
    return binFileName;
  }
  
  
  // Helper methods remain the same
  static int _getBlockSize(Uint8List header, int offset) {
    // Block size is at offset 0x4C (big-endian)
    return (header[offset + 0x4D] << 16) | (header[offset + 0x4E] << 8) | header[offset + 0x4F];
  }
  
  static int _getRootBlockLocation(Uint8List header, int offset) {
    // Root directory block location is at offset 0x64 (big-endian)
    return (header[offset + 0x65] << 16) | (header[offset + 0x66] << 8) | header[offset + 0x67];
  }
  
  static bool _compareBytes(List<int> a, int aOffset, List<int> b, int bOffset, int length) {
    if (a.length < aOffset + length || b.length < bOffset + length) {
      return false;
    }
    
    for (int i = 0; i < length; i++) {
      if (a[aOffset + i] != b[bOffset + i]) {
        return false;
      }
    }
    
    return true;
  }
  
  static Future<Map<String, dynamic>?> _findLaunchMeFile(
      RandomAccessFile fileHandle, 
      int sectorSize,
      int fsOffset,
      int rootBlockLocation, 
      int blockSize) async {
    
    // Calculate sector for the root directory
    int sector = rootBlockLocation ~/ 2048;
    
    // Read the root directory sector
    while (true) {
      await fileHandle.setPosition(sector * sectorSize);
      final buffer = Uint8List(sectorSize);
      final bytesRead = await fileHandle.readInto(buffer);
      
      if (bytesRead < sectorSize) {
        return null;
      }
      
      // Offset to start of entries is at offset 0x10
      int offset = (buffer[fsOffset + 0x12] << 8) | buffer[fsOffset + 0x13];
      
      // Offset to end of entries is at offset 0x0C
       int stop = (buffer[fsOffset + 0x0D] << 16) | 
                (buffer[fsOffset + 0x0E] << 8) | 
                buffer[fsOffset + 0x0F];
      
      while (offset < stop) {
        // Check if entry is a file (type 0x02)
        if (buffer[fsOffset + offset + 0x03] == 0x02) {
          // Extract filename starting at offset 0x20
          final nameBytes = buffer.sublist(
              fsOffset + offset + 0x20, 
              fsOffset + offset + 0x20 + 32);
          
          final filename = String.fromCharCodes(nameBytes)
              .replaceAll(RegExp(r'\u0000.*'), '')
              .trim();
          
          if (filename == 'LaunchMe' || filename == 'launchme' || filename == 'launch.me' || 
              filename == 'Launch.Me' || filename == 'launch' || filename == 'Launch' || 
              filename == 'takeme' || filename == 'LAUNCHME' || filename == 'LAUNCH.ME' || 
              filename == 'LAUNCH' || filename == 'Launchme' || filename == 'launchMe')  {
            // File found! Extract its information
            
            // File block location at offset 0x44
            final fileBlockLocation = (buffer[fsOffset + offset + 0x45] << 16) | 
                                   (buffer[fsOffset + offset + 0x46] << 8) | 
                                   buffer[fsOffset + offset + 0x47];
            
            // File size at offset 0x10
            final fileSize = (buffer[fsOffset + offset + 0x11] << 16) | 
                         (buffer[fsOffset + offset + 0x12] << 8) | 
                         buffer[fsOffset + offset + 0x13];
            
            return {
              'location': fileBlockLocation * blockSize,
              'size': fileSize
            };
          }
        }
        
        // Move to next entry
        // Extra copies count at offset 0x40
        final extraCopies = buffer[fsOffset + offset + 0x43];
        offset += 0x48 + extraCopies * 4;
      }
      
      // Check if there's a continuation to another sector
      offset = (buffer[fsOffset + 0x02] << 8) | buffer[fsOffset + 0x03];
      
      // No more sectors to search
      if (offset == 0xFFFF) {
        break;
      }
      
      // Get next sector
      offset *= blockSize;
      sector = (rootBlockLocation + offset) ~/ 2048;
    }
    
    return null;
  }
}