// lib/services/hashing/n64/n64_hash_integration.dart
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

/// Class to handle Nintendo 64 ROM hashing
class N64HashIntegration {
  /// Hashes Nintendo 64 ROM files found in the provided folders.
  /// 
  /// Returns a map where keys are file paths and values are the calculated hash strings.
  /// The hash is calculated based on the specific Nintendo 64 ROM format.
  Future<Map<String, String>> hashN64FilesInFolders(List<String> folders) async {
    final Map<String, String> hashes = {};
    final validExtensions = ['.n64', '.z64', '.v64', '.ndd'];
    
    debugPrint('Starting Nintendo 64 hashing for ${folders.length} folders');
    
    for (final folderPath in folders) {
      final directory = Directory(folderPath);
      
      if (await directory.exists()) {
        await for (final entity in directory.list(recursive: true)) {
          if (entity is File) {
            final extension = path.extension(entity.path).toLowerCase();
            
            // Check if file has a valid N64 ROM extension
            if (validExtensions.contains(extension)) {
              try {
                final hash = await _hashN64File(entity);
                if (hash != null) {
                  hashes[entity.path] = hash;
                  debugPrint('Hashed N64 file: ${entity.path} -> $hash');
                }
              } catch (e) {
                debugPrint('Error hashing N64 file ${entity.path}: $e');
              }
            }
          }
        }
      }
    }
    
    debugPrint('Completed Nintendo 64 hashing, found ${hashes.length} files');
    return hashes;
  }
  
  /// Hashes a single Nintendo 64 ROM file.
  /// 
  /// The hashing process handles different ROM formats (Z64, V64, N64)
  /// and extracts the correct portion of the ROM for hashing.
  Future<String?> _hashN64File(File file) async {
    try {
      // Read the first part of the file to determine format
      final fileLength = await file.length();
      if (fileLength < 0x40) {
        debugPrint('File too small to be a valid N64 ROM: ${file.path}');
        return null;
      }
      
      // Read enough of the file for hashing
      final bytesToRead = (fileLength > 64 * 1024 * 1024) ? 64 * 1024 * 1024 : fileLength;
      final bytes = await file.openRead(0, bytesToRead).toList();
      
      // Combine the chunks into a single buffer
      final buffer = Uint8List(bytesToRead);
      int offset = 0;
      for (final chunk in bytes) {
        buffer.setRange(offset, offset + chunk.length, chunk);
        offset += chunk.length;
      }
      
      // Determine the ROM format based on the first 4 bytes
      final format = _determineRomFormat(buffer);
      if (format == null) {
        debugPrint('Unknown N64 ROM format for file: ${file.path}');
        return null;
      }
      
      // Convert to Z64 format (big-endian) if needed
      Uint8List hashBuffer;
      if (format == 'Z64') {
        // Already in the correct format
        hashBuffer = buffer;
      } else if (format == 'V64') {
        // V64 format (byte-swapped)
        hashBuffer = _byteswap16(buffer);
      } else if (format == 'N64') {
        // N64 format (word-swapped)
        hashBuffer = _byteswap32(buffer);
      } else {
        return null;
      }
      
      // Get MD5 hash
      final digest = md5.convert(hashBuffer);
      return digest.toString();
      
    } catch (e) {
      debugPrint('Error processing N64 ROM: $e');
      return null;
    }
  }
  
  /// Determines the format of the N64 ROM from the header.
  /// Returns 'Z64', 'V64', 'N64', or null if unknown.
  String? _determineRomFormat(Uint8List buffer) {
    if (buffer.length < 4) return null;
    
    // Check magic values at the start of the ROM
    final first4Bytes = buffer.sublist(0, 4);
    
    // Z64 format (big-endian)
    if (first4Bytes[0] == 0x80 && first4Bytes[1] == 0x37 && 
        first4Bytes[2] == 0x12 && first4Bytes[3] == 0x40) {
      return 'Z64';
    }
    
    // V64 format (byte-swapped)
    if (first4Bytes[0] == 0x37 && first4Bytes[1] == 0x80 && 
        first4Bytes[2] == 0x40 && first4Bytes[3] == 0x12) {
      return 'V64';
    }
    
    // N64 format (word-swapped)
    if (first4Bytes[0] == 0x40 && first4Bytes[1] == 0x12 && 
        first4Bytes[2] == 0x37 && first4Bytes[3] == 0x80) {
      return 'N64';
    }
    
    // Unknown format
    debugPrint('Unknown N64 ROM format. First 4 bytes: ${first4Bytes[0].toRadixString(16)} ${first4Bytes[1].toRadixString(16)} ${first4Bytes[2].toRadixString(16)} ${first4Bytes[3].toRadixString(16)}');
    return null;
  }
  
  /// Performs a 16-bit byte swap operation (for V64 format)
  Uint8List _byteswap16(Uint8List buffer) {
    final result = Uint8List(buffer.length);
    
    for (int i = 0; i < buffer.length - 1; i += 2) {
      result[i] = buffer[i + 1];
      result[i + 1] = buffer[i];
    }
    
    // If odd length, copy the last byte as is
    if (buffer.length % 2 != 0) {
      result[buffer.length - 1] = buffer[buffer.length - 1];
    }
    
    return result;
  }
  
  /// Performs a 32-bit byte swap operation (for N64 format)
  Uint8List _byteswap32(Uint8List buffer) {
    final result = Uint8List(buffer.length);
    
    for (int i = 0; i < buffer.length - 3; i += 4) {
      result[i] = buffer[i + 3];
      result[i + 1] = buffer[i + 2];
      result[i + 2] = buffer[i + 1];
      result[i + 3] = buffer[i];
    }
    
    // Handle remaining bytes if length is not a multiple of 4
    final remainder = buffer.length % 4;
    if (remainder > 0) {
      for (int i = 0; i < remainder; i++) {
        result[buffer.length - remainder + i] = buffer[buffer.length - remainder + i];
      }
    }
    
    return result;
  }
}