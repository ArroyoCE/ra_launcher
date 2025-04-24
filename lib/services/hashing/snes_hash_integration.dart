import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart'; // Only needed if using compute outside the pool
import 'package:path/path.dart' as path;

/// Optimized class for hashing SNES ROMs using isolates.
class SnesHashIntegration {
  static const int maxBufferSize = 64 * 1024 * 1024; // 64MB
  static const int defaultBatchSize = 16;

  late ComputePool _computePool;
  bool _poolInitialized = false;

  Future<void> _ensurePoolInitialized() async {
    if (!_poolInitialized) {
      final int isolateCount = max(2, min(Platform.numberOfProcessors - 1, 8));
      _computePool = ComputePool(isolateCount);
      await _computePool.initialize();
      _poolInitialized = true;
    }
  }

  /// Processes SNES files in parallel using the compute pool.
  Future<Map<String, String>> hashSnesFilesInFolders(List<String> folders, {int batchSize = defaultBatchSize}) async {
    final Map<String, String> hashes = {};
    List<String> validExtensions = ['.sfc', '.smc', '.swc', '.fig'];

    if (validExtensions.isEmpty) return hashes;

    final List<String> filePathsToProcess = await _findFilesToProcess(folders, validExtensions);

    if (filePathsToProcess.isEmpty) return hashes;

    await _ensurePoolInitialized();

    // Pass file paths instead of File objects
    final result = await _computePool.processFilePaths(filePathsToProcess, batchSize);
    hashes.addAll(result);

    return hashes;
  }

  /// Finds file paths to process in parallel.
  Future<List<String>> _findFilesToProcess(List<String> folders, List<String> validExtensions) async {
    final List<String> filePathsToProcess = [];
    final List<Future<List<String>>> scanFutures = [];

    for (final folderPath in folders) {
      final directory = Directory(folderPath);
      if (await directory.exists()) {
        scanFutures.add(_scanFolder(directory, validExtensions));
      }
    }

    final results = await Future.wait(scanFutures);
    for (final files in results) {
      filePathsToProcess.addAll(files);
    }

    return filePathsToProcess;
  }

  /// Scans a folder for file paths with valid extensions.
  Future<List<String>> _scanFolder(Directory directory, List<String> validExtensions) async {
    final List<String> result = [];
    try {
      await for (final entity in directory.list(recursive: true, followLinks: false)) {
        if (entity is File && validExtensions.contains(path.extension(entity.path).toLowerCase())) {
          result.add(entity.path);
        }
      }
    } catch (e) {
       // Handle potential errors listing directories (e.g., permissions)
    }
    return result;
  }

  void dispose() {
    if (_poolInitialized) {
      _computePool.dispose();
      _poolInitialized = false;
    }
  }

  /// Hashes a SNES ROM directly (for use within isolates).
  String? hashSNESDirect(Uint8List bytes) {
    final bufferSize = bytes.length > maxBufferSize ? maxBufferSize : bytes.length;
    final view = Uint8List.sublistView(bytes, 0, bufferSize); // Use view to avoid copying

    if (bufferSize < 0x8000) {
      return md5.convert(view).toString();
    }

    bool hasHeader = bufferSize % 1024 == 512;
    int offset = hasHeader ? 512 : 0;

    // Basic header skip - complex logic removed for brevity/performance focus
    // If detailed format checking is crucial, re-add necessary logic here.

    Uint8List dataToHash;
    if (hasHeader) {
      if (bufferSize > offset) {
         dataToHash = Uint8List.sublistView(bytes, offset, bufferSize);
      } else {
         return null; // Invalid state
      }
    } else {
       dataToHash = view;
    }

    if (dataToHash.isEmpty) return null; // Avoid hashing empty data

    return md5.convert(dataToHash).toString();
  }

  // Optional: Keep a version that uses compute for external calls if needed
  // Future<String?> hashSNESWithCompute(Uint8List bytes) async {
  //   return await compute(_computeMd5ForSNES, bytes);
  // }
  // static String? _computeMd5ForSNES(Uint8List bytes) {
  //    // Create a temporary hasher instance to call the direct method
  //    final hasher = SnesHashIntegration();
  //    return hasher.hashSNESDirect(bytes);
  // }
}

/// Manages a pool of isolates for parallel file processing.
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

  Future<Map<String, String>> processFilePaths(List<String> filePaths, int batchSize) async {
    if (filePaths.isEmpty || _sendPorts.isEmpty) return {};

    // Distribute file paths somewhat evenly, simple division
    final int pathsPerWorker = (filePaths.length / _sendPorts.length).ceil();
    final List<List<String>> chunks = [];

    for (int i = 0; i < filePaths.length; i += pathsPerWorker) {
      final end = (i + pathsPerWorker > filePaths.length) ? filePaths.length : i + pathsPerWorker;
      chunks.add(filePaths.sublist(i, end));
    }

    // Process chunks in parallel
    final List<Future<Map<String, String>>> futures = [];
    for (int i = 0; i < chunks.length; i++) {
       if (i < _sendPorts.length && chunks[i].isNotEmpty) {
          futures.add(_processChunk(_sendPorts[i], chunks[i], batchSize));
       } else if (chunks[i].isNotEmpty) {
          // Handle case where there are more chunks than isolates (shouldn't happen with ceil)
          // Or append to the last worker
          if(futures.isNotEmpty) {
             // This logic might need refinement depending on desired load balancing
             // futures.last = futures.last.then((map) async {
             //    final extraMap = await _processChunk(_sendPorts.last, chunks[i], batchSize);
             //    map.addAll(extraMap);
             //    return map;
             // });
          }
       }
    }

    final results = await Future.wait(futures);
    final Map<String, String> combinedHashes = {};
    for (final result in results) {
      combinedHashes.addAll(result);
    }

    return combinedHashes;
  }

  Future<Map<String, String>> _processChunk(SendPort port, List<String> filePaths, int batchSize) async {
    final ReceivePort responsePort = ReceivePort();
    port.send([filePaths, responsePort.sendPort, batchSize]);
    final result = await responsePort.first;
    if (result is Map<String, String>) {
       return result;
    } else {
       // Handle potential errors sent back from isolate
       return {};
    }
  }

  void dispose() {
    for (final isolate in _isolates) {
      isolate.kill(priority: Isolate.immediate);
    }
    _isolates.clear();
    _sendPorts.clear();
  }

  /// Entry point for isolate workers.
  static void _isolateEntryPoint(SendPort mainSendPort) {
    final ReceivePort receivePort = ReceivePort();
    mainSendPort.send(receivePort.sendPort);

    Uint8List? reuseBuffer;
    final hasher = SnesHashIntegration(); // Create instance once per isolate

    receivePort.listen((message) async {
      if (message is! List || message.length < 3) {
         // Optionally send back an error indicator
         // (message[1] as SendPort).send(<error_object>);
         return;
      }

      final List<String> filePaths = message[0] as List<String>;
      final SendPort replyPort = message[1] as SendPort;
      final int batchSize = message[2] as int;

      final Map<String, String> batchHashes = {};

      // Process files in batches
      for (int i = 0; i < filePaths.length; i += batchSize) {
        final end = (i + batchSize > filePaths.length) ? filePaths.length : i + batchSize;
        final batch = filePaths.sublist(i, end);

        if (batch.isEmpty) continue;

        // --- File Size Handling & Buffer Allocation ---
        int maxBatchFileSize = 0;
        final List<MapEntry<String, int>> batchFilesWithSize = [];
        for(final filePath in batch) {
            final file = File(filePath);
            try {
                final size = await file.length(); // Use async length
                if (size > 0 && size <= SnesHashIntegration.maxBufferSize) {
                   batchFilesWithSize.add(MapEntry(filePath, size));
                   if (size > maxBatchFileSize) {
                      maxBatchFileSize = size;
                   }
                } else if (size > SnesHashIntegration.maxBufferSize) {
                    // File too large based on constant, record size for potential buffer adjustment
                    batchFilesWithSize.add(MapEntry(filePath, SnesHashIntegration.maxBufferSize));
                    if(SnesHashIntegration.maxBufferSize > maxBatchFileSize) {
                       maxBatchFileSize = SnesHashIntegration.maxBufferSize;
                    }
                }
                // else: skip 0-byte files
            } catch (e) {
                // Handle error getting file size (e.g., file disappears)
            }
        }

        if(batchFilesWithSize.isEmpty) continue; // Skip batch if no valid files found

        // Allocate or resize buffer ONCE per batch
        if (maxBatchFileSize > 0 && (reuseBuffer == null || reuseBuffer!.length < maxBatchFileSize)) {
          try {
             reuseBuffer = Uint8List(maxBatchFileSize);
          } catch (e) {
              // If buffer allocation fails, we cannot process this batch with the buffer
              reuseBuffer = null; // Reset buffer state
              // Potentially skip the rest of this batch or handle error differently
              continue;
          }
        }

        // --- Process Batch ---
        for (final entry in batchFilesWithSize) {
          final filePath = entry.key;
          final fileSize = entry.value; // Use pre-calculated size (capped at maxBufferSize)
          final file = File(filePath);

          if (reuseBuffer == null) {
             continue; // Cannot process without buffer
          }

          try {
            // Read file into the buffer
            final bytesRead = await _readFileIntoBuffer(file, reuseBuffer!, fileSize);

            if (bytesRead != null) {
                // Use the direct hashing method within the isolate
                final fileHash = hasher.hashSNESDirect(bytesRead);
                if (fileHash != null) {
                  batchHashes[filePath] = fileHash;
                }
            }
          } catch (e) {
            // Log specific file hashing errors
          }
        }
      }
      replyPort.send(batchHashes);
    });
  }

  /// Reads file content into a pre-allocated buffer, returning a view of the data read.
  static Future<Uint8List?> _readFileIntoBuffer(File file, Uint8List buffer, int bytesToRead) async {
      RandomAccessFile? raf;
      try {
          // Ensure we don't try to read more than the buffer allows or file has
          final readSize = min(bytesToRead, buffer.length);
          if (readSize <= 0) return null;

          raf = await file.open(mode: FileMode.read);
          final actualBytesRead = await raf.readInto(buffer, 0, readSize);

          if (actualBytesRead > 0) {
              // Return a view of the buffer containing the data read
              return Uint8List.sublistView(buffer, 0, actualBytesRead);
          } else {
              return null; // Nothing read
          }
      } catch (e) {
           return null; // Indicate error
      }
      finally {
          try {
             await raf?.close();
          } catch (e) {
              // Ignore close errors
          }
      }
  }
}
