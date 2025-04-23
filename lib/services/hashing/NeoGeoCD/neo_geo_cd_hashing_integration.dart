// lib/services/hashing/NeoGeoCD/neo_geo_cd_hash_integration.dart
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:retroachievements_organizer/services/hashing/CHD/chd_read_common.dart';
import 'package:retroachievements_organizer/services/hashing/NeoGeoCD/file_utils.dart';
import 'package:retroachievements_organizer/services/hashing/NeoGeoCD/neo_geo_cd_hash_generator.dart';

class NeoGeocdHashIntegration {
  /// Hash Neo Geo CD files in the specified folders
  Future<Map<String, String>> hashNeoGeocdFilesInFolders(
    List<String> folders, {
    Function(int current, int total)? progressCallback,
  }) async {
    Map<String, String> hashes = {};
    List<FileSystemEntity> allFiles = [];
    
    // Collect all files from the folders
    for (final folder in folders) {
      debugPrint('Scanning folder: $folder');
      final files = await FileUtils.getFilesInFolder(folder, 
          extensions: ['cue', 'chd', 'm3u', 'iso', 'bin']);
      allFiles.addAll(files);
      debugPrint('Found ${files.length} potential Neo Geo CD files in $folder');
    }
    
    final total = allFiles.length;
    int current = 0;
    
    for (final file in allFiles) {
      try {
        current++;
        if (progressCallback != null) {
          progressCallback(current, total);
        }
        
        debugPrint('Processing Neo Geo CD file ($current/$total): ${file.path}');
        final hash = await hashNeoGeocdFile(file.path);
        if (hash != null && hash.isNotEmpty) {
          hashes[file.path] = hash;
          debugPrint('Neo Geo CD hash for ${file.path}: $hash');
        } else {
          debugPrint('Failed to generate hash for ${file.path}');
        }
      } catch (e) {
        debugPrint('Error hashing Neo Geo CD file ${file.path}: $e');
      }
    }
    
    debugPrint('Generated ${hashes.length} hashes for Neo Geo CD files');
    return hashes;
  }
  
  /// Generate a hash for a Neo Geo CD file
  Future<String?> hashNeoGeocdFile(String filePath) async {
    final extension = path.extension(filePath).toLowerCase().replaceFirst('.', '');
    final hashGenerator = NeoGeoCdHashGenerator();
    
    try {
      debugPrint('Hashing Neo Geo CD file: $filePath (extension: $extension)');
      
      if (extension == 'chd') {
        // Process CHD file
        final chdReader = ChdReader();
        final chdResult = await chdReader.processChdFile(filePath);
        
        if (!chdResult.isSuccess) {
          debugPrint('Failed to process CHD file: ${chdResult.error}');
          return null;
        }
        
        return await hashGenerator.hashFromChd(filePath, chdResult);
      } else if (extension == 'cue') {
        // Process CUE file
        return await hashGenerator.hashFromCue(filePath);
      } else if (extension == 'm3u') {
        // Process M3U playlist
        final firstItem = await FileUtils.getFirstItemFromPlaylist(filePath);
        if (firstItem != null) {
          debugPrint('Processing first item from M3U playlist: $firstItem');
          return await hashNeoGeocdFile(firstItem);
        } else {
          debugPrint('No valid items found in M3U playlist: $filePath');
        }
      } else if (extension == 'iso') {
        // For ISO files, we can create a simple track info and hash it
        return await hashGenerator.hashFromCue(filePath);
      } else if (extension == 'bin') {
        // Check if there's a corresponding CUE file
        final cueFilePath = path.join(
          path.dirname(filePath),
          '${path.basenameWithoutExtension(filePath)}.cue'
        );
        
        if (File(cueFilePath).existsSync()) {
          debugPrint('Found corresponding CUE file: $cueFilePath');
          return await hashNeoGeocdFile(cueFilePath);
        } else {
          debugPrint('No corresponding CUE file found for BIN: $filePath');
          // Try to hash the BIN directly as a data track
          return await hashGenerator.hashFromCue(filePath);
        }
      }
    } catch (e) {
      debugPrint('Error generating Neo Geo CD hash: $e');
    }
    
    return null;
  }
}