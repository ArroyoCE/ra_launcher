import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

/// Class that implements hashing for NES and FDS ROMs
class NesHashIntegration {
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

  /// Process NES files in parallel using compute pool
  Future<Map<String, String>> hashNesFilesInFolders(List<String> folders) async {
    final Map<String, String> hashes = {};
    List<String> validExtensions = ['.nes', '.fds', '.unf', '.unif'];

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

  /// Hashes an NES or FDS ROM based on file extension
  Future<String?> hashROM(Uint8List bytes, String filePath) async {
    // Check file extension to determine appropriate hashing method
    final extension = path.extension(filePath).toLowerCase();
    
    if (extension == '.fds') {
      return await hashFDS(bytes);  // Use dedicated FDS method like in combined console implementation
    } else if (extension == '.unf' || extension == '.unif') {
      return await hashUNIF(bytes);
    } else {
      return await hashNES(bytes);
    }
  }

  /// Hashes an NES ROM based on the Combined Console implementation
  Future<String?> hashNES(Uint8List bytes) async {
    // Limit buffer size for memory safety
    final bufferSize = bytes.length > maxBufferSize ? maxBufferSize : bytes.length;

    // Too small to be a valid NES ROM
    if (bufferSize < 16) {
      return await computeRawMD5(bytes.sublist(0, bufferSize));
    }

    // Check if this is an iNES ROM (header starts with NES\x1A)
    if (bytes[0] == 0x4E && bytes[1] == 0x45 && bytes[2] == 0x53 && bytes[3] == 0x1A) {
      int prgSize = bytes[4] * 16384; // PRG size in 16K units
      int chrSize = bytes[5] * 8192;  // CHR size in 8K units

      // Check for NES 2.0 format (bits 2-3 of byte 7 are 10)
      bool isNes20 = ((bytes[7] & 0x0C) == 0x08);
      if (isNes20) {
        // For NES 2.0, extract the upper bits from byte 9
        int prgSizeMSB = (bytes[9] & 0x0F);
        prgSize = ((prgSizeMSB << 8) | bytes[4]) * 16384;

        int chrSizeMSB = (bytes[9] >> 4);
        chrSize = ((chrSizeMSB << 8) | bytes[5]) * 8192;
      }

      // Calculate header size (iNES header is minimum 16 bytes)
      int headerSize = 16;

      // Check for trainer - adds 512 bytes after header
      if ((bytes[6] & 0x04) != 0) {
        headerSize += 512;
      }

      // Combine PRG and CHR data for hashing
      int dataSize = prgSize + chrSize;
      if (dataSize == 0 || headerSize + dataSize > bufferSize) {
        // If sizes are invalid or the file is truncated, hash the whole file
        return await computeRawMD5(bytes.sublist(0, bufferSize));
      }

      // Extract PRG+CHR data for hashing (skipping header and trainer if present)
      final dataBytes = bytes.sublist(headerSize, headerSize + dataSize);
      return await computeRawMD5(dataBytes);
    }

    // Not an iNES ROM or invalid header, hash the whole file
    return await computeRawMD5(bytes.sublist(0, bufferSize));
  }

  /// Hashes a UNIF format NES ROM
  Future<String?> hashUNIF(Uint8List bytes) async {
    // Limit buffer size for memory safety
    final bufferSize = bytes.length > maxBufferSize ? maxBufferSize : bytes.length;

    // Check UNIF header for "UNIF"
    if (bufferSize >= 32 &&
        bytes[0] == 0x55 && bytes[1] == 0x4E && bytes[2] == 0x49 && bytes[3] == 0x46) {
      
      // UNIF header is 32 bytes
      int headerSize = 32;
      
      // Find the PRG and CHR chunks in the UNIF file
      int offset = headerSize;
      List<Uint8List> dataChunks = [];
      
      while (offset + 8 < bufferSize) {
        // Get chunk type (4 bytes) and length (4 bytes)
        String chunkType = String.fromCharCodes(bytes.sublist(offset, offset + 4));
        int chunkLength = bytes[offset + 4] | 
                        (bytes[offset + 5] << 8) | 
                        (bytes[offset + 6] << 16) | 
                        (bytes[offset + 7] << 24);
        
        offset += 8; // Move past chunk header
        
        // Check if we have a valid chunk length
        if (offset + chunkLength > bufferSize) {
          break;
        }
        
        // Extract PRG and CHR chunks
        if (chunkType.startsWith('PRG') || chunkType.startsWith('CHR')) {
          dataChunks.add(bytes.sublist(offset, offset + chunkLength));
        }
        
        offset += chunkLength; // Move to next chunk
      }
      
      // Concatenate all chunks and hash them
      if (dataChunks.isNotEmpty) {
        // Calculate total length
        int totalLength = dataChunks.fold(0, (sum, chunk) => sum + chunk.length);
        Uint8List combined = Uint8List(totalLength);
        
        // Copy chunks into combined buffer
        int position = 0;
        for (final chunk in dataChunks) {
          combined.setRange(position, position + chunk.length, chunk);
          position += chunk.length;
        }
        
        return await computeRawMD5(combined);
      }
    }
    
    // Not a UNIF file or invalid header, hash the whole file
    return await computeRawMD5(bytes.sublist(0, bufferSize));
  }
  
  /// Hashes a Famicom Disk System ROM based on the C code implementation
  /// This follows the logic in rc_hash_fds from the C code
  Future<String?> hashFDS(Uint8List bytes) async {
    // Limit buffer size for memory safety
    final bufferSize = bytes.length > maxBufferSize ? maxBufferSize : bytes.length;

    // Check FDS header for "FDS\x1A"
    if (bufferSize >= 16 &&
        bytes[0] == 0x46 && bytes[1] == 0x44 && bytes[2] == 0x53 && bytes[3] == 0x1A) {
      // Skip 16-byte header and hash the rest of the file
      final dataBytes = bytes.sublist(16, bufferSize);
      return await computeRawMD5(dataBytes);
    }

    // No FDS header, hash the entire file
    return await computeRawMD5(bytes.sublist(0, bufferSize));
  }

  /// Computes an MD5 hash of raw bytes
  Future<String> computeRawMD5(Uint8List bytes) async {
    // Direct computation for small files to avoid compute overhead
    if (bytes.length < 2 * 1024 * 1024) { // 2MB threshold
      final digest = crypto.md5.convert(bytes);
      return digest.toString();
    }
    
    // Use compute for better performance on larger files
    return await compute(_md5Hash, bytes);
  }

  // Static method for compute isolation
  static String _md5Hash(Uint8List bytes) {
    final digest = crypto.md5.convert(bytes);
    return digest.toString();
  }
}

/// Helper class for accumulating MD5 hashes in parts
class AccumulatingMd5Digest {
  final List<int> _bytes = [];
  
  void add(List<int> bytes) {
    _bytes.addAll(bytes);
  }
  
  String digestString() {
    final digest = crypto.md5.convert(_bytes);
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
    const int actualBatchSize = NesHashIntegration.batchSize;
    
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
      final int batchSize = message.length > 2 ? message[2] as int : NesHashIntegration.batchSize;
      
      final Map<String, String> batchHashes = {};
      final hasher = NesHashIntegration();
      
      // Process files in batches for better memory management
      for (int i = 0; i < files.length; i += batchSize) {
        final end = i + batchSize > files.length 
            ? files.length 
            : i + batchSize;
        
        final batch = files.sublist(i, end);
        
        // Process batch
        for (final file in batch) {
          try {
            // Memory optimization: Read file in chunks if it's very large
            final fileSize = await file.length();
            Uint8List bytes;
            
            if (fileSize > 32 * 1024 * 1024) {
              // For very large files, read only what we need
              final RandomAccessFile raf = await file.open(mode: FileMode.read);
              bytes = Uint8List(NesHashIntegration.maxBufferSize);
              await raf.readInto(bytes, 0, NesHashIntegration.maxBufferSize);
              await raf.close();
            } else {
              bytes = await file.readAsBytes();
            }
            
            // Determine hash method by extension
            final extension = path.extension(file.path).toLowerCase();
            String? fileHash;
            
            if (extension == '.fds') {
              fileHash = await hasher.hashFDS(bytes);
            } else if (extension == '.unf' || extension == '.unif') {
              fileHash = await hasher.hashUNIF(bytes);
            } else {
              fileHash = await hasher.hashNES(bytes);
            }
            
            if (fileHash != null) {
              batchHashes[file.path] = fileHash;
            }
          } catch (e) {
            // Ignore hashing errors, but print for debugging if needed
            // print('Error hashing ${file.path}: $e');
          }
        }
      }
      
      sendPort.send(batchHashes);
    });
  }
}

// Add max function if not available
int max(int a, int b) => a > b ? a : b;