// lib/services/hashing/dreamcast/dreamcast_hash_integration.dart
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:retroachievements_organizer/services/hashing/DC/dreamcast_chd_reader.dart';
import 'package:retroachievements_organizer/services/hashing/DC/dreamcast_disc_reader.dart';

class DreamcastHashIntegration {
  final DreamcastChdReader _chdReader = DreamcastChdReader();
  final DreamcastDiscReader _discReader = DreamcastDiscReader();
  
  Future<Map<String, String>> hashDreamcastFilesInFolders(
    List<String> folders, {
    Function(int current, int total)? progressCallback,
  }) async {
    final Map<String, String> hashes = {};
    final validExtensions = ['.gdi', '.cdi', '.chd', '.cue'];
    int processedFiles = 0;
    int totalFiles = 0;
    
    // Count total files first for progress reporting
    for (final folder in folders) {
      totalFiles += _countDreamcastFiles(folder, validExtensions);
    }
    
    for (final folder in folders) {
      final dir = Directory(folder);
      if (!await dir.exists()) continue;
      
      try {
        await for (final entity in dir.list(recursive: true)) {
          if (entity is File) {
            final path = entity.path;
            final extension = path.toLowerCase().split('.').last;
            
            // Check if file has a valid extension
            if (!validExtensions.any((ext) => path.toLowerCase().endsWith(ext))) {
              continue;
            }
            
            String? hash;
            
            try {
              // Process file based on extension
              if (extension == 'chd') {
                hash = await _chdReader.processFile(path);
              } else {
                hash = await _discReader.processFile(path, extension);
              }
              
              // If hash was generated successfully, add to map
              if (hash != null) {
                hashes[path] = hash;
                debugPrint('Generated Dreamcast hash for $path: $hash');
              }
            } catch (e) {
              debugPrint('Error hashing Dreamcast file $path: $e');
            }
            
            // Update progress
            processedFiles++;
            if (progressCallback != null) {
              progressCallback(processedFiles, totalFiles);
            }
          }
        }
      } catch (e) {
        debugPrint('Error processing Dreamcast files in folder $folder: $e');
      }
    }
    
    return hashes;
  }
  
  int _countDreamcastFiles(String folder, List<String> validExtensions) {
    int count = 0;
    try {
      final dir = Directory(folder);
      if (!dir.existsSync()) return 0;
      
      final List<FileSystemEntity> entities = dir.listSync(recursive: true);
      for (final entity in entities) {
        if (entity is File && 
            validExtensions.any((ext) => entity.path.toLowerCase().endsWith(ext))) {
          count++;
        }
      }
    } catch (e) {
      debugPrint('Error counting Dreamcast files: $e');
    }
    return count;
  }
}