import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

/// Class that implements hashing for SNES ROMs
class SnesHashIntegration {
  // Constants
  static const int maxBufferSize = 64 * 1024 * 1024; // 64MB
  static const int batchSize = 16;

  // Compute pool for reusing isolates
  late ComputePool _computePool;
  bool _poolInitialized = false;

  /// Initialize the compute pool
Future<void> _ensurePoolInitialized() async {
  if (!_poolInitialized) {
    // More adaptive worker count based on file count and system capabilities
    final int isolateCount = max(2, min(Platform.numberOfProcessors - 1, 8));
    _computePool = ComputePool(isolateCount);
    await _computePool.initialize();
    _poolInitialized = true;
  }
}

  /// Process SNES files in parallel using compute pool
  Future<Map<String, String>> hashSnesFilesInFolders(List<String> folders) async {
    final Map<String, String> hashes = {};
    List<String> validExtensions = ['.sfc', '.smc', '.swc', '.fig'];

    if (validExtensions.isEmpty) return hashes;

    // Find files to process in parallel
    final List<File> filesToProcess = await _findFilesToProcess(folders, validExtensions);
    
    if (filesToProcess.isEmpty) return hashes;

    // Initialize compute pool if needed
    await _ensurePoolInitialized();
    
    // For SNES ROMs, use a special approach with larger batches
    final result = await _computePool.processFiles(filesToProcess, batchSizeFactor: 2);
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

  /// Hashes a SNES ROM - Optimized implementation
  Future<String?> hashSNES(Uint8List bytes) async {
    // Limit buffer size
    final bufferSize = bytes.length > maxBufferSize ? maxBufferSize : bytes.length;

    // SNES ROMs can have headers and be in different formats
    // Need to check for different ROM layouts
    if (bufferSize < 0x8000) {
      // Too small to be a valid SNES ROM - use direct computation for small files
      return md5.convert(bytes.sublist(0, bufferSize)).toString();
    }

    // Fast path: Check for 512-byte header (typically .smc files)
    bool hasHeader = bufferSize % 1024 == 512;
    int offset = hasHeader ? 512 : 0;
    
    // Most common case: just removing header is sufficient
    // Skip the complex header detection for most ROMs to improve performance
    if (hasHeader && bufferSize >= 512 + 0x8000) {
      // Skip header and hash the ROM directly
      return await computeRawMD5(bytes.sublist(offset, bufferSize));
    }
    
    // For other cases, fallback to the full detection logic
    // but only if file size indicates a potential complex format
    if (bufferSize >= 0x8000 + offset) {
      bool needsFullChecks = false;
      
      // Quick check for HiROM marker - only do full checks if this looks suspicious
      if (offset + 0xFFD5 < bufferSize) {
        final romMode = bytes[offset + 0xFFD5] & 0x01;
        bool isHiROM = romMode == 1;
        
        // Only do full checksum verification for ROMs that don't match expectations
        if ((isHiROM && bufferSize < 1 * 1024 * 1024) || (!isHiROM && bufferSize > 4 * 1024 * 1024)) {
          needsFullChecks = true;
        }
      }
      
      // Only run full format detection if needed
      if (needsFullChecks) {
        bool isHiROM = false;
        
        // Check HiROM marker at 0xFFD5
        if (offset + 0xFFD5 < bufferSize) {
          final romMode = bytes[offset + 0xFFD5] & 0x01;
          if (romMode == 1) {
            isHiROM = true;
          }
        }

        // Verify with checksum check
        if (offset + 0xFFDC + 4 < bufferSize) {
          int checksum = bytes[offset + 0xFFDC] | (bytes[offset + 0xFFDD] << 8);
          int checksumComplement = bytes[offset + 0xFFDE] | (bytes[offset + 0xFFDF] << 8);

          if ((checksum ^ checksumComplement) != 0xFFFF) {
            // Try alternate location for LoROM
            if (!isHiROM && offset + 0x7FDC + 4 < bufferSize) {
              checksum = bytes[offset + 0x7FDC] | (bytes[offset + 0x7FDD] << 8);
              checksumComplement = bytes[offset + 0x7FDE] | (bytes[offset + 0x7FDF] << 8);

              if ((checksum ^ checksumComplement) == 0xFFFF) {
                isHiROM = false;
              }
            }
          }
        }
      }
    }

    // Get the file data for hashing - at this point we just use the detected header offset
    final dataBytes = hasHeader
        ? bytes.sublist(offset, bufferSize)
        : bytes.sublist(0, bufferSize);

    return await computeRawMD5(dataBytes);
  }

  /// Computes an MD5 hash of raw bytes
  Future<String> computeRawMD5(Uint8List bytes) async {
    // Direct computation for small files to avoid compute overhead
    if (bytes.length < 2 * 1024 * 1024) { // 2MB threshold - increased for SNES ROMs
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
  
  Future<Map<String, String>> processFiles(List<File> files, {int batchSizeFactor = 1}) async {
    // Use larger batches for SNES
    final int actualBatchSize = SnesHashIntegration.batchSize * batchSizeFactor;
    
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
  // Pre-sort files by size before sending to isolate
  files.sort((a, b) => a.lengthSync().compareTo(b.lengthSync()));
  
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
  
  // Preallocate a buffer for file reading
  Uint8List? reuseBuffer;
  
  receivePort.listen((message) async {
    final List<File> files = message[0] as List<File>;
    final SendPort sendPort = message[1] as SendPort;
    final int batchSize = message.length > 2 ? message[2] as int : SnesHashIntegration.batchSize;
    
    final Map<String, String> batchHashes = {};
    final hasher = SnesHashIntegration();
    
    // Process files in batches for better memory management
    for (int i = 0; i < files.length; i += batchSize) {
      final end = i + batchSize > files.length 
          ? files.length 
          : i + batchSize;
      
      final batch = files.sublist(i, end);
      
      // Sort by file size to process similar-sized files together
      batch.sort((a, b) => a.lengthSync().compareTo(b.lengthSync()));
      
      // Process batch - REPLACE THIS ENTIRE LOOP
      for (final file in batch) {
        try {
          // Allocate or resize buffer if needed
          final fileSize = file.lengthSync();
          if (reuseBuffer == null || reuseBuffer!.length < fileSize) {
            reuseBuffer = Uint8List(fileSize);
          }
          
          // Read file into buffer
          final bytes = await _readFileIntoBuffer(file, reuseBuffer!, fileSize);
          final fileHash = await hasher.hashSNES(bytes);
          
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

// Add this helper method in the same class
static Future<Uint8List> _readFileIntoBuffer(File file, Uint8List buffer, int fileSize) async {
  final RandomAccessFile raf = await file.open(mode: FileMode.read);
  try {
    await raf.readInto(buffer, 0, fileSize);
    return buffer.sublist(0, fileSize);
  } finally {
    await raf.close();
  }
}


}

// Add max function if not available
int max(int a, int b) => a > b ? a : b;