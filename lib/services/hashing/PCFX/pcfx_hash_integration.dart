import 'dart:io';
import 'package:flutter/foundation.dart';
// Use path alias

// Import the new hashing logic files
import 'pcfx_bin_hasher.dart';
import 'pcfx_chd_hasher.dart';

/// PC-FX hash integration class.
/// Finds PC-FX related files and delegates hashing to specific handlers.
class PCFXHashIntegration {
  /// Hashes PC-FX files (CHD, CUE, BIN, IMG, ISO) in the given folders.
  Future<Map<String, String>> hashPCFXFilesInFolders(
    List<String> folders,
    {void Function(int current, int total)? progressCallback}
  ) async {
    debugPrint('[PCFXHashIntegration] Starting PC-FX hashing in ${folders.length} folders...');
    final Map<String, String> hashes = {};
    final stopwatch = Stopwatch()..start();

    try {
      // Find all potential disc image files
      final allFiles = await _findDiscFiles(folders);
      final total = allFiles.length;
      debugPrint('[PCFXHashIntegration] Found ${allFiles.length} potential PC-FX files to process.');

      // Process each file
      for (int i = 0; i < allFiles.length; i++) {
        final filePath = allFiles[i];
        final lowerPath = filePath.toLowerCase();
        String? hash;

        // Skip M3U playlists - they aren't directly hashed for PC-FX
        if (lowerPath.endsWith('.m3u')) {
          debugPrint('[PCFXHashIntegration] Skipping M3U file (not directly hashed): $filePath');
          continue;
        }

        try {
          // Delegate hashing based on extension
          if (lowerPath.endsWith('.chd')) {
            hash = await hashPcfxChdFile(filePath);
          } else if (lowerPath.endsWith('.cue')) {
            hash = await hashPcfxCueFile(filePath);
          } else if (lowerPath.endsWith('.bin') || lowerPath.endsWith('.img') || lowerPath.endsWith('.iso')) {
            // Attempt to hash raw images directly, assuming default format
            // This might fail if it's not actually PC-FX or needs a specific CUE format
            hash = await hashPcfxBinFile(filePath, 2352, 16); // Default MODE1/2352
             if (hash == null) {
                 debugPrint('[PCFXHashIntegration] Direct BIN hash failed for $filePath (might need CUE or not be PC-FX). Trying MODE1/2048.');
                 // Try MODE1/2048 as another common format
                 hash = await hashPcfxBinFile(filePath, 2048, 0);
             }
          } else {
             debugPrint('[PCFXHashIntegration] Skipping unsupported file type: $filePath');
          }

          // Store successful hash
          if (hash != null && hash.isNotEmpty) {
            hashes[filePath] = hash;
            debugPrint('[PCFXHashIntegration] Hashed ($i/$total): $filePath -> $hash');
          } else {
            debugPrint('[PCFXHashIntegration] Failed to hash ($i/$total): $filePath');
          }
        } catch (e, stack) {
          // Catch errors during the hashing call itself
          debugPrint('[PCFXHashIntegration] Error hashing file $filePath: $e');
          debugPrint('Stack trace: $stack');
        }

        // Update progress
        progressCallback?.call(i + 1, total);
      }

      stopwatch.stop();
      debugPrint('[PCFXHashIntegration] Completed PC-FX hashing ${hashes.length} files out of $total candidates in ${stopwatch.elapsedMilliseconds}ms.');
      return hashes;

    } catch (e, stack) {
      // Catch errors during file finding or general processing
      debugPrint('[PCFXHashIntegration] Error in hashPCFXFilesInFolders: $e');
      debugPrint('Stack trace: $stack');
      return hashes; // Return any hashes found so far
    }
  }

  /// Finds disc files with specific extensions in folders recursively.
  Future<List<String>> _findDiscFiles(List<String> folders) async {
    final List<String> result = [];
    // Prioritize CUE and CHD, then common raw image types
    final validExtensions = ['.cue', '.chd', '.bin', '.img', '.iso'];

    for (final folder in folders) {
      try {
        final directory = Directory(folder);
        if (!await directory.exists()) {
          debugPrint('[PCFXHashIntegration] Directory does not exist: $folder');
          continue;
        }

        await for (final entity in directory.list(recursive: true, followLinks: false)) {
          if (entity is File) {
            final lowerPath = entity.path.toLowerCase();
            if (validExtensions.any((ext) => lowerPath.endsWith(ext))) {
              result.add(entity.path);
            }
          }
        }
      } catch (e) {
        // Log errors reading specific directories but continue with others
        debugPrint('[PCFXHashIntegration] Error scanning directory $folder: $e');
      }
    }
    return result;
  }
}
