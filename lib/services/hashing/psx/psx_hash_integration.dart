// FILE: psx_hash_integration.dart
// lib/services/hashing/psx_hash_integration.dart
import 'dart:io';
import 'dart:math'; // Import math for min function

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
    // INCREASED BATCH SIZE
    const int BATCH_SIZE = 10; // Process more files in parallel

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
           // Use try-catch for directory listing to handle permission errors gracefully
          try {
            await for (final entity in directory.list(recursive: true, followLinks: false)) { // Avoid following links
              if (entity is File) {
                final extension = path.extension(entity.path).toLowerCase();
                if (validExtensions.contains(extension)) {
                  folderFiles.add(entity);
                  // Add directly to filesToHash to avoid double iteration
                  filesToHash.add(entity);
                }
              }
            }
          } catch (e) {
             debugPrint("Error listing directory $folderPath: $e");
             // Continue with other folders even if one fails
          }


          // Cache folder contents for future calls
          _folderCache[folderPath] = folderFiles;
        } else {
            debugPrint("Directory not found: $folderPath");
        }
      }


       // --- Sorting Logic ---
       // Sort files primarily by type (CUE first), then by size (smallest first)
      filesToHash.sort((a, b) {
        final extA = path.extension(a.path).toLowerCase();
        final extB = path.extension(b.path).toLowerCase();

        // Prioritize CUE files
        if (extA == '.cue' && extB != '.cue') return -1;
        if (extA != '.cue' && extB == '.cue') return 1;

        // If extensions are the same (both CUE or both CHD), sort by size
        try {
          final sizeA = a.lengthSync();
          final sizeB = b.lengthSync();
          return sizeA.compareTo(sizeB);
        } catch (e) {
          // Handle potential error during lengthSync (e.g., file removed)
          debugPrint("Error getting length for sorting: $e");
          return 0; // Keep original order if size cannot be determined
        }
      });
      // --- End Sorting Logic ---


      // Allow UI to update before starting potentially long hash process
      await Future.microtask(() => null);


      // Process files in batches
      for (int i = 0; i < filesToHash.length; i += BATCH_SIZE) {
        final endIndex = (i + BATCH_SIZE < filesToHash.length) ? i + BATCH_SIZE : filesToHash.length;
        final batch = filesToHash.sublist(i, endIndex);


        // Process this batch of files in parallel
        final results = await Future.wait(
          batch.map((file) async {
            try {
              // Minimal logging - Log start of batch instead of every file?
              // Optional: Log progress less frequently
              // if (i % (BATCH_SIZE * 2) == 0 && batch.first == file) { // Log every ~20 files
              //   debugPrint('Hashing PSX files batch starting around ${i + 1}/${filesToHash.length}');
              // }


              String? fileHash = await _psxHashService.hashPsxFile(file.path);


              if (fileHash != null) {
                return MapEntry(file.path, fileHash);
              } else {
                  // Log files that failed to hash (might be intended for non-PSX CUE/CHD)
                   // debugPrint('Hashing failed or returned null for: ${path.basename(file.path)}');
              }
            } catch (e) {
              // Log critical errors during hashing itself
              // Shorten error message to avoid excessive logging
               String errorMsg = e.toString();
               debugPrint('Error hashing file ${path.basename(file.path)}: ${errorMsg.substring(0, min(100, errorMsg.length))}...');
            }
            return null; // Return null if hash failed or was null
          }),
        );


        // Add the valid results to our hash map
        for (var entry in results) {
          if (entry != null) {
            hashes[entry.key] = entry.value;
          }
        }


        // Yield to UI periodically to keep it responsive
        // Yield more frequently if batches are large? Maybe every batch is fine.
         await Future.delayed(const Duration(milliseconds: 10)); // Small delay per batch
      }


      debugPrint('Finished hashing ${hashes.length} PSX files out of ${filesToHash.length} found.');
      return hashes;
    } catch (e, stackTrace) { // Catch potential errors during file collection/batching
      debugPrint('Error during PSX file hashing integration: $e');
       debugPrint('Stack trace: $stackTrace');
      return hashes; // Return whatever was hashed successfully
    }
  }


  // Helper function for min value (already present, good)
  // int min(int a, int b) => a < b ? a : b; // Can use dart:math min now
}