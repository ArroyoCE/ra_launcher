// lib/services/hashing/n64/n64_hash_integration_optimized.dart
import 'dart:async'; // Added for Completer
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

/// Data structure to pass arguments to the isolate.
class _IsolateParams {
  final SendPort sendPort;
  final String filePath;

  _IsolateParams(this.sendPort, this.filePath);
}

/// Data structure to send results back from the isolate.
class _IsolateResult {
  final String filePath;
  final String? hash;
  final String? error; // Optional: include error details

  _IsolateResult(this.filePath, {this.hash, this.error});
}

/// Optimized class to handle Nintendo 64 ROM hashing using Isolates,
/// including correct handling for NDD format.
class N64HashIntegration {
  final validExtensions = const ['.n64', '.z64', '.v64', '.ndd'];

  /// Hashes Nintendo 64 ROM files found in the provided folders concurrently.
  ///
  /// Returns a map where keys are file paths and values are the calculated hash strings.
  /// Uses Isolates for parallel processing to improve performance.
  Future<Map<String, String>> hashN64FilesInFolders(List<String> folders) async {
    final Map<String, String> hashes = {};
    final List<Future<void>> isolateSpawnFutures = []; // Track spawn attempts
    final ReceivePort mainReceivePort = ReceivePort();

    debugPrint('Starting Optimized Nintendo 64 hashing for ${folders.length} folders');

    // 1. Find all candidate files first
    final List<String> filesToProcess = [];
    for (final folderPath in folders) {
      final directory = Directory(folderPath);
      if (await directory.exists()) {
        try {
          await for (final entity in directory.list(recursive: true, followLinks: false)) {
            if (entity is File) {
              final extension = path.extension(entity.path).toLowerCase();
              if (validExtensions.contains(extension)) {
                filesToProcess.add(entity.path);
              }
            }
          }
        } catch (e) {
          debugPrint('Error listing files in $folderPath: $e');
        }
      } else {
         debugPrint('Directory not found: $folderPath');
      }
    }

     debugPrint('Found ${filesToProcess.length} potential N64 files to hash.');

    if (filesToProcess.isEmpty) {
       mainReceivePort.close();
       return hashes;
    }

    // 2. Setup listener for results from isolates
    int processedCount = 0;
    final completer = Completer<void>();

    mainReceivePort.listen((message) {
      if (message is _IsolateResult) {
        // Increment count regardless of success/failure to track completion
        processedCount++;
        if (message.hash != null) {
          hashes[message.filePath] = message.hash!;
           // Slightly less verbose logging, remove hash value from print
           // debugPrint('(${processedCount}/${filesToProcess.length}) Hashed N64 file: ${message.filePath}');
        } else if (message.error != null) {
           debugPrint('($processedCount/${filesToProcess.length}) Error hashing N64 file ${message.filePath}: ${message.error}');
        } else {
           debugPrint('($processedCount/${filesToProcess.length}) Skipping N64 file (no hash generated): ${message.filePath}');
        }

        // Check if all results are in
        if (processedCount == filesToProcess.length) {
           mainReceivePort.close();
           if (!completer.isCompleted) {
             completer.complete();
           }
        }
      } else {
         debugPrint("Received unexpected message type from isolate: ${message.runtimeType}");
         // Increment count even for unexpected messages to avoid hangs
         processedCount++;
         if (processedCount == filesToProcess.length && !completer.isCompleted) {
             mainReceivePort.close();
             completer.complete();
         }
      }
    }, onError: (e) {
       debugPrint("Error on main receive port: $e");
       processedCount++; // Count errors as processed
       if (processedCount == filesToProcess.length && !completer.isCompleted) {
           mainReceivePort.close();
           completer.complete();
       }
    }, onDone: () {
       debugPrint("Main receive port closed.");
        if (!completer.isCompleted) {
           completer.complete(); // Ensure completion
        }
    });


    // 3. Spawn an isolate for each file
    for (final filePath in filesToProcess) {
       try {
         final isolateParams = _IsolateParams(mainReceivePort.sendPort, filePath);
         // Add future to list to potentially await spawn completion/errors later if needed
         // For now, primarily relying on message count for completion signal
         Future<Isolate> isolateFuture = Isolate.spawn(_isolateHashingTask, isolateParams);
         isolateSpawnFutures.add(isolateFuture.catchError((e) {
            debugPrint("Error spawning isolate for $filePath: $e");
            // If spawn fails, we won't get a message back. We need to manually
            // increment processedCount to prevent the completer from hanging.
            processedCount++;
            if (processedCount == filesToProcess.length && !completer.isCompleted) {
                mainReceivePort.close();
                completer.complete();
            }
         }));
       } catch (e) {
          debugPrint("Failed to spawn isolate for $filePath: $e");
           // Handle synchronous spawn errors
           processedCount++;
           if (processedCount == filesToProcess.length && !completer.isCompleted) {
               mainReceivePort.close();
               completer.complete();
           }
       }
    }

    // 4. Wait for all results to be processed
    await completer.future;

    // Optional: Await all spawn futures to ensure cleanup or catch late errors
    // await Future.wait(isolateSpawnFutures);

    debugPrint('Completed Optimized Nintendo 64 hashing, processed $processedCount files, got ${hashes.length} valid hashes.');
    return hashes;
  }

  // ---------------------------------------------------------------------------
  // Isolate Task and Helper Functions (MUST be static or top-level)
  // ---------------------------------------------------------------------------

  /// The function executed by each Isolate.
  static Future<void> _isolateHashingTask(_IsolateParams params) async {
    final String filePath = params.filePath;
    final SendPort sendPort = params.sendPort;
    File file = File(filePath);
    RandomAccessFile? raf;

    try {
      if (!await file.exists()) {
          // Use Isolate.exit for cleaner termination and message sending
          Isolate.exit(sendPort, _IsolateResult(filePath, error: "File not found"));
      }

      final fileLength = await file.length();
      // NDD files might be smaller? Keep minimum check for header relevance.
      if (fileLength < 4) { // Need at least 4 bytes for format detection
        debugPrint('Isolate: File too small for format detection: $filePath');
        Isolate.exit(sendPort, _IsolateResult(filePath, error: "File too small"));
      }

      // Limit read size according to C code reference (MAX_BUFFER_SIZE = 64 MiB)
      const int maxReadSize = 64 * 1024 * 1024;
      final bytesToRead = (fileLength > maxReadSize) ? maxReadSize : fileLength.toInt();
      final buffer = Uint8List(bytesToRead);

      raf = await file.open(mode: FileMode.read);
      final bytesRead = await raf.readInto(buffer);

      if (bytesRead != bytesToRead) {
          await raf.close();
          Isolate.exit(sendPort, _IsolateResult(filePath, error: "Failed to read expected number of bytes ($bytesRead/$bytesToRead)"));
      }
      await raf.close();
      raf = null;

      // Determine the ROM format based on the first 4 bytes
      final format = _determineRomFormat(buffer);
      if (format == null) {
        debugPrint('Isolate: Unknown N64 ROM/NDD format: $filePath');
        Isolate.exit(sendPort, _IsolateResult(filePath, hash: null)); // Not necessarily error, just unknown
      }

      Uint8List hashBuffer;
      // *** UPDATED FORMAT HANDLING ***
      switch (format) {
        case 'Z64':
        case 'NDD': // NDD format uses big-endian like Z64, no byte swap needed
          hashBuffer = buffer;
          break;
        case 'V64': // V64 format (byte-swapped)
          hashBuffer = _byteswap16(buffer);
          break;
        case 'N64': // N64 format (word-swapped)
          hashBuffer = _byteswap32(buffer);
          break;
        default: // Should be caught by format == null, but defensive
           Isolate.exit(sendPort, _IsolateResult(filePath, hash: null));

      }

      // Calculate MD5 hash
      final digest = md5.convert(hashBuffer);
      final hashString = digest.toString();

      Isolate.exit(sendPort, _IsolateResult(filePath, hash: hashString));

    } catch (e, stacktrace) {
      debugPrint('Isolate Error processing $filePath: $e\n$stacktrace');
      await raf?.close(); // Ensure closure on error
      Isolate.exit(sendPort, _IsolateResult(filePath, error: e.toString()));
    } finally {
      // Ensure file handle is closed if raf was opened and an error occurred before close
      await raf?.close();
    }
  }

  /// Determines the format of the N64 ROM or NDD file from the header. (Static)
  /// Returns 'Z64', 'V64', 'N64', 'NDD', or null if unknown.
  static String? _determineRomFormat(Uint8List buffer) {
    if (buffer.length < 4) return null; // Need at least 4 bytes

    final firstByte = buffer[0];
    final first4Bytes = buffer.sublist(0, 4);

    // *** ADDED NDD Check based on C code ***
    // Check NDD first as its magic number is simpler (just first byte)
    // The C code checks only the first byte for NDD.
    if (firstByte == 0xE8 || firstByte == 0x22) {
      return 'NDD';
    }

    // Z64 format (big-endian) - 80 37 12 40
    if (first4Bytes[0] == 0x80 && first4Bytes[1] == 0x37 &&
        first4Bytes[2] == 0x12 && first4Bytes[3] == 0x40) {
      return 'Z64';
    }

    // V64 format (byte-swapped) - 37 80 40 12
    if (first4Bytes[0] == 0x37 && first4Bytes[1] == 0x80 &&
        first4Bytes[2] == 0x40 && first4Bytes[3] == 0x12) {
      return 'V64';
    }

    // N64 format (word-swapped) - 40 12 37 80
    if (first4Bytes[0] == 0x40 && first4Bytes[1] == 0x12 &&
        first4Bytes[2] == 0x37 && first4Bytes[3] == 0x80) {
      return 'N64';
    }

    // Unknown format
    // Log first 4 bytes for debugging unknown formats
    debugPrint('Unknown N64 ROM/NDD format. First 4 bytes: ${first4Bytes[0].toRadixString(16)} ${first4Bytes[1].toRadixString(16)} ${first4Bytes[2].toRadixString(16)} ${first4Bytes[3].toRadixString(16)}');
    return null;
  }

  /// Performs a 16-bit byte swap operation (for V64 format). (Static)
  static Uint8List _byteswap16(Uint8List buffer) {
    final result = Uint8List(buffer.length);
    final len = buffer.length;
    // Ensure loop doesn't go out of bounds if length is odd
    for (int i = 0; i < (len ~/ 2) * 2; i += 2) {
      result[i] = buffer[i + 1];
      result[i + 1] = buffer[i];
    }
    // If odd length, copy the last byte as is
    if (len % 2 != 0) {
      result[len - 1] = buffer[len - 1];
    }
    return result;
  }

  /// Performs a 32-bit byte swap operation (for N64 format). (Static)
  static Uint8List _byteswap32(Uint8List buffer) {
    final result = Uint8List(buffer.length);
    final len = buffer.length;
     // Ensure loop doesn't go out of bounds if length is not multiple of 4
    for (int i = 0; i < (len ~/ 4) * 4; i += 4) {
      result[i] = buffer[i + 3];
      result[i + 1] = buffer[i + 2];
      result[i + 2] = buffer[i + 1];
      result[i + 3] = buffer[i];
    }
    // Handle remaining bytes if length is not a multiple of 4
    final remainder = len % 4;
    if (remainder > 0) {
      final startOfRemainder = len - remainder;
      // Copy remaining bytes without swapping, matching original C logic interpretation
      for (int i = 0; i < remainder; i++) {
        result[startOfRemainder + i] = buffer[startOfRemainder + i];
      }
    }
    return result;
  }
}