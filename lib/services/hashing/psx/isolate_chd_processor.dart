// FILE: isolate_chd_processor.dart
import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';

// Adjust imports based on your actual project structure if needed
import 'psx_filesystem.dart'; // Assuming psx_filesystem.dart is in the same directory
import 'psx_hash.dart';       // Assuming psx_hash.dart is in the same directory
import '../CHD/chd_read_common.dart'; // Assuming CHD folder is one level up

// Message to send to the isolate
class ChdProcessRequest {
  final String filePath;
  final SendPort sendPort;

  ChdProcessRequest(this.filePath, this.sendPort);
}

// Response from the isolate
class ChdProcessResponse {
  final String? hash;
  final String? error;
  final String filePath;
  final double progress; // 0.0 to 1.0

  ChdProcessResponse({
    this.hash,
    this.error,
    required this.filePath,
    this.progress = 1.0,
  });
}

/// Class to process CHD files in a separate isolate
class IsolateChdProcessor {
  /// Process a CHD file in an isolate and return the hash
  static Future<String?> processChd(String filePath) async {
    final receivePort = ReceivePort();
    final completer = Completer<String?>();

    // Create and spawn the isolate
    Isolate? isolate; // Declare isolate variable outside the try block
    try {
       isolate = await Isolate.spawn(
        _processChdFileInIsolate,
        ChdProcessRequest(filePath, receivePort.sendPort),
        onError: receivePort.sendPort, // Send errors back to the main isolate
        onExit: receivePort.sendPort, // Send exit signals back
        debugName: 'CHD Processor',
      );
    } catch (e) {
        debugPrint("Failed to spawn isolate: $e");
        receivePort.close(); // Clean up port if spawn failed
        completer.completeError("Isolate spawn failed: $e");
        return completer.future; // Return the error future
    }


    // Listen for messages from the isolate
    StreamSubscription? subscription; // Hold subscription to cancel it later
    subscription = receivePort.listen((message) {
      if (message is ChdProcessResponse) {
        // Update progress if needed (you can add a progress callback here)
        if (message.progress < 1.0) {
          // Reduce logging frequency to improve performance
          // Optional: Log progress if needed
          // if (message.progress % 0.2 < 0.01) { // Only log at 0%, 20%, 40%, 60%, 80%
          //   debugPrint('CHD Progress for ${message.filePath}: ${(message.progress * 100).toStringAsFixed(0)}%');
          // }
          return; // Don't complete yet, still progressing
        }

        // Complete when we get the final result (progress == 1.0)
        if (message.hash != null) {
          completer.complete(message.hash);
        } else {
          // Even if hash is null, if progress is 1.0 it means processing finished (with error)
          debugPrint('Error processing CHD ${message.filePath}: ${message.error ?? "Unknown error"}');
          completer.complete(null); // Complete with null for errors
        }

        // Clean up
        subscription?.cancel(); // Cancel the subscription
        receivePort.close();
        isolate?.kill(priority: Isolate.immediate); // Ensure isolate is killed
      } else if (message is List && message.length == 2 && message[0] is String) {
         // Handle errors sent via onError port
         debugPrint("Error from CHD isolate for $filePath: ${message[0]}\nStack trace:\n${message[1]}");
         completer.complete(null); // Complete with null on error
         subscription?.cancel();
         receivePort.close();
         isolate?.kill(priority: Isolate.immediate);
      } else if (message == null) {
         // Handle isolate exit signal
         debugPrint("CHD isolate for $filePath exited unexpectedly.");
         if (!completer.isCompleted) {
            completer.complete(null); // Complete with null if not already done
         }
         subscription?.cancel();
         receivePort.close();
         // Isolate already exited, no need to kill
      } else {
          // Unexpected message
          debugPrint("Unexpected message from CHD isolate for $filePath: $message");
           if (!completer.isCompleted) {
               completer.complete(null);
           }
          subscription?.cancel();
          receivePort.close();
          isolate?.kill(priority: Isolate.immediate);
      }
    });

    // Handle potential errors during the Future itself (e.g., if isolate dies before completing)
     completer.future.catchError((error) {
         debugPrint("Error in completer future for $filePath: $error");
         // Ensure cleanup if completer fails
         subscription?.cancel();
         receivePort.close();
         isolate?.kill(priority: Isolate.immediate);
         return null; // Return null on future error
     });


    return completer.future;
  }

  /// The isolate entry point
  static void _processChdFileInIsolate(ChdProcessRequest request) async {
    final sendPort = request.sendPort;
    final filePath = request.filePath;

    try {
      // Create CHD reader
      final chdReader = ChdReader(); // Consider passing lib path if not default

      if (!chdReader.isInitialized) {
        sendPort.send(ChdProcessResponse(
          filePath: filePath,
          error: 'Failed to initialize CHD library',
        ));
        return;
      }

      // Process the CHD file metadata
      final result = await chdReader.processChdFile(filePath);

      if (!result.isSuccess) {
        sendPort.send(ChdProcessResponse(
          filePath: filePath,
          error: 'Error processing CHD file metadata: ${result.error}',
        ));
        return;
      }

      // Check if it's a data disc with at least one track
      if (result.tracks.isEmpty || !result.isDataDisc) {
        sendPort.send(ChdProcessResponse(
          filePath: filePath,
          error: result.tracks.isEmpty ? 'No tracks found' : 'Not a data disc (first track is not MODE1/MODE2)',
        ));
        return;
      }

      // Send progress update - after initial processing
      sendPort.send(ChdProcessResponse(
        filePath: filePath,
        progress: 0.2, // Example progress point
      ));

      // Get the first data track (guaranteed to exist based on checks above)
      final dataTrack = result.tracks[0];

      // Create the filesystem handler
      final filesystem = PsxFilesystem(chdReader, filePath, dataTrack);

      // Test filesystem access - finding root is part of hash calculation now
      // var rootDir = await filesystem.findRootDirectory(); // No longer needed here
      // if (rootDir == null) { ... } // Error handled within hashCalculator

      // Send progress update - before hash calculation
      sendPort.send(ChdProcessResponse(
        filePath: filePath,
        progress: 0.4, // Example progress point
      ));

      // Create a hash calculator and calculate the hash
      // *** FIX: Pass the third argument (dataTrack) ***
      final hashCalculator = PsxHashCalculator(chdReader, filesystem);
      final execInfo = await hashCalculator.calculateHash(); // This now includes root dir finding

      if (execInfo == null) {
        sendPort.send(ChdProcessResponse(
          filePath: filePath,
          error: 'Failed to calculate hash (executable not found or error during hashing)',
        ));
        return;
      }

      // Hash calculation successful, final hash is in execInfo.hash
      String finalHash = execInfo.hash;
      // Special case already handled inside calculateHash

      // Send the final result (progress = 1.0 is default)
      sendPort.send(ChdProcessResponse(
        filePath: filePath,
        hash: finalHash,
      ));
    } catch (e, stackTrace) {
      // Catch errors within the isolate processing
      debugPrint('Error in CHD isolate for $filePath: $e');
      debugPrint('Stack trace: $stackTrace');

      // Send error back to the main isolate
      sendPort.send(ChdProcessResponse(
        filePath: filePath,
        error: 'Exception: $e',
      ));
    }
  }
}