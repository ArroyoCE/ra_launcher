// File: lib/3do/hash_3do.dart

import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:retroachievements_organizer/services/hashing/chd_read_common.dart';

/// Hashing implementation for 3DO (Opera filesystem)
class Hash3DOCalculator {
  static const List<int> OPERA_FS_IDENTIFIER = [0x01, 0x5A, 0x5A, 0x5A, 0x5A, 0x5A, 0x01];
  
  /// Calculate hash for a 3DO disc
  /// Returns the MD5 hash as a hex string, or null if an error occurs
  static Future<String?> calculateHash(String filePath) async {
    final chdReader = ChdReader();
    
    if (!chdReader.isInitialized) {
      print('CHD library not initialized');
      return null;
    }
    
    // Process the CHD file to extract track info
    final result = await chdReader.processChdFile(filePath);
    
    if (!result.isSuccess) {
      print('Error processing CHD file: ${result.error}');
      return null;
    }
    
    // Find the first data track
    if (result.tracks.isEmpty) {
      print('No tracks found in CHD file');
      return null;
    }
    
    final track = result.tracks[0];
    print('Using track: $track');
    
    // Read the first sector to check for Opera filesystem
    Uint8List? sectorData = await chdReader.readSector(filePath, track, 0);
    if (sectorData == null) {
      print('Could not read first sector');
      return null;
    }
    
    // Debug output
    print('First 16 bytes of sector 0: ${_bytesToHex(sectorData.sublist(0, 16))}');
    
    // First look for the Opera filesystem AFTER the 16-byte sync pattern
    bool found = false;
    int fsOffset = track.dataOffset;
    
    if (track.dataOffset > 0 && sectorData.length >= track.dataOffset + OPERA_FS_IDENTIFIER.length) {
      found = _compareBytes(sectorData, track.dataOffset, 
                        Uint8List.fromList(OPERA_FS_IDENTIFIER), 0, 
                        OPERA_FS_IDENTIFIER.length);
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
      sectorData = await chdReader.readSector(filePath, track, 16);
      if (sectorData == null) {
        print('Could not read sector 16');
        return null;
      }
      
      print('First 16 bytes of sector 16: ${_bytesToHex(sectorData.sublist(0, 16))}');
      
      // First look for the Opera filesystem AFTER the 16-byte sync pattern
      if (track.dataOffset > 0 && sectorData.length >= track.dataOffset + OPERA_FS_IDENTIFIER.length) {
        found = _compareBytes(sectorData, track.dataOffset, 
                          Uint8List.fromList(OPERA_FS_IDENTIFIER), 0, 
                          OPERA_FS_IDENTIFIER.length);
        if (found) fsOffset = track.dataOffset;
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
    final launchMeInfo = await _findLaunchMeFile(chdReader, filePath, track, rootBlockLocation, blockSize, fsOffset);
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
      final buffer = await chdReader.readSector(filePath, track, sector);
      if (buffer == null) {
        print('Could not read sector $sector');
        return null;
      }
      
      final bytesToRead = remaining > track.dataSize ? track.dataSize : remaining;
      print('Adding $bytesToRead bytes from sector $sector');
      
      // Only add the data portion of the sector
      allBytes.addAll(buffer.sublist(fsOffset, fsOffset + bytesToRead));
      
      // Move to next sector
      sector++;
      remaining -= bytesToRead;
    }
    
    // Calculate the final hash
    final digest = crypto.md5.convert(allBytes);
    final hash = digest.toString();
    print('Final hash: $hash');
    
    return hash;
  }

  /// Helper method to convert bytes to hex for debugging
  static String _bytesToHex(List<int> bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
  }
  
  /// Extract the title from the volume header
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
  
  /// Get block size from header
  static int _getBlockSize(Uint8List header, int offset) {
    // Block size is at offset 0x4C (big-endian)
    return (header[offset + 0x4D] << 16) | (header[offset + 0x4E] << 8) | header[offset + 0x4F];
  }
  
  /// Get root directory block location from header
  static int _getRootBlockLocation(Uint8List header, int offset) {
    // Root directory block location is at offset 0x64 (big-endian)
    return (header[offset + 0x65] << 16) | (header[offset + 0x66] << 8) | header[offset + 0x67];
  }
  
  /// Compare byte sequences, similar to memcmp in C
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
  
  /// Find LaunchMe file in directory structure
  static Future<Map<String, dynamic>?> _findLaunchMeFile(
      ChdReader chdReader, 
      String filePath, 
      TrackInfo track, 
      int rootBlockLocation, 
      int blockSize,
      int fsOffset) async {
    
    // Calculate sector for the root directory
    int sector = rootBlockLocation ~/ 2048;
    
    print('Searching for LaunchMe in directory at sector: $sector');
    
    // Read the root directory sector
    while (true) {
      final buffer = await chdReader.readSector(filePath, track, sector);
      if (buffer == null) {
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
            
            // File block size at offset 0x0C (3 bytes)
            final fileBlockSize = (buffer[fsOffset + offset + 0x0D] << 16) | 
                               (buffer[fsOffset + offset + 0x0E] << 8) | 
                               buffer[fsOffset + offset + 0x0F];
            
            // File block location at offset 0x44 (3 bytes)
            final fileBlockLocation = (buffer[fsOffset + offset + 0x45] << 16) | 
                                   (buffer[fsOffset + offset + 0x46] << 8) | 
                                   buffer[fsOffset + offset + 0x47];
            
            // File size at offset 0x10 (3 bytes)
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

  /// Hash file contents
  static Future<crypto.Digest?> _hashFileContents(
      ChdReader chdReader, 
      String filePath, 
      TrackInfo track, 
      int fsOffset, 
      int blockLocation, 
      int fileSize) async {
    
    final md5 = crypto.md5;
    var digest = md5.convert([]);
    int sector = blockLocation ~/ 2048;
    int remaining = fileSize;
    
    while (remaining > 0) {
      final buffer = await chdReader.readSector(filePath, track, sector);
      if (buffer == null) {
        print('Could not read file sector');
        return null;
      }
      
      final bytesToHash = remaining > 2048 ? 2048 : remaining;
      final sectorData = buffer.sublist(fsOffset, fsOffset + bytesToHash);
      
      // Update digest with this sector
      digest = md5.convert([...digest.bytes, ...sectorData]);
      
      sector++;
      remaining -= bytesToHash;
    }
    
    return digest;
  }
}