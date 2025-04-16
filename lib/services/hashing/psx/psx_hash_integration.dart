// lib/services/hashing/psx_hash_integration.dart
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

import 'psx_hash_service.dart';

/// Integration with the main hashing system
class PsxHashIntegration {
  static final PsxHashIntegration _instance = PsxHashIntegration._internal();
  
  factory PsxHashIntegration() {
    return _instance;
  }
  
  PsxHashIntegration._internal();
  
  late final PsxHashService _psxHashService = PsxHashService();
  
  /// Hash PlayStation files in the given folders
  Future<Map<String, String>> hashPsxFilesInFolders(List<String> folders) async {
  final Map<String, String> hashes = {};
  final List<String> validExtensions = ['.chd', '.cue'];
  const int BATCH_SIZE = 3; // Process 3 files at a time
  
  // Check if folders list is empty
  if (folders.isEmpty) {
    return hashes;
  }

  try {
    // Collect all files first
    final List<File> filesToHash = [];
    
    for (final folderPath in folders) {
      final directory = Directory(folderPath);
      
      if (await directory.exists()) {
        await for (final entity in directory.list(recursive: true)) {
          if (entity is File) {
            final extension = path.extension(entity.path).toLowerCase();
            if (validExtensions.contains(extension)) {
              filesToHash.add(entity);
            }
          }
        }
      }
    }
    
    // Allow UI to update before starting hash process
    await Future.microtask(() => null);
    
    // Process files in batches
    for (int i = 0; i < filesToHash.length; i += BATCH_SIZE) {
      final endIndex = (i + BATCH_SIZE < filesToHash.length) ? i + BATCH_SIZE : filesToHash.length;
      final batch = filesToHash.sublist(i, endIndex);
      
      // Process this batch of files
      final results = await Future.wait(
        batch.map((file) async {
          try {
            debugPrint('Hashing PSX file (${i + batch.indexOf(file) + 1}/${filesToHash.length}): ${file.path}');
            String? fileHash = await _psxHashService.hashPsxFile(file.path);
            
            if (fileHash != null) {
              return MapEntry(file.path, fileHash);
            }
          } catch (e) {
            debugPrint('Error hashing file ${file.path}: $e');
          }
          return null;
        }),
      );
      
      // Add the results to our hash map
      for (var entry in results) {
        if (entry != null) {
          hashes[entry.key] = entry.value;
        }
      }
      
      // Allow UI to update after each batch
      await Future.delayed(const Duration(milliseconds: 50));
    }
    
    return hashes;
  } catch (e) {
    debugPrint('Error hashing PlayStation files: $e');
    return hashes;
  }
}

}