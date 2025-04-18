// arduboy_hash.dart

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

/// Class to handle Arduboy game hashing specifically
class ArduboyHashIntegration {
  /// Hashes all Arduboy games (.hex files) in the provided folders
  /// Returns a map of file paths to MD5 hashes
  Future<Map<String, String>> hashArduboyFilesInFolders(List<String> folders) async {
    debugPrint('Starting Arduboy hashing, this might take some time...');
    
    final Map<String, String> arduboyHashes = {};
    
    for (final folderPath in folders) {
      final directory = Directory(folderPath);
      
      if (await directory.exists()) {
        await for (final entity in directory.list(recursive: true)) {
          if (entity is File) {
            final extension = path.extension(entity.path).toLowerCase();
            
            // Only process .hex files for Arduboy
            if (extension == '.hex') {
              try {
                // Read the file as text since Intel HEX is a text format
                final String hexContent = await entity.readAsString();
                
                // Normalize the line endings to Unix style (LF only)
                final String normalizedContent = normalizeLineEndings(hexContent);
                
                // Hash the normalized text content directly
                final hashBytes = md5.convert(utf8.encode(normalizedContent)).bytes;
                final hash = hashBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
                
                arduboyHashes[entity.path] = hash;
                debugPrint('Hashed Arduboy file: ${entity.path} -> $hash');
              } catch (e) {
                debugPrint('Error hashing Arduboy file ${entity.path}: $e');
              }
            }
          }
        }
      }
    }
    
    return arduboyHashes;
  }

  /// Normalizes line endings to Unix style (LF only)
  String normalizeLineEndings(String text) {
    // Replace Windows style (CRLF) with Unix style (LF)
    String normalized = text.replaceAll('\r\n', '\n');
    
    // Replace any remaining Mac style (CR) with Unix style (LF)
    normalized = normalized.replaceAll('\r', '\n');
    
    return normalized;
  }
}