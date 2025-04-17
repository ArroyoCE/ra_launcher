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
      return null;
    }
    
    // Process the CHD file to extract track info
    final result = await chdReader.processChdFile(filePath);
    
    if (!result.isSuccess) {
      return null;
    }
    
    // Find the first data track
    if (result.tracks.isEmpty) {
      return null;
    }
    
    final track = result.tracks[0];
    
    // Read the first sector to check for Opera filesystem
    Uint8List? sectorData = await chdReader.readSector(filePath, track, 0);
    if (sectorData == null) {
      return null;
    }
    
    // Debug output
    
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
      sectorData = await chdReader.readSector(filePath, track, 16);
      if (sectorData == null) {
        return null;
      }
      
      
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
    final launchMeInfo = await _findLaunchMeFile(chdReader, filePath, track, rootBlockLocation, blockSize, fsOffset);
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
      final buffer = await chdReader.readSector(filePath, track, sector);
      if (buffer == null) {
        return null;
      }
      
      final bytesToRead = remaining > track.dataSize ? track.dataSize : remaining;
      
      // Only add the data portion of the sector
      allBytes.addAll(buffer.sublist(fsOffset, fsOffset + bytesToRead));
      
      // Move to next sector
      sector++;
      remaining -= bytesToRead;
    }
    
    // Calculate the final hash
    final digest = crypto.md5.convert(allBytes);
    final hash = digest.toString();
    
    return hash;
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
    
    
    // Read the root directory sector
    while (true) {
      final buffer = await chdReader.readSector(filePath, track, sector);
      if (buffer == null) {
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
          
          
          if (filename == 'LaunchMe' || filename == 'launchme' || filename == 'launch.me' || filename == 'Launch.Me' || filename == 'launch' || filename == 'Launch' || filename == 'takeme' || filename == 'LAUNCHME' || filename == 'LAUNCH.ME' || filename == 'LAUNCH' || filename == 'Launchme' || filename == 'launchMe'  )  {
            // File found! Extract its information
            
            // File block size at offset 0x0C (3 bytes)
            
            // File block location at offset 0x44 (3 bytes)
            final fileBlockLocation = (buffer[fsOffset + offset + 0x45] << 16) | 
                                   (buffer[fsOffset + offset + 0x46] << 8) | 
                                   buffer[fsOffset + offset + 0x47];
            
            // File size at offset 0x10 (3 bytes)
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