// File: lib/3do/hash_3do_main.dart

import 'dart:io';

import 'package:retroachievements_organizer/services/hashing/3do/hash_3do_cue.dart';
import 'package:retroachievements_organizer/services/hashing/3do/isolate_3do_chd_processor.dart';

/// Class to handle 3DO hashing operations
/// Class to handle 3DO hashing operations
class ThreeDOHashIntegration {
  /// Hash 3DO files in multiple folders
  /// Returns a map of file paths to their hashes
  Future<Map<String, String>> hash3DOFilesInFolders(List<String> folders) async {
    final Map<String, String> hashes = {};
    
    for (final folder in folders) {
      final directory = Directory(folder);
      if (!await directory.exists()) {
        continue;
      }
      
      // Process files in directory
      await for (final entity in directory.list(recursive: true)) {
        if (entity is File) {
          final filePath = entity.path;
          final extension = filePath.toLowerCase().split('.').last;
          
          // Process CHD, CUE, BIN, and ISO files
          if (extension == 'chd' || extension == 'cue' || extension == 'bin' || extension == 'iso') {
            // Calculate hash for the file
            final hash = await Hash3DO.calculateHash(filePath);
            
            if (hash != null) {
              hashes[filePath] = hash;
            }
          }
        }
      }
    }
    
    return hashes;
  }
}

/// Main class to calculate 3DO hashes
class Hash3DO {
  /// Calculate hash for a 3DO disc (supports CHD, CUE, BIN, and ISO formats)
  /// Returns the MD5 hash as a hex string, or null if an error occurs
  static Future<String?> calculateHash(String filePath) async {
    final extension = filePath.toLowerCase().split('.').last;
    
    switch (extension) {
      case 'chd':
        // Use the isolate processor for CHD files to prevent UI freezing
        return Isolate3DOChdProcessor.processChd(filePath);
        
      case 'cue':
      case 'bin':
      case 'iso':
        // Use the unified hash calculator for CUE, BIN and ISO files
        return Hash3DOCalculator.calculateHash(filePath);
        
      default:
        return null;
    }
  }
}