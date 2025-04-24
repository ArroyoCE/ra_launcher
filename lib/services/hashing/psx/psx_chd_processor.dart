// lib/services/hashing/psx/psx_chd_processor.dart
import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';

// PSX Specific Imports
import 'psx_filesystem.dart'; // PSX Filesystem reader for CHD context
import 'psx_hash.dart';       // PSX Hash calculator and executable info

// Common CHD Import
import '../CHD/chd_read_common.dart'; // Shared CHD reader

// --- Message classes for Isolate Communication ---

/// Request message sent to the PSX CHD processing isolate.
class PsxChdProcessRequest {
  final String filePath;
  final SendPort sendPort; // Port to send the response back

  PsxChdProcessRequest(this.filePath, this.sendPort);
}

/// Response message sent back from the PSX CHD processing isolate.
class PsxChdProcessResponse {
  final String filePath;
  final String? hash; // The calculated MD5 hash, or null on error
  final String? error; // Error message if hashing failed
  final double progress; // Progress indicator (0.0 to 1.0)
  // Optional: Include PsxExecutableInfo if needed by the caller
  // final PsxExecutableInfo? executableInfo;

  PsxChdProcessResponse({
    required this.filePath,
    this.hash,
    this.error,
    this.progress = 1.0, // Default to 1.0 (completed)
    // this.executableInfo,
  });
}

// --- Isolate Processor Class ---

/// Handles processing PSX CHD files in a separate isolate.
class PsxChdProcessor {
  /// Processes a PSX CHD file in an isolate and returns the calculated hash.
  ///
  /// [filePath]: The path to the CHD file.
  /// Returns the MD5 hash as a String, or null if an error occurs.
  static Future<String?> processChd(String filePath) async {
    final receivePort = ReceivePort();
    final completer = Completer<String?>();

    Isolate? isolate;
    try {
      isolate = await Isolate.spawn(
        _processPsxChdFileInIsolate, // PSX specific isolate entry point
        PsxChdProcessRequest(filePath, receivePort.sendPort), // PSX specific request
        onError: receivePort.sendPort,
        onExit: receivePort.sendPort,
        debugName: 'PSX CHD Processor for $filePath',
      );

      final subscription = receivePort.listen((message) {
        if (message is PsxChdProcessResponse) { // Expect PSX specific response
          // Optional: Handle progress
          // if (message.progress < 1.0) {
          //   return;
          // }

          if (message.hash != null) {
            completer.complete(message.hash);
          } else {
            debugPrint('Error processing PSX CHD $filePath in isolate: ${message.error}');
            completer.complete(null);
          }
          receivePort.close();
        } else if (message is List && message.length == 2) {
           // Handle uncaught errors
           final error = message[0];
           final stackTrace = message[1];
           debugPrint('Uncaught error in PSX CHD isolate ($filePath): $error');
           debugPrint('Isolate StackTrace: $stackTrace');
           if (!completer.isCompleted) completer.complete(null);
           receivePort.close();
        } else if (message == null) {
           // Handle exit
           debugPrint('PSX CHD isolate ($filePath) exited.');
           if (!completer.isCompleted) completer.complete(null);
           receivePort.close();
        } else {
          debugPrint('Unexpected message from PSX CHD isolate ($filePath): $message');
           if (!completer.isCompleted) completer.complete(null);
          receivePort.close();
        }
      });
       completer.future.whenComplete(() => subscription.cancel());

    } catch (e, stackTrace) {
      debugPrint('Error spawning PSX CHD isolate for $filePath: $e');
      debugPrint('Stack Trace: $stackTrace');
      receivePort.close();
      isolate?.kill(priority: Isolate.immediate);
      return null;
    }

    return completer.future;
  }

  /// The entry point function executed by the PSX CHD isolate.
  static Future<void> _processPsxChdFileInIsolate(PsxChdProcessRequest request) async {
    final sendPort = request.sendPort;
    final filePath = request.filePath;
    final ChdReader chdReader = ChdReader(); // Use the shared CHD reader

    try {
      // 1. Initialize ChdReader
      if (!chdReader.isInitialized) {
        throw Exception('CHD library (chdr) not initialized or found.');
      }
      sendPort.send(PsxChdProcessResponse(filePath: filePath, progress: 0.1));


      // 2. Process CHD Header and Tracks
      final chdInfo = await chdReader.processChdFile(filePath);
      if (!chdInfo.isSuccess || chdInfo.tracks.isEmpty) {
        throw Exception('Failed to process CHD header/tracks: ${chdInfo.error}');
      }

      // PSX discs typically use the first track for data
      final dataTrack = chdInfo.tracks.firstWhere(
          (t) => t.type.contains('MODE1') || t.type.contains('MODE2'),
           orElse: () => throw Exception('No suitable data track found in PSX CHD.'),
      );
      sendPort.send(PsxChdProcessResponse(filePath: filePath, progress: 0.2));


      // 3. Create PSX Filesystem handler for CHD context
      // PsxFilesystem is designed to work with ChdReader
      final filesystem = PsxFilesystem(chdReader, filePath, dataTrack);

      // 4. Test filesystem access (optional but good for debugging)
      var rootDir = await filesystem.findRootDirectory();
      if (rootDir == null) {
        throw Exception('Could not find root directory in PSX CHD filesystem.');
      }
      sendPort.send(PsxChdProcessResponse(filePath: filePath, progress: 0.4));


      // 5. Create PSX Hash Calculator and calculate the hash
      // PsxHashCalculator uses PsxFilesystem
      final hashCalculator = PsxHashCalculator(chdReader, filesystem);
      final execInfo = await hashCalculator.calculateHash(); // This finds SYSTEM.CNF, reads files, etc.

      if (execInfo == null) {
        throw Exception('Failed to calculate PSX hash (executable not found or error).');
      }
      sendPort.send(PsxChdProcessResponse(filePath: filePath, progress: 0.9));


      // 6. Apply special case hash replacement if needed (This logic remains from original)
      // String finalHash = execInfo.hash;
      // if (finalHash == '4fde0064a5ab5d8db59a22334228e9f1') {
      //   finalHash = '1ca6c010e4667df408fccd5dc7948d81';
      //   debugPrint('Applied special hash case for PSX CHD: ${path.basename(filePath)}');
      // }


      // 7. Send the final result back
      sendPort.send(PsxChdProcessResponse(
        filePath: filePath,
        hash: execInfo.hash, // Use the hash from PsxExecutableInfo
        progress: 1.0,
        // executableInfo: execInfo, // Optionally send full info
      ));

    } catch (e, stackTrace) {
      debugPrint('Error in PSX CHD isolate for $filePath: $e');
      debugPrint('Isolate StackTrace: $stackTrace');
      sendPort.send(PsxChdProcessResponse(filePath: filePath, error: e.toString(), progress: 1.0));
    } finally {
       Isolate.current.kill(priority: Isolate.immediate);
    }
  }
}
