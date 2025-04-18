import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

/// Class that implements hashing for Atari 7800 ROMs
class A78HashIntegration {
  // Constants
  static const int maxBufferSize = 64 * 1024 * 1024; // 64MB
  static const int batchSize = 16;

  // Compute pool for reusing isolates
  late ComputePool _computePool;
  bool _poolInitialized = false;

  /// Initialize the compute pool
  Future<void> _ensurePoolInitialized() async {
    if (!_poolInitialized) {
      final int isolateCount = max(1, Platform.numberOfProcessors - 1); // Leave one core free for UI
      _computePool = ComputePool(isolateCount);
      await _computePool.initialize();
      _poolInitialized = true;
    }
  }

  /// Process Atari 7800 files in parallel using compute pool
  Future<Map<String, String>> hashA78FilesInFolders(List<String> folders) async {
    final Map<String, String> hashes = {};
    List<String> validExtensions = ['.a78'];

    if (validExtensions.isEmpty) return hashes;

    // Find files to process in parallel
    final List<File> filesToProcess = await _findFilesToProcess(folders, validExtensions);
    
    if (filesToProcess.isEmpty) return hashes;

    // Initialize compute pool if needed
    await _ensurePoolInitialized();
    
    // Process files using compute pool
    final result = await _computePool.processFiles(filesToProcess);
    hashes.addAll(result);

    return hashes;
  }

  /// Find files to process in parallel
  Future<List<File>> _findFilesToProcess(List<String> folders, List<String> validExtensions) async {
    final List<File> filesToProcess = [];
    final List<Future<List<File>>> scanFutures = [];
    
    for (final folderPath in folders) {
      final directory = Directory(folderPath);
      if (await directory.exists()) {
        scanFutures.add(_scanFolder(directory, validExtensions));
      }
    }
    
    // Wait for all folder scans to complete in parallel
    final results = await Future.wait(scanFutures);
    for (final files in results) {
      filesToProcess.addAll(files);
    }
    
    return filesToProcess;
  }

  /// Scan a folder for files with valid extensions
  Future<List<File>> _scanFolder(Directory directory, List<String> validExtensions) async {
    final List<File> result = [];
    await for (final entity in directory.list(recursive: true)) {
      if (entity is File && validExtensions.contains(path.extension(entity.path).toLowerCase())) {
        result.add(entity);
      }
    }
    return result;
  }

  /// Disposes resources
  void dispose() {
    if (_poolInitialized) {
      _computePool.dispose();
      _poolInitialized = false;
    }
  }

  /// Hashes an Atari 7800 ROM
  Future<String?> hash7800(Uint8List bytes) async {
    // Limit buffer size
    final bufferSize = bytes.length > maxBufferSize ? maxBufferSize : bytes.length;

    // Check header - A78 games begin with ATARI7800
    if (bufferSize < 128) return await computeRawMD5(bytes);

    final header = String.fromCharCodes(bytes.sublist(1, 17));
    if (header.startsWith('ATARI7800')) {
      // A78 header is 128 bytes
      final dataBytes = bytes.sublist(128, bufferSize);
      return await computeRawMD5(dataBytes);
    }

    // If no header found, hash the whole file
    return await computeRawMD5(bytes.sublist(0, bufferSize));
  }

  /// Computes an MD5 hash of raw bytes
  Future<String> computeRawMD5(Uint8List bytes) async {
    // Direct computation for small files to avoid compute overhead
    if (bytes.length < 2 * 1024 * 1024) { // 2MB threshold
      final digest = md5.convert(bytes);
      return digest.toString();
    }
    
    // Use compute for better performance on larger files
    return await compute(_md5Hash, bytes);
  }

  // Static method for compute isolation
  static String _md5Hash(Uint8List bytes) {
    final digest = md5.convert(bytes);
    return digest.toString();
  }
}

/// Worker for handling file processing in isolates
class ComputePool {
  final List<Isolate> _isolates = [];
  final List<SendPort> _sendPorts = [];
  final int size;
  
  ComputePool(this.size);
  
  Future<void> initialize() async {
    for (int i = 0; i < size; i++) {
      final receivePort = ReceivePort();
      final isolate = await Isolate.spawn(_isolateEntryPoint, receivePort.sendPort);
      final sendPort = await receivePort.first as SendPort;
      
      _isolates.add(isolate);
      _sendPorts.add(sendPort);
    }
  }
  
  Future<Map<String, String>> processFiles(List<File> files) async {
    const int actualBatchSize = A78HashIntegration.batchSize;
    
    // Distribute files evenly across workers
    final int filesPerWorker = (files.length / size).ceil();
    final List<List<File>> chunks = [];
    
    for (int i = 0; i < files.length; i += filesPerWorker) {
      final end = i + filesPerWorker > files.length ? files.length : i + filesPerWorker;
      chunks.add(files.sublist(i, end));
    }
    
    // Make sure we don't have more chunks than workers
    while (chunks.length > _sendPorts.length) {
      final lastChunk = chunks.removeLast();
      chunks.last.addAll(lastChunk);
    }
    
    // Process all chunks in parallel
    final List<Future<Map<String, String>>> futures = [];
    for (int i = 0; i < chunks.length; i++) {
      if (chunks[i].isNotEmpty) {
        futures.add(_processChunk(_sendPorts[i], chunks[i], actualBatchSize));
      }
    }
    
    // Combine results
    final results = await Future.wait(futures);
    final Map<String, String> combinedHashes = {};
    for (final result in results) {
      combinedHashes.addAll(result);
    }
    
    return combinedHashes;
  }
  
  Future<Map<String, String>> _processChunk(SendPort port, List<File> files, int batchSize) async {
    final ReceivePort responsePort = ReceivePort();
    port.send([files, responsePort.sendPort, batchSize]);
    return await responsePort.first as Map<String, String>;
  }
  
  void dispose() {
    for (final isolate in _isolates) {
      isolate.kill(priority: Isolate.immediate);
    }
    _isolates.clear();
    _sendPorts.clear();
  }
  
  static void _isolateEntryPoint(SendPort mainSendPort) {
    final ReceivePort receivePort = ReceivePort();
    mainSendPort.send(receivePort.sendPort);
    
    receivePort.listen((message) async {
      final List<File> files = message[0] as List<File>;
      final SendPort sendPort = message[1] as SendPort;
      final int batchSize = message.length > 2 ? message[2] as int : A78HashIntegration.batchSize;
      
      final Map<String, String> batchHashes = {};
      final hasher = A78HashIntegration();
      
      // Process files in batches for better memory management
      for (int i = 0; i < files.length; i += batchSize) {
        final end = i + batchSize > files.length 
            ? files.length 
            : i + batchSize;
        
        final batch = files.sublist(i, end);
        
        // Process batch
        for (final file in batch) {
          try {
            final bytes = await file.readAsBytes();
            final fileHash = await hasher.hash7800(bytes);
            
            if (fileHash != null) {
              batchHashes[file.path] = fileHash;
            }
          } catch (_) {
            // Ignore hashing errors
          }
        }
      }
      
      sendPort.send(batchHashes);
    });
  }
}

// Add max function if not available
int max(int a, int b) => a > b ? a : b;