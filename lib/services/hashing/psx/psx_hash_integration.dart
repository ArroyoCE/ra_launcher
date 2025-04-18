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
  
  // Cache for quick lookup of already processed folders
  final Map<String, List<File>> _folderCache = {};
  
  /// Hash PlayStation files in the given folders
  Future<Map<String, String>> hashPsxFilesInFolders(List<String> folders) async {
    final Map<String, String> hashes = {};
    final List<String> validExtensions = ['.chd', '.cue'];
    const int BATCH_SIZE = 5; // Increase batch size for better throughput
    
    // Check if folders list is empty
    if (folders.isEmpty) {
      return hashes;
    }

    try {
      // Collect all files first - with caching for improved performance
      final List<File> filesToHash = [];
      
      for (final folderPath in folders) {
        // Check if folder is in cache
        if (_folderCache.containsKey(folderPath)) {
          filesToHash.addAll(_folderCache[folderPath]!);
          continue;
        }
        
        final directory = Directory(folderPath);
        final List<File> folderFiles = [];
        
        if (await directory.exists()) {
          await for (final entity in directory.list(recursive: true)) {
            if (entity is File) {
              final extension = path.extension(entity.path).toLowerCase();
              if (validExtensions.contains(extension)) {
                folderFiles.add(entity);
                filesToHash.add(entity);
              }
            }
          }
          
          // Cache folder contents for future calls
          _folderCache[folderPath] = folderFiles;
        }
      }
      
      // Sort files by extension - process smaller files first for quicker feedback
      filesToHash.sort((a, b) {
        // CHD files are typically larger, so prioritize CUE files
        final extA = path.extension(a.path).toLowerCase();
        final extB = path.extension(b.path).toLowerCase();
        
        if (extA == extB) {
          // If same extension, sort by file size
          return a.lengthSync().compareTo(b.lengthSync());
        }
        
        return extA == '.cue' ? -1 : 1;
      });
      
      // Allow UI to update before starting hash process
      await Future.microtask(() => null);
      
      // Process files in batches
      for (int i = 0; i < filesToHash.length; i += BATCH_SIZE) {
        final endIndex = (i + BATCH_SIZE < filesToHash.length) ? i + BATCH_SIZE : filesToHash.length;
        final batch = filesToHash.sublist(i, endIndex);
        
        // Process this batch of files in parallel
        final results = await Future.wait(
          batch.map((file) async {
            try {
              // Minimal logging to improve performance
              if (i % 10 == 0) {
                debugPrint('Hashing PSX file (${i + batch.indexOf(file) + 1}/${filesToHash.length}): ${path.basename(file.path)}');
              }
              
              String? fileHash = await _psxHashService.hashPsxFile(file.path);
              
              if (fileHash != null) {
                return MapEntry(file.path, fileHash);
              }
            } catch (e) {
              // Only log critical errors
              debugPrint('Error hashing file ${path.basename(file.path)}: ${e.toString().substring(0, min(50, e.toString().length))}...');
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
        
        // Only yield to UI for meaningful refresh intervals (every 10 files)
        if (i % 10 == 0) {
          await Future.delayed(const Duration(milliseconds: 25));
        }
      }
      
      return hashes;
    } catch (e) {
      debugPrint('Error hashing PlayStation files: $e');
      return hashes;
    }
  }
  
  // Helper function for min value
  int min(int a, int b) => a < b ? a : b;
}