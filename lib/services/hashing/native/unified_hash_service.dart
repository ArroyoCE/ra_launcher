// lib/services/hashing/unified_hash_service.dart
import 'dart:io';
import 'dart:collection';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:retroachievements_organizer/services/hashing/native/rc_hash_dll.dart';

class UnifiedHashService {
  final RCHashDLL _rcHashDll = RCHashDLL();
  final Map<int, HashInstancePool> _hashPools = {};
  
  // Get or create a hash pool for a specific console ID
  HashInstancePool _getHashPool(int consoleId) {
    if (!_hashPools.containsKey(consoleId)) {
      _hashPools[consoleId] = HashInstancePool(poolSize: 8); // Adjust pool size as needed
    }
    return _hashPools[consoleId]!;
  }
  
  // Hash a single file with better error handling
  Future<String> hashFile(String filePath, int consoleId) async {
    try {
      // Quick check for CHD
      if (path.extension(filePath).toLowerCase() == '.chd') {
        debugPrint('CHD files are no longer supported for hashing: $filePath');
        return '';
      }
      
      // Use isolate for computation
      return await compute(_hashRegularFile, {
        'filePath': filePath,
        'consoleId': consoleId,
      });
    } catch (e) {
      debugPrint('Error hashing file $filePath: $e');
      return ''; // Return empty instead of rethrowing to avoid stopping batch processing
    }
  }
  
  // Optimized method to gather files to hash
  Future<List<String>> _gatherFilesToHash(List<String> folders, Set<String> validExtensions) async {
    final List<String> allFiles = [];
    final List<Future<List<String>>> folderScans = [];
    
    // Start all folder scans in parallel
    for (final folder in folders) {
      folderScans.add(_scanSingleFolder(folder, validExtensions));
    }
    
    // Wait for all scans to complete and combine results
    final results = await Future.wait(folderScans);
    for (final files in results) {
      allFiles.addAll(files);
    }
    
    return allFiles;
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
      
      await for (final entity in dir.list(recursive: true)) {
        if (entity is File) {
          final extension = path.extension(entity.path).toLowerCase();
          if (validExtensions.contains(extension)) {
            foundFiles.add(entity.path);
          }
        }
      }
    } catch (e) {
      debugPrint('Error scanning folder $folder: $e');
    }
    
    return foundFiles;
  }
  
  // Calculate optimal batch size based on file count and system resources
  int _calculateOptimalBatchSize(int fileCount) {
    // Use isolate count to optimize batch size for parallelism
    final int isolateCount = Platform.numberOfProcessors;
    
    // Adjust batch size based on file count and available processors
    if (fileCount < 100) return isolateCount * 4;
    if (fileCount < 500) return isolateCount * 3;
    return isolateCount * 2; // Default for large collections
  }
  
  // Optimized hash files in folders method
  Future<Map<String, String>> hashFilesInFolders(
    int consoleId, 
    List<String> folders, 
    List<String> validExtensions,
    {Function(int current, int total)? progressCallback}
  ) async {
    final Map<String, String> hashes = {};
    
    // Filter out .chd extension and use Set for O(1) lookups
    final validExtensionsSet = validExtensions
        .where((ext) => ext.toLowerCase() != '.chd')
        .map((e) => e.toLowerCase())
        .toSet();
    
    debugPrint('Starting hash process for console ID: $consoleId');
    debugPrint('Folders to scan: ${folders.join(", ")}');
    
    // Start file gathering
    final allFiles = await _gatherFilesToHash(folders, validExtensionsSet);
    debugPrint('Found ${allFiles.length} files to hash');
    
    if (allFiles.isEmpty) {
      return hashes;
    }
    
    // Adapt batch size based on file count and system
    final batchSize = _calculateOptimalBatchSize(allFiles.length);
    debugPrint('Using batch size: $batchSize');
    
    // Sort files by size to distribute work more evenly
    await _sortFilesBySize(allFiles);
    
    // Process files in batches
    for (int i = 0; i < allFiles.length; i += batchSize) {
      final int end = (i + batchSize < allFiles.length) ? i + batchSize : allFiles.length;
      final batch = allFiles.sublist(i, end);
      
      // Process batch in parallel
      final results = await Future.wait(
        batch.map((file) => hashFile(file, consoleId).catchError((e) {
          debugPrint('Failed to hash $file: $e');
          return '';
        }))
      );
      
      // Add successful hashes to the map
      for (int j = 0; j < batch.length; j++) {
        final hash = results[j];
        if (hash.isNotEmpty) {
          hashes[batch[j]] = hash;
        }
      }
      
      // Update progress
      if (progressCallback != null) {
        progressCallback(end, allFiles.length);
      }
    }
    
    return hashes;
  }
  
  // Sort files by size to better distribute workload
  Future<void> _sortFilesBySize(List<String> files) async {
    // Get file sizes
    final fileSizes = <String, int>{};
    for (final file in files) {
      try {
        final fileInfo = await File(file).stat();
        fileSizes[file] = fileInfo.size;
      } catch (e) {
        fileSizes[file] = 0;
      }
    }
    
    // Sort files with largest files first to ensure they start processing earlier
    files.sort((a, b) => fileSizes[b]!.compareTo(fileSizes[a]!));
  }
  
  // Static method for isolate computation
  static String _hashRegularFile(Map<String, dynamic> params) {
    final filePath = params['filePath'] as String;
    final consoleId = params['consoleId'] as int;
    
    try {
      final rcHashDll = RCHashDLL();
      return rcHashDll.hashFile(filePath, consoleId);
    } catch (e) {
      debugPrint('Error in isolate hashing $filePath: $e');
      return '';
    }
  }
}

// Hash instance pool for better performance
class HashInstancePool {
  final int _poolSize;
  final List<RCHashDLL> _instances = [];
  final List<bool> _inUse = [];
  
  HashInstancePool({int poolSize = 8}) : _poolSize = poolSize {
    // Initialize the pool
    for (int i = 0; i < _poolSize; i++) {
      _instances.add(RCHashDLL());
      _inUse.add(false);
    }
  }
  
  // Get an available instance
  RCHashDLL? getAvailableInstance() {
    for (int i = 0; i < _poolSize; i++) {
      if (!_inUse[i]) {
        _inUse[i] = true;
        return _instances[i];
      }
    }
    return null; // No available instances
  }
  
  // Release an instance
  void releaseInstance(RCHashDLL instance) {
    final index = _instances.indexOf(instance);
    if (index != -1) {
      _inUse[index] = false;
    }
  }
}