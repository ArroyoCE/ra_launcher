import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:retroachievements_organizer/services/hashing/PCECD/pcfx_hashing.dart';

/// PC-FX hash integration
class PCFXHashIntegration {
  /// Hash PC-FX files in the given folders
  Future<Map<String, String>> hashPCFXFilesInFolders(
    List<String> folders,
    {void Function(int current, int total)? progressCallback}
  ) async {
    debugPrint('Starting PC-FX hashing in ${folders.length} folders');
    
    final Map<String, String> hashes = {};
    
    try {
      // Find all disc files
      final allFiles = await _findDiscFiles(folders);
      final total = allFiles.length;
      
      debugPrint('Found ${allFiles.length} PC-FX files to process');
      
      // Process each file
      for (int i = 0; i < allFiles.length; i++) {
        final filePath = allFiles[i];
        
        // Skip M3U playlists - we'll process the individual files
        if (filePath.toLowerCase().endsWith('.m3u')) {
          debugPrint('Skipping M3U file: $filePath');
          continue;
        }
        
        try {
          // Use the PCFXHasher from pcfx_hashing.dart
          final hash = await PCFXHasher.hashFile(filePath);
          
          if (hash != null && hash.isNotEmpty) {
            hashes[filePath] = hash;
            debugPrint('Successfully hashed: $filePath -> $hash');
          } else {
            debugPrint('Failed to hash: $filePath');
          }
        } catch (e) {
          debugPrint('Error processing $filePath: $e');
        }
        
        // Update progress
        if (progressCallback != null) {
          progressCallback(i + 1, total);
        }
      }
      
      debugPrint('Completed hashing ${hashes.length} out of $total files');
      return hashes;
    } catch (e) {
      debugPrint('Error in hashFilesInFolders: $e');
      return hashes;
    }
  }
  
  /// Find disc files with specific extensions in folders
  Future<List<String>> _findDiscFiles(List<String> folders) async {
    final List<String> result = [];
    final validExtensions = ['.cue', '.bin', '.img', '.chd', '.iso'];
    
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
            if (validExtensions.any((ext) => lowerPath.endsWith(ext))) {
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