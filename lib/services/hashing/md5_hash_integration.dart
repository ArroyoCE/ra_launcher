// lib/services/hashing/md5/md5_hash_integration.dart
import 'dart:io';
import 'dart:isolate';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

/// Class to handle MD5 hashing of files
class MD5HashIntegration {
  /// Hashes files in the provided folders using MD5.
  /// 
  /// [folders] - List of folder paths to search for files.
  /// [validExtensions] - List of file extensions to process.
  /// [progressCallback] - Optional callback to report progress.
  /// 
  /// Returns a map where keys are file paths and values are MD5 hash strings.
  Future<Map<String, String>> hashFilesInFolders(
    List<String> folders, 
    List<String> validExtensions,
    {Function(int current, int total)? progressCallback}
  ) async {
    final Map<String, String> hashes = {};
    final List<File> filesToProcess = [];
    
    // First collect all files to process
    for (final folderPath in folders) {
      final directory = Directory(folderPath);
      
      if (await directory.exists()) {
        await for (final entity in directory.list(recursive: true)) {
          if (entity is File) {
            final extension = path.extension(entity.path).toLowerCase();
            
            // Check if file has a valid extension
            if (validExtensions.contains(extension)) {
              filesToProcess.add(entity);
            }
          }
        }
      }
    }
    
    if (filesToProcess.isEmpty) {
      return hashes;
    }

    debugPrint('Found ${filesToProcess.length} files to MD5 hash');
    
    // Process files using isolates for better performance
    final int totalFiles = filesToProcess.length;
    int processedFiles = 0;
    
    // Determine the number of isolates to use based on available processors
    final int isolateCount = Platform.numberOfProcessors - 1;
    final int filesPerIsolate = (totalFiles / isolateCount).ceil();
    
    final List<Future<Map<String, String>>> isolateFutures = [];
    
    for (int i = 0; i < isolateCount; i++) {
      final int start = i * filesPerIsolate;
      final int end = (start + filesPerIsolate > totalFiles) ? totalFiles : start + filesPerIsolate;
      
      if (start >= totalFiles) {
        break;
      }
      
      // Create a sublist of files for this isolate to process
      final sublist = filesToProcess.sublist(start, end);
      isolateFutures.add(_processFilesInIsolate(sublist));
      
      // Update processed files count
      processedFiles = end;
      if (progressCallback != null) {
        progressCallback(processedFiles, totalFiles);
      }
    }
    
    // Wait for all isolates to complete and combine results
    final results = await Future.wait(isolateFutures);
    for (final result in results) {
      hashes.addAll(result);
    }
    
    return hashes;
  }
  
  /// Processes a list of files in a separate isolate to compute MD5 hashes.
  Future<Map<String, String>> _processFilesInIsolate(List<File> files) async {
    final ReceivePort receivePort = ReceivePort();
    
    // Create message to send to isolate
    final List<String> filePaths = files.map((file) => file.path).toList();
    
    await Isolate.spawn(
      _isolateHashFiles, 
      _IsolateMessage(
        sendPort: receivePort.sendPort,
        filePaths: filePaths,
      ),
    );
    
    // Receive the result from the isolate
    final Map<String, String> result = await receivePort.first as Map<String, String>;
    return result;
  }
  
  /// Static method that runs in an isolate to hash multiple files.
  static void _isolateHashFiles(_IsolateMessage message) async {
    final Map<String, String> hashes = {};
    
    for (final filePath in message.filePaths) {
      try {
        final file = File(filePath);
        final fileLength = await file.length();
        
        // For very large files, read and hash in chunks
        if (fileLength > 100 * 1024 * 1024) { // 100MB
          final hash = await _hashLargeFile(file);
          hashes[filePath] = hash;
        } else {
          // For smaller files, read the whole file at once
          final bytes = await file.readAsBytes();
          final hash = md5.convert(bytes).toString();
          hashes[filePath] = hash;
        }
      } catch (e) {
        // Skip files that can't be read or hashed
      }
    }
    
    // Send result back to main isolate
    message.sendPort.send(hashes);
  }

  /// Hashes a large file by reading it in chunks.
  static Future<String> _hashLargeFile(File file) async {
    // Create a new MD5 instance for each chunk
    const md5Instance = md5;
    final chunks = <List<int>>[];
    
    // Read the file in chunks
    await for (final chunk in file.openRead()) {
      chunks.add(chunk);
    }
    
    // Concatenate all chunks and compute hash
    final bytes = <int>[];
    for (final chunk in chunks) {
      bytes.addAll(chunk);
    }
    
    // Compute and return the hash
    return md5Instance.convert(bytes).toString();
  }
  
  /// Optimized method for hashing a single file
  static Future<String?> hashSingleFile(String filePath) async {
    try {
      final file = File(filePath);
      final fileLength = await file.length();
      
      if (fileLength > 100 * 1024 * 1024) { // 100MB
        return await _hashLargeFile(file);
      } else {
        final bytes = await file.readAsBytes();
        return md5.convert(bytes).toString();
      }
    } catch (e) {
      debugPrint('Error hashing file $filePath: $e');
      return null;
    }
  }
}

/// Message class for communicating with isolates
class _IsolateMessage {
  final SendPort sendPort;
  final List<String> filePaths;
  
  _IsolateMessage({
    required this.sendPort,
    required this.filePaths,
  });
}