import 'dart:isolate';
import 'dart:async';
import 'package:flutter/foundation.dart';

import 'package:retroachievements_organizer/services/hashing/3do/hash_3do_chd.dart';


// Message to send to the isolate
class Chd3DOProcessRequest {
  final String filePath;
  final SendPort sendPort;

  Chd3DOProcessRequest(this.filePath, this.sendPort);
}

// Response from the isolate
class Chd3DOProcessResponse {
  final String? hash;
  final String? error;
  final String filePath;
  final double progress; // 0.0 to 1.0

  Chd3DOProcessResponse({
    this.hash,
    this.error,
    required this.filePath,
    this.progress = 1.0,
  });
}

/// Class to process 3DO CHD files in a separate isolate
class Isolate3DOChdProcessor {
  /// Process a 3DO CHD file in an isolate and return the hash
  static Future<String?> processChd(String filePath) async {
    final receivePort = ReceivePort();
    final completer = Completer<String?>();
    
    // Create and spawn the isolate
    final isolate = await Isolate.spawn(
      _process3DOChdFileInIsolate,
      Chd3DOProcessRequest(filePath, receivePort.sendPort),
    );
    
    // Listen for messages from the isolate
    receivePort.listen((message) {
      if (message is Chd3DOProcessResponse) {
        // Update progress if needed (you can add a progress callback here)
        if (message.progress < 1.0) {
          debugPrint('Processing 3DO CHD: ${(message.progress * 100).toStringAsFixed(1)}%');
          return;
        }
        
        // Complete when we get the final result
        if (message.hash != null) {
          completer.complete(message.hash);
        } else {
          debugPrint('Error processing 3DO CHD: ${message.error}');
          completer.complete(null);
        }
        
        // Clean up
        receivePort.close();
        isolate.kill();
      }
    });
    
    return completer.future;
  }
  
  /// The isolate entry point
  static void _process3DOChdFileInIsolate(Chd3DOProcessRequest request) async {
    final sendPort = request.sendPort;
    final filePath = request.filePath;
    
    try {
      // Send initial progress update
      sendPort.send(Chd3DOProcessResponse(
        filePath: filePath,
        progress: 0.1,
      ));

      // Use the existing Hash3DOCalculator to calculate the hash
      final hash = await Hash3DOCalculator.calculateHash(filePath);
      
      // Send progress update
      sendPort.send(Chd3DOProcessResponse(
        filePath: filePath,
        progress: 0.9,
      ));
      
      if (hash == null) {
        sendPort.send(Chd3DOProcessResponse(
          filePath: filePath,
          error: 'Failed to calculate 3DO hash',
        ));
        return;
      }
      
      // Send the final result
      sendPort.send(Chd3DOProcessResponse(
        filePath: filePath,
        hash: hash,
      ));
    } catch (e, stackTrace) {
      debugPrint('Error in 3DO CHD isolate: $e');
      debugPrint('Stack trace: $stackTrace');
      
      sendPort.send(Chd3DOProcessResponse(
        filePath: filePath,
        error: 'Exception: $e',
      ));
    }
  }
}