// File: lib/3do/hash_3do_cue.dart

import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:path/path.dart' as path;

/// Handler for 3DO CUE files
class Hash3DOCueCalculator {
  static const List<int> OPERA_FS_IDENTIFIER = [0x01, 0x5A, 0x5A, 0x5A, 0x5A, 0x5A, 0x01];
  
  static Future<bool> _addFileContentsToList(
    RandomAccessFile fileHandle, 
    int sectorSize,
    int fsOffset,
    int blockLocation, 
    int fileSize,
    List<int> allBytes) async {
  
    int sector = blockLocation ~/ 2048;
    int remaining = fileSize;
    
    while (remaining > 0) {
      await fileHandle.setPosition(sector * sectorSize);
      final buffer = Uint8List(sectorSize);
      final bytesRead = await fileHandle.readInto(buffer);
      
      if (bytesRead < sectorSize) {
        print('Could not read file sector');
        return false;
      }
      
      final bytesToAdd = remaining > 2048 ? 2048 : remaining;
      print('Adding $bytesToAdd bytes from sector $sector');
      
      final sectorData = buffer.sublist(fsOffset, fsOffset + bytesToAdd);
      
      // Add data to the list
      allBytes.addAll(sectorData);
      
      sector++;
      remaining -= bytesToAdd;
    }
    
    return true;
  }

  /// Calculate hash for a 3DO CUE file
  /// Returns the MD5 hash as a hex string, or null if an error occurs
  static Future<String?> calculateHash(String cuePath) async {
    // Parse the CUE file to find the associated BIN file
    final File cueFile = File(cuePath);
    if (!await cueFile.exists()) {
      print('CUE file not found: $cuePath');
      return null;
    }
    
    final String cueContent = await cueFile.readAsString();
    final String? binPath = _extractBinPath(cueContent, cuePath);
    
    if (binPath == null) {
      print('Could not find BIN file in CUE: $cuePath');
      return null;
    }
    
    print('Looking for BIN file at: $binPath');
    
    final File binFile = File(binPath);
    if (!await binFile.exists()) {
      print('BIN file not found: $binPath');
      return null;
    }
    
    // Open the BIN file and read the first sector
    final RandomAccessFile binHandle = await binFile.open(mode: FileMode.read);
    
    try {
      // Determine track type and sector size from CUE
      final trackInfo = _extractTrackInfo(cueContent);
      final int sectorSize = trackInfo['sectorSize'] ?? 2352;
      final int dataOffset = trackInfo['mode'] == 1 ? 16 : 0;
      
      print('Using sector size: $sectorSize, data offset: $dataOffset');
      
      // Read the first sector to check for Opera filesystem
      final Uint8List sectorData = Uint8List(sectorSize);
      final int bytesRead = await binHandle.readInto(sectorData);
      
      if (bytesRead < sectorSize) {
        print('Could not read first sector');
        return null;
      }
      
      // Debug output
      print('First 16 bytes of sector: ${_bytesToHex(sectorData.sublist(0, 16))}');
      
      // First look for the Opera filesystem AFTER the 16-byte sync pattern if MODE1
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
        print('Opera filesystem not found at standard offset, scanning sector...');
        for (int i = 0; i < sectorData.length - OPERA_FS_IDENTIFIER.length; i++) {
          if (_compareBytes(sectorData, i, Uint8List.fromList(OPERA_FS_IDENTIFIER), 0, OPERA_FS_IDENTIFIER.length)) {
            print('Found Opera filesystem at offset $i');
            found = true;
            fsOffset = i;
            break;
          }
        }
      }
      
      // If still not found, try sector 16 (sometimes used as start sector)
      if (!found) {
        print('Opera filesystem not found in sector 0, trying sector 16...');
        await binHandle.setPosition(16 * sectorSize);
        final bytesRead = await binHandle.readInto(sectorData);
        
        if (bytesRead < sectorSize) {
          print('Could not read sector 16');
          return null;
        }
        
        print('First 16 bytes of sector 16: ${_bytesToHex(sectorData.sublist(0, 16))}');
        
        // First look for the Opera filesystem AFTER the 16-byte sync pattern if MODE1
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
              print('Found Opera filesystem at offset $i in sector 16');
              found = true;
              fsOffset = i;
              break;
            }
          }
        }
      }
      
      if (!found) {
        print('Not a 3DO CD (Opera filesystem not found)');
        return null;
      }
      
      print('Found 3DO CD, title: ${_extractTitle(sectorData, fsOffset)}');
      
      // Parse the block size and root directory location from the header
      final blockSize = _getBlockSize(sectorData, fsOffset);
      final rootBlockLocation = _getRootBlockLocation(sectorData, fsOffset) * blockSize;
      
      print('Block size: $blockSize, Root directory location: $rootBlockLocation');
      
      // Find the LaunchMe file
      final launchMeInfo = await _findLaunchMeFile(binHandle, sectorSize, fsOffset, rootBlockLocation, blockSize);
      if (launchMeInfo == null) {
        print('Could not find LaunchMe file');
        return null;
      }
      
      final launchMeLocation = launchMeInfo['location'] as int;
      final launchMeSize = launchMeInfo['size'] as int;
      
      print('Found LaunchMe file at block location: $launchMeLocation, size: $launchMeSize');
      
      // Create a list to hold all bytes to hash
      final List<int> allBytes = [];
      
      // First add the volume header (132 bytes)
      print('Adding 132-byte volume header to hash');
      allBytes.addAll(sectorData.sublist(fsOffset, fsOffset + 132));
      
      // Then add the LaunchMe file contents
      print('Adding LaunchMe file contents to hash');
      
      int sector = launchMeLocation ~/ 2048;
      int remaining = launchMeSize;
      
      while (remaining > 0) {
        await binHandle.setPosition(sector * sectorSize);
        final buffer = Uint8List(sectorSize);
        final bytesRead = await binHandle.readInto(buffer);
        
        if (bytesRead < sectorSize) {
          print('Could not read file sector');
          return null;
        }
        
        final bytesToHash = remaining > 2048 ? 2048 : remaining;
        print('Adding $bytesToHash bytes from sector $sector');
        
        final sectorData = buffer.sublist(fsOffset, fsOffset + bytesToHash);
        
        // Add data to the list
        allBytes.addAll(sectorData);
        
        sector++;
        remaining -= bytesToHash;
      }
      
      // Calculate the final hash
      final md5 = crypto.md5;
      final finalDigest = md5.convert(allBytes);
      
      print('Final hash: ${finalDigest.toString()}');
      return finalDigest.toString();
      
    } finally {
      await binHandle.close();
    }
  }

  /// Helper method to convert bytes to hex for debugging
  static String _bytesToHex(List<int> bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
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
  
  /// Extract track information from the CUE content
  static Map<String, int> _extractTrackInfo(String cueContent) {
    final RegExp trackRegex = RegExp(r'TRACK\s+01\s+MODE([12])/(\d+)', caseSensitive: false);
    final match = trackRegex.firstMatch(cueContent);
    
    final result = <String, int>{
      'mode': 1,      // Default: MODE1
      'sectorSize': 2352  // Default: 2352 bytes
    };
    
    if (match != null) {
      result['mode'] = int.parse(match.group(1)!);
      result['sectorSize'] = int.parse(match.group(2)!);
      
      // For MODE1, data starts after 16-byte header
      if (result['mode'] == 1) {
        result['dataOffset'] = 16;
        result['dataSize'] = 2048;
      } else {
        result['dataOffset'] = 0;
        result['dataSize'] = result['sectorSize']!;
      }
    }
    
    return result;
  }
  
  // The rest of the helper methods (similar to the CHD version but adapted for direct file access)
  static String _extractTitle(Uint8List sectorData, int offset) {
    if (sectorData.length < offset + 0x48) return '';
    
    // Title is at offset 0x28, max 32 bytes
    final titleBytes = sectorData.sublist(offset + 0x28, offset + 0x28 + 32);
    
    // Convert to string and trim nulls/spaces
    final String title = String.fromCharCodes(titleBytes)
        .replaceAll(RegExp(r'\u0000.*'), '')
        .trim();
    
    return title;
  }
  
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
    
    print('Searching for LaunchMe in directory at sector: $sector');
    
    // Read the root directory sector
    while (true) {
      await fileHandle.setPosition(sector * sectorSize);
      final buffer = Uint8List(sectorSize);
      final bytesRead = await fileHandle.readInto(buffer);
      
      if (bytesRead < sectorSize) {
        print('Could not read directory sector');
        return null;
      }
      
      // Offset to start of entries is at offset 0x10
      int offset = (buffer[fsOffset + 0x12] << 8) | buffer[fsOffset + 0x13];
      
      // Offset to end of entries is at offset 0x0C
       int stop = (buffer[fsOffset + 0x0D] << 16) | 
                (buffer[fsOffset + 0x0E] << 8) | 
                buffer[fsOffset + 0x0F];
      
      print('Directory entries from offset $offset to $stop');
      
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
          
          print('Found file: $filename');
          
         if (filename == 'LaunchMe' || filename == 'launchme' || filename == 'launch.me' || filename == 'Launch.Me' || filename == 'launch' || filename == 'Launch' || filename == 'takeme' || filename == 'LAUNCHME' || filename == 'LAUNCH.ME' || filename == 'LAUNCH' || filename == 'Launchme' || filename == 'launchMe'  )  {
            // File found! Extract its information
            
            // File block size at offset 0x0C
            final fileBlockSize = (buffer[fsOffset + offset + 0x0D] << 16) | 
                               (buffer[fsOffset + offset + 0x0E] << 8) | 
                               buffer[fsOffset + offset + 0x0F];
            
            // File block location at offset 0x44
            final fileBlockLocation = (buffer[fsOffset + offset + 0x45] << 16) | 
                                   (buffer[fsOffset + offset + 0x46] << 8) | 
                                   buffer[fsOffset + offset + 0x47];
            
            // File size at offset 0x10
            final fileSize = (buffer[fsOffset + offset + 0x11] << 16) | 
                         (buffer[fsOffset + offset + 0x12] << 8) | 
                         buffer[fsOffset + offset + 0x13];
            
            print('LaunchMe found: blockLocation=$fileBlockLocation, blockSize=$fileBlockSize, fileSize=$fileSize');
            
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
        print('End of directory reached without finding LaunchMe');
        break;
      }
      
      // Get next sector
      print('Following directory continuation to offset $offset');
      offset *= blockSize;
      sector = (rootBlockLocation + offset) ~/ 2048;
    }
    
    return null;
  }
  
  static Future<crypto.Digest?> _hashFileContents(
      RandomAccessFile fileHandle, 
      int sectorSize,
      int fsOffset,
      int blockLocation, 
      int fileSize) async {
    
    final md5 = crypto.md5;
    var digest = md5.convert([]);
    int sector = blockLocation ~/ 2048;
    int remaining = fileSize;
    
    while (remaining > 0) {
      await fileHandle.setPosition(sector * sectorSize);
      final buffer = Uint8List(sectorSize);
      final bytesRead = await fileHandle.readInto(buffer);
      
      if (bytesRead < sectorSize) {
        print('Could not read file sector');
        return null;
      }
      
      final bytesToHash = remaining > 2048 ? 2048 : remaining;
      print('Adding $bytesToHash bytes from sector $sector');
      
      final sectorData = buffer.sublist(fsOffset, fsOffset + bytesToHash);
      
      // Update digest with this sector
      digest = md5.convert([...digest.bytes, ...sectorData]);
      
      sector++;
      remaining -= bytesToHash;
    }
    
    return digest;
  }
}