// lib/services/hashing/unified_hash_service.dart
import 'dart:async'; // Import dart:async for FutureOr (though not directly used in the final fix)
import 'dart:io';
import 'dart:math'; // Import dart:math for max function

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
// Adjust the import path if necessary based on your project structure
import 'package:retroachievements_organizer/services/hashing/native/rc_hash_dll.dart';

class UnifiedHashService {
  // Hash a single file using an isolate
  Future<String> hashFile(String filePath, int consoleId) async {
    if (path.extension(filePath).toLowerCase() == '.chd') {
      return '';
    }
    try {
      return await compute(_hashRegularFileIsolate, {
        'filePath': filePath,
        'consoleId': consoleId,
      });
    } catch (e) {
      debugPrint('Error hashing file $filePath in compute: $e');
      return '';
    }
  }

  // Static method designed to be run in an isolate via compute
  static String _hashRegularFileIsolate(Map<String, dynamic> params) {
    final filePath = params['filePath'] as String;
    final consoleId = params['consoleId'] as int;
    try {
      final rcHashDll = RCHashDLL();
      return rcHashDll.hashFile(filePath, consoleId);
    } catch (e) {
      // debugPrint('Error in isolate hashing $filePath: $e'); // Can be noisy
      return '';
    }
  }

  // Scan a single folder for files matching extensions
  Future<List<String>> _scanSingleFolder(String folder, Set<String> validExtensions) async {
    final List<String> foundFiles = [];
    try {
      final dir = Directory(folder);
      if (!await dir.exists()) {
        debugPrint('Directory does not exist: $folder');
        return foundFiles;
      }
      final Stream<FileSystemEntity> entityStream = dir.list(recursive: true, followLinks: false);
      await for (final entity in entityStream) {
        if (entity is File) {
          final String filePath = entity.path;
          final String extension = path.extension(filePath).toLowerCase();
          if (validExtensions.contains(extension)) {
            foundFiles.add(filePath);
          }
        }
      }
    } catch (e) {
      debugPrint('Error scanning folder $folder: $e');
    }
    return foundFiles;
  }

  // Optimized method to gather files to hash by scanning folders in parallel
  Future<List<String>> _gatherFilesToHash(List<String> folders, Set<String> validExtensions) async {
    final List<Future<List<String>>> folderScans = folders
        .map((folder) => _scanSingleFolder(folder, validExtensions))
        .toList();
    final List<List<String>> results = await Future.wait(folderScans);
    return results.expand((files) => files).toList();
  }

  // Calculate a reasonable number of concurrent hashing operations
  int _calculateConcurrencyLevel() {
    final int cores = Platform.numberOfProcessors;
    return max(2, min(cores * 2, 16)); // Example: Min 2, Max 16, typically 2x cores
  }

  // Hash files found in specified folders, processing with limited concurrency
  Future<Map<String, String>> hashFilesInFolders(
    int consoleId,
    List<String> folders,
    List<String> validExtensions, {
    Function(int current, int total)? progressCallback,
  }) async {
    final Map<String, String> hashes = {};
    final validExtensionsSet = validExtensions
        .where((ext) => ext.toLowerCase() != '.chd')
        .map((e) => e.toLowerCase())
        .toSet();

    if (validExtensionsSet.isEmpty && !validExtensions.contains('.chd')) {
         debugPrint('No valid extensions provided (excluding .chd).');
         return hashes;
    }
    if (folders.isEmpty) {
        debugPrint('No folders provided to scan.');
        return hashes;
    }

    debugPrint('Starting hash process for console ID: $consoleId');
    debugPrint('Folders to scan: ${folders.join(", ")}');
    debugPrint('Valid extensions: ${validExtensionsSet.join(", ")}');

    final List<String> allFiles = await _gatherFilesToHash(folders, validExtensionsSet);
    final int totalFiles = allFiles.length;
    debugPrint('Found $totalFiles files to hash.');

    if (allFiles.isEmpty) {
      return hashes;
    }

    final int concurrencyLevel = _calculateConcurrencyLevel();
    debugPrint('Using concurrency level: $concurrencyLevel');

    // --- Corrected Concurrency Logic ---
    final List<Future<void>> activeTasks = []; // List to track active hashing futures
    int processedCount = 0;
    final Stream<String> fileStream = Stream.fromIterable(allFiles);

    await for (final filePath in fileStream) {
        // Wait if the number of active tasks reaches the concurrency limit
        while (activeTasks.length >= concurrencyLevel) {
            // Wait for *any* of the active tasks to complete
            await Future.any(activeTasks);
            // Note: We rely on the task's own `whenComplete` to remove itself,
            // so no explicit removal is needed here after Future.any.
            // The list size check in the while loop condition handles throttling.
        }

        // Launch the next hashing task
        late final Future<void> task; // Declare task as late
        task = hashFile(filePath, consoleId).then((hash) {
            if (hash.isNotEmpty) {
                hashes[filePath] = hash; // Store successful hash
            }
        }).catchError((e) {
            // Log error but continue processing other files
            debugPrint('Error processing hash future for $filePath: $e');
        }).whenComplete(() {
            // This block executes after the future completes (success or error)
            processedCount++;
            progressCallback?.call(processedCount, totalFiles); // Update progress
            // **Crucially, remove this task from the active list *after* it completes**
            activeTasks.remove(task);
        });

        // Add the newly created task future to the list of active tasks
        activeTasks.add(task);
    }

    // After the loop finishes, wait for any remaining tasks that might still be running
    await Future.wait(activeTasks);

    debugPrint('Hashing process completed. Generated ${hashes.length} valid hashes for $processedCount processed files.');
    return hashes;
  }
}