// lib/services/hashing/ps2/ps2_chd_processor.dart
import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path; // For basename in logs
import 'package:retroachievements_organizer/services/hashing/CHD/chd_read_common.dart'; // Shared dependency

// --- Message classes for Isolate Communication ---

/// Request message sent to the PS2 CHD processing isolate.
class Ps2ChdProcessRequest {
  final String filePath;
  final SendPort sendPort; // Port to send the response back

  Ps2ChdProcessRequest(this.filePath, this.sendPort);
}

/// Response message sent back from the PS2 CHD processing isolate.
class Ps2ChdProcessResponse {
  final String filePath;
  final String? hash; // The calculated MD5 hash, or null on error
  final String? error; // Error message if hashing failed
  final double progress; // Progress indicator (0.0 to 1.0)

  Ps2ChdProcessResponse({
    required this.filePath,
    this.hash,
    this.error,
    this.progress = 1.0, // Default to 1.0 (completed)
  });

   @override
   String toString() { // For better debugging if message object is printed
     return 'Ps2ChdProcessResponse(filePath: ${path.basename(filePath)}, hash: $hash, error: $error, progress: $progress)';
   }
}

// --- Isolate Processor Class ---

/// Handles processing PS2 CHD files in a separate isolate to avoid blocking the main thread.
class Ps2ChdProcessor {
  /// Processes a PS2 CHD file in an isolate and returns the calculated hash.
  ///
  /// [filePath]: The path to the CHD file.
  /// Returns the MD5 hash as a String, or null if an error occurs.
  static Future<String?> processChd(String filePath) async {
    final receivePort = ReceivePort(); // Port to receive messages from the isolate
    final completer = Completer<String?>();
    StreamSubscription? subscription; // Declare subscription variable

    Isolate? isolate;
    try {
      // Spawn the isolate, passing the entry point function and the request message
      isolate = await Isolate.spawn(
        _processPs2ChdFileInIsolate, // The function the isolate will execute
        Ps2ChdProcessRequest(filePath, receivePort.sendPort),
        onError: receivePort.sendPort, // Send errors back through the port
        onExit: receivePort.sendPort, // Send exit signals back
        debugName: 'PS2 CHD Processor for ${path.basename(filePath)}',
      );

      // Listen for messages from the isolate
      subscription = receivePort.listen((message) {
         debugPrint('[Main Thread Listener] Received message for ${path.basename(filePath)}: $message');

         // Ensure completer hasn't already completed
         if (completer.isCompleted) {
            debugPrint('[Main Thread Listener] Completer already done for ${path.basename(filePath)}, closing port.');
            // Ensure cleanup if completer finished but listener somehow still active
            try { receivePort.close(); } catch (_) {}
            subscription?.cancel();
            return;
         }

        // ---- Start of Modified Listener Logic ----
        if (message is Ps2ChdProcessResponse) {
          // Check if it's the FINAL response (progress == 1.0)
          if (message.progress == 1.0) { // <--- Check for final progress
              if (message.hash != null) {
                 // Successfully received the hash
                 debugPrint('[Main Thread Listener] Completing with HASH: ${message.hash} for ${path.basename(filePath)}');
                 completer.complete(message.hash);
              } else {
                 // Final message, but hash is null means an error occurred in isolate
                 debugPrint('[Main Thread Listener] Completing with NULL (Error: ${message.error}) for ${path.basename(filePath)}');
                 // Log the specific error received from the isolate
                 debugPrint('Error processing PS2 CHD ${path.basename(filePath)} in isolate: ${message.error ?? "Unknown error"}');
                 completer.complete(null);
              }
              // Clean up ONLY after handling the final message or an error response
              receivePort.close();
              subscription?.cancel();
          } else {
             // It's an intermediate progress update, ignore for completion logic.
             // You could add UI update logic here if needed based on message.progress.
             debugPrint('[Main Thread Listener] Received progress update: ${message.progress * 100}% for ${path.basename(filePath)}');
             // Do NOT complete or close the port here for progress updates
          }
        }
        // ---- End of Modified Listener Logic ----

        else if (message is List && message.length == 2) {
          // Handle uncaught errors from the isolate (sent via onError)
          final error = message[0];
          final stackTrace = message[1];
          debugPrint('[Main Thread Listener] Completing with NULL (Uncaught Isolate Error) for ${path.basename(filePath)}');
          debugPrint('Uncaught error in PS2 CHD isolate (${path.basename(filePath)}): $error');
          debugPrint('Isolate StackTrace: $stackTrace');
          completer.complete(null); // Complete with null on uncaught error
          receivePort.close();
          subscription?.cancel();
        } else if (message == null) {
           // Handle isolate exit signal (sent via onExit)
           debugPrint('[Main Thread Listener] Isolate exited for ${path.basename(filePath)}.');
           // Only complete with null if it hasn't completed successfully already
           if (!completer.isCompleted) {
              debugPrint('[Main Thread Listener] Completing with NULL (Isolate Exited Prematurely?) for ${path.basename(filePath)}');
              completer.complete(null);
           }
           receivePort.close();
           subscription?.cancel();
        } else {
          // Unexpected message
          debugPrint('[Main Thread Listener] Completing with NULL (Unexpected Message) for ${path.basename(filePath)}');
          debugPrint('Unexpected message from PS2 CHD isolate (${path.basename(filePath)}): $message');
           if (!completer.isCompleted) {
             completer.complete(null);
           }
          receivePort.close();
          subscription?.cancel();
        }
      }); // End of receivePort.listen

      // Optional: Add a timeout for the operation (consider re-enabling if needed)
      // completer.future.timeout(const Duration(minutes: 2), onTimeout: () {
      //    debugPrint('PS2 CHD processing timed out for ${path.basename(filePath)}');
      //    if (!completer.isCompleted) completer.complete(null);
      //    receivePort.close();
      //    subscription?.cancel();
      //    isolate?.kill(priority: Isolate.immediate);
      //    return null;
      // });

    } catch (e, stackTrace) {
      // Error during isolate spawning itself
      debugPrint('Error spawning PS2 CHD isolate for $filePath: $e');
      debugPrint('Stack Trace: $stackTrace');
      // Ensure resources are cleaned up if spawning fails
      try { receivePort.close(); } catch (_) {}
      subscription?.cancel();
      isolate?.kill(priority: Isolate.immediate);
      // Complete with null if spawning failed before listener was set up
      if (!completer.isCompleted) {
         completer.complete(null);
      }
      // Return null directly as we couldn't start the process
      return null;
    }

    // Ensure cleanup happens when the future completes, regardless of how
    completer.future.whenComplete(() {
       // Cancel listener if it's somehow still active (e.g., future completed via timeout)
       subscription?.cancel();
       // Ensure port is closed if not already (might be redundant, but safe)
       // try { receivePort.close(); } catch (_) {}
       // It's generally better practice to ensure the isolate is killed if the
       // completer finishes unexpectedly, but killing should be handled carefully.
       // Consider if isolate?.kill() is needed here in edge cases.
    });

    return completer.future; // Return the future that will complete with the hash or null
  }
  // --- Isolate Entry Point and Helpers ---
  // (The rest of the file remains the same as the previous version)

  /// The entry point function executed by the isolate.
  static Future<void> _processPs2ChdFileInIsolate(Ps2ChdProcessRequest request) async {
    final sendPort = request.sendPort;
    final filePath = request.filePath;
    final ChdReader chdReader = ChdReader(); // Use the shared CHD reader

    try {
      debugLogIsolate('PS2 Isolate: Starting for ${path.basename(filePath)}');

      // 1. Initialize ChdReader
      if (!chdReader.isInitialized) {
        throw Exception('CHD library (chdr) not initialized or found.');
      }
      sendPort.send(Ps2ChdProcessResponse(filePath: filePath, progress: 0.1));
      debugLogIsolate('PS2 Isolate: CHD Reader Initialized.');

      // 2. Process CHD Header and Tracks
      final chdInfo = await chdReader.processChdFile(filePath);
      if (!chdInfo.isSuccess || chdInfo.tracks.isEmpty) {
        throw Exception('Failed to process CHD header/tracks: ${chdInfo.error ?? "Unknown CHD processing error"}');
      }

      // PS2 discs should have at least one data track (MODE1 or MODE2)
      final dataTrack = chdInfo.tracks.firstWhere(
          (t) => t.type.contains('MODE1') || t.type.contains('MODE2'),
          orElse: () => throw Exception('No suitable data track (MODE1/MODE2) found in PS2 CHD.'),
      );
      debugLogIsolate('PS2 Isolate: Found data track ${dataTrack.number} (${dataTrack.type}).');
      sendPort.send(Ps2ChdProcessResponse(filePath: filePath, progress: 0.3));

      // 3. Create a Filesystem Reader for the CHD context
      final chdFsReader = _Ps2ChdFilesystemReader(chdReader, filePath, dataTrack);
      debugLogIsolate('PS2 Isolate: Filesystem handler created.');

      // 4. Find SYSTEM.CNF within the CHD
      debugLogIsolate('PS2 Isolate: Reading SYSTEM.CNF...');
      final systemCnfData = await chdFsReader.findAndReadFile('SYSTEM.CNF');
      if (systemCnfData == null) {
        // Try alternative common paths if direct root fails
         debugLogIsolate('PS2 Isolate: SYSTEM.CNF not found in root, trying common alternatives...');
         // This part could be expanded to check common subdirs if needed.
         // For now, we assume it must be in the root for PS2.
        throw Exception('Could not find or read SYSTEM.CNF within the CHD root.');
      }
      debugLogIsolate('PS2 Isolate: SYSTEM.CNF read successfully.');
      sendPort.send(Ps2ChdProcessResponse(filePath: filePath, progress: 0.5));

      // 5. Parse SYSTEM.CNF to find the boot executable (BOOT2)
      final exePath = _findBootExecutable(systemCnfData);
      if (exePath == null) {
        throw Exception('Could not find BOOT2 executable path in SYSTEM.CNF.');
      }
      debugLogIsolate('PS2 Isolate: Found boot executable path in SYSTEM.CNF: $exePath');
      sendPort.send(Ps2ChdProcessResponse(filePath: filePath, progress: 0.7));

      // 6. Find and read the executable file from the CHD
      debugLogIsolate('PS2 Isolate: Reading executable "$exePath"...');
      final exeData = await chdFsReader.findAndReadFile(exePath);
      if (exeData == null) {
        throw Exception('Could not find or read executable "$exePath" within the CHD.');
      }
      debugLogIsolate('PS2 Isolate: Executable "$exePath" read successfully (${exeData.length} bytes).');

      // Optional: Check for ELF header (useful for debugging)
      if (exeData.length >= 4) {
        if (exeData[0] != 0x7F || exeData[1] != 0x45 || // E
            exeData[2] != 0x4C || // L
            exeData[3] != 0x46) { // F
          debugLogIsolate('Warning: PS2 executable "$exePath" in CHD does not have ELF header.');
        }
      } else {
         debugLogIsolate('Warning: PS2 executable "$exePath" in CHD is very small (< 4 bytes).');
      }
      sendPort.send(Ps2ChdProcessResponse(filePath: filePath, progress: 0.9));

      // 7. Calculate the MD5 hash
      // The hash is based on the executable's *path string* (from SYSTEM.CNF, normalized)
      // concatenated with the *executable's content*.
      final pathBytes = utf8.encode(exePath); // Use UTF-8 for the path string
      final combinedData = Uint8List(pathBytes.length + exeData.length);
      combinedData.setRange(0, pathBytes.length, pathBytes);
      combinedData.setRange(pathBytes.length, combinedData.length, exeData);

      final digest = crypto.md5.convert(combinedData);
      final hash = digest.toString();
      debugLogIsolate('PS2 Isolate: Hash calculated: $hash');

      // 8. Send the final result back
      debugLogIsolate('PS2 Isolate: Sending success response.');
      sendPort.send(Ps2ChdProcessResponse(filePath: filePath, hash: hash, progress: 1.0));

    } catch (e, stackTrace) {
      final errorMsg = 'PS2 CHD Error: $e';
      debugLogIsolate('Error in PS2 CHD isolate for ${path.basename(filePath)}: $errorMsg');
      debugLogIsolate('Isolate StackTrace: $stackTrace');
      // Send error back to the main thread
      try {
         sendPort.send(Ps2ChdProcessResponse(filePath: filePath, error: errorMsg, progress: 1.0));
      } catch (sendError) {
         debugLogIsolate('PS2 Isolate: Failed to send error message back to main thread: $sendError');
      }
    } finally {
      debugLogIsolate('PS2 Isolate: Exiting for ${path.basename(filePath)}.');
      // Do NOT kill the isolate here.
      // Isolate.current.kill(priority: Isolate.immediate);
    }
  }

  /// Parses the content of SYSTEM.CNF to find the BOOT2 executable path.
  static String? _findBootExecutable(Uint8List data) {
    const String bootKey = "BOOT2";
    const String cdromPrefix = "cdrom0:";
    try {
      // Decode using utf8, allowing malformed characters
      final content = utf8.decode(data, allowMalformed: true);

      // Regex to find "BOOT2 = cdrom0:\PATH\TO\EXEC.ELF;1" (case-insensitive, multiline)
      // Handles optional backslash after prefix and captures the path until space, semicolon, or newline
      final bootPattern = RegExp(
          r'^\s*' + bootKey + r'\s*=\s*' + cdromPrefix + r'\\?([^\s;]+)', // Removed \r\n from exclusion for flexibility
          caseSensitive: false,
          multiLine: true, // Search line by line
      );

      final match = bootPattern.firstMatch(content);

      if (match != null && match.groupCount >= 1) {
        String execPath = match.group(1)!;

        // Sanitize: remove version (;1) and trim whitespace
        execPath = execPath.split(';').first.trim();

        // Ensure consistent path separators (use forward slash internally)
        execPath = execPath.replaceAll('\\', '/');

        // Remove leading slash if present
        if (execPath.startsWith('/')) {
          execPath = execPath.substring(1);
        }

        return execPath; // Return the cleaned path relative to root
      }
      debugLogIsolate('BOOT2 key not found or invalid format in SYSTEM.CNF content.');
      return null;
    } catch (e) {
      debugLogIsolate('Error parsing SYSTEM.CNF for BOOT2 key: $e');
      return null;
    }
  }

   // Helper for isolate-specific logging
   static void debugLogIsolate(String message) {
     if (kDebugMode) {
       print('[${Isolate.current.debugName ?? 'Isolate'}] $message');
     }
   }
}

// --- Internal Filesystem Reader for CHD Context ---
// (This class remains unchanged from the previous version)
/// Helper class to read the ISO9660 filesystem *within* a PS2 CHD file.
/// Adapts filesystem logic to use ChdReader.readSector instead of direct file access.
class _Ps2ChdFilesystemReader {
  final ChdReader _chdReader;
  final String _chdFilePath;
  final TrackInfo _dataTrack; // Assumes the first data track contains the filesystem
  static const int _logicalSectorSize = 2048; // Logical sector size for ISO data

  // Simple sector cache for performance within the isolate
  final Map<int, Uint8List> _sectorCache = {};
  final int _maxCacheSize = 30; // Limit cache size

  _Ps2ChdFilesystemReader(this._chdReader, this._chdFilePath, this._dataTrack);

  /// Reads a logical sector from the CHD track, applying caching.
  Future<Uint8List?> _readLogicalSectorCached(int logicalSectorIndex) async {
    if (_sectorCache.containsKey(logicalSectorIndex)) {
      return _sectorCache[logicalSectorIndex];
    }

    // Read the full physical sector from the CHD track
    // Note: ChdReader.readSector takes the logical sector index relative to track start
    final rawSectorData = await _chdReader.readSector(_chdFilePath, _dataTrack, logicalSectorIndex);

    if (rawSectorData == null) {
       Ps2ChdProcessor.debugLogIsolate('CHD Read Error: Failed to read logical sector $logicalSectorIndex from $_chdFilePath');
      return null;
    }

    // Extract the relevant logical data portion based on the track's data offset and size
    if (_dataTrack.dataOffset + _logicalSectorSize > rawSectorData.length) {
       Ps2ChdProcessor.debugLogIsolate('CHD Read Warning: Physical sector $logicalSectorIndex data length (${rawSectorData.length}) is less than expected offset+size (${_dataTrack.dataOffset + _logicalSectorSize})');
       // Return what we have, truncated if necessary
       if (_dataTrack.dataOffset >= rawSectorData.length) return Uint8List(0); // Offset is beyond data
       final truncatedData = rawSectorData.sublist(_dataTrack.dataOffset);
       _cacheSector(logicalSectorIndex, truncatedData);
       return truncatedData;
    }

    final logicalSectorData = rawSectorData.sublist(_dataTrack.dataOffset, _dataTrack.dataOffset + _logicalSectorSize);

    _cacheSector(logicalSectorIndex, logicalSectorData);
    return logicalSectorData;
  }

  /// Adds a sector to the cache, managing cache size.
  void _cacheSector(int sectorIndex, Uint8List data) {
     if (_sectorCache.length >= _maxCacheSize) {
        _sectorCache.remove(_sectorCache.keys.first); // Remove oldest entry
     }
     _sectorCache[sectorIndex] = data;
  }


  /// Finds and reads a file within the CHD's filesystem.
  Future<Uint8List?> findAndReadFile(String filePath) async {
    try {
      Ps2ChdProcessor.debugLogIsolate('CHD FS: Finding root directory...');
      final rootDirSectorLba = await _findRootDirectorySector();
      if (rootDirSectorLba == null) {
        throw Exception('Could not find root directory sector in CHD.');
      }
       Ps2ChdProcessor.debugLogIsolate('CHD FS: Root directory LBA: $rootDirSectorLba');


       Ps2ChdProcessor.debugLogIsolate('CHD FS: Finding file entry for "$filePath"...');
      final fileInfo = await _findFileInDirectory(rootDirSectorLba, filePath);
      if (fileInfo == null) {
        throw Exception('File "$filePath" not found in CHD filesystem.');
      }
       Ps2ChdProcessor.debugLogIsolate('CHD FS: File entry found: LBA=${fileInfo.lba}, Size=${fileInfo.size}');


      // Read the file content sector by sector
       Ps2ChdProcessor.debugLogIsolate('CHD FS: Reading file content...');
      final totalLogicalSectors = (fileInfo.size + _logicalSectorSize - 1) ~/ _logicalSectorSize;
      final fileData = BytesBuilder(copy: false); // More efficient for appending


      for (int i = 0; i < totalLogicalSectors; i++) {
         final currentLogicalSectorIndex = fileInfo.lba + i;
        final sectorData = await _readLogicalSectorCached(currentLogicalSectorIndex);
        if (sectorData == null) {
          throw Exception('Error reading logical sector $currentLogicalSectorIndex for file "$filePath".');
        }


        final bytesRemainingInFile = fileInfo.size - fileData.length;
        final bytesToReadFromSector = (bytesRemainingInFile < _logicalSectorSize)
            ? bytesRemainingInFile
            : _logicalSectorSize;


        if (bytesToReadFromSector > sectorData.length) {
           Ps2ChdProcessor.debugLogIsolate('Warning: Reading beyond logical sector data for file $filePath sector $currentLogicalSectorIndex');
           fileData.add(sectorData); // Add all available data from the sector
        } else {
           fileData.add(sectorData.sublist(0, bytesToReadFromSector));
        }
         // Check if we've read enough bytes
         if (fileData.length >= fileInfo.size) {
            break;
         }
      }


       // Ensure the final size matches the expected size
       final resultBytes = fileData.takeBytes();
       if (resultBytes.length != fileInfo.size) {
          Ps2ChdProcessor.debugLogIsolate('Warning: Final read size (${resultBytes.length}) differs from expected size (${fileInfo.size}) for file $filePath');
          // If smaller, it's an error. If larger, truncate.
          if (resultBytes.length < fileInfo.size) {
             throw Exception('Read fewer bytes (${resultBytes.length}) than expected (${fileInfo.size}) for file $filePath.');
          }
          return Uint8List.view(resultBytes.buffer, 0, fileInfo.size); // Return truncated view
       }


      return resultBytes;


    } catch (e, stackTrace) {
      Ps2ChdProcessor.debugLogIsolate('Error finding/reading file $filePath in CHD $_chdFilePath: $e');
      Ps2ChdProcessor.debugLogIsolate('CHD Filesystem Stack Trace: $stackTrace');
      return null;
    }
  }


  /// Finds the root directory sector LBA within the CHD track.
  Future<int?> _findRootDirectorySector() async {
    try {
      // PVD is at logical sector 16 relative to the start of the track's data
      final pvdLogicalData = await _readLogicalSectorCached(16); // Read logical sector 16
      if (pvdLogicalData == null || pvdLogicalData.length < 170) { // Need bytes up to root dir size field
         Ps2ChdProcessor.debugLogIsolate('Failed to read logical PVD sector 16 from CHD or data too short.');
        return null;
      }


      // Check "CD001" identifier (already offset correctly by _readLogicalSectorCached)
      if (pvdLogicalData[1] != 0x43 || pvdLogicalData[2] != 0x44 || pvdLogicalData[3] != 0x30 ||
          pvdLogicalData[4] != 0x30 || pvdLogicalData[5] != 0x31) {
         Ps2ChdProcessor.debugLogIsolate('ISO9660 identifier "CD001" not found in logical PVD of CHD.');
        return null;
      }


      // Root directory LBA is at offset 158 (156+2) within the logical PVD sector data
      final rootDirLba = ByteData.view(pvdLogicalData.buffer).getUint32(156 + 2, Endian.little);
      return rootDirLba;
    } catch (e) {
      Ps2ChdProcessor.debugLogIsolate('Error finding root directory sector in CHD: $e');
      return null;
    }
  }


  /// Finds a file entry within a directory structure in the CHD.
  Future<Ps2FileInfo?> _findFileInDirectory(int startDirLba, String targetPath) async {
     // This implementation mirrors the logic from Ps2FilesystemReader._findFileInDirectory
     // but uses _readLogicalSectorCached and _findDirectoryEntryCHD internally.
    try {
      final normalizedTargetPath = targetPath.toUpperCase().replaceAll('\\', '/');
      final pathParts = normalizedTargetPath.split('/').where((p) => p.isNotEmpty && p != '.').toList();


      if (pathParts.isEmpty) return null; // Cannot find empty path


      int currentDirLba = startDirLba;
// Need size of current dir for _findDirectoryEntryCHD


      // Find the root directory entry itself to get its size initially
      // This requires searching the PVD's root entry, slightly complex.
      // Let's assume a reasonable default/max size for the root dir search first.
      int currentDirSize = 34 * 100; // Assume root dir fits in ~100 entries initially


      for (int i = 0; i < pathParts.length; i++) {
         final part = pathParts[i];
         final isLastPart = (i == pathParts.length - 1);
         bool lookForDirectory = !isLastPart;


         Ps2ChdProcessor.debugLogIsolate('CHD FS: Searching for "$part" (dir: $lookForDirectory) in LBA $currentDirLba');
         final foundEntry = await _findDirectoryEntryCHD(currentDirLba, currentDirSize, part, lookForDirectory);


         if (foundEntry == null) {
            Ps2ChdProcessor.debugLogIsolate('CHD FS: Path part "$part" not found.');
            return null;
         }


         if (lookForDirectory && !foundEntry.isDirectory) {
            Ps2ChdProcessor.debugLogIsolate('CHD FS: Path part "$part" found but is not a directory.');
            return null;
         }


         if (isLastPart) {
            // Found the final target file/directory
            // We specifically need a file for hashing
            if (foundEntry.isDirectory) {
               Ps2ChdProcessor.debugLogIsolate('CHD FS: Target "$part" found but it is a directory.');
               return null;
            }
            return Ps2FileInfo(lba: foundEntry.lba, size: foundEntry.size);
         }


         // Move to the next directory level
         currentDirLba = foundEntry.lba;
         currentDirSize = foundEntry.size; // Use the found directory's size for the next search
      }


      return null; // Should not be reached
    } catch (e, stackTrace) {
      Ps2ChdProcessor.debugLogIsolate('CHD FS: Error finding file "$targetPath": $e');
       Ps2ChdProcessor.debugLogIsolate('CHD FS Stack Trace: $stackTrace');
      return null;
    }
  }


  /// Finds a directory entry within a directory extent in the CHD.
  Future<Ps2DirectoryEntry?> _findDirectoryEntryCHD(
      int dirLba, int dirSize, String targetName, bool findDirectory) async {
     // This implementation mirrors the logic from Ps2FilesystemReader._findDirectoryEntry
     // but uses _readLogicalSectorCached.


     targetName = targetName.toUpperCase();
     int bytesRead = 0;
     int currentLogicalSector = dirLba;
     const maxDirectorySectors = 1000; // Sanity limit
     int sectorsChecked = 0;


     while (bytesRead < dirSize && sectorsChecked < maxDirectorySectors) {
        final sectorData = await _readLogicalSectorCached(currentLogicalSector);
        sectorsChecked++;
        if (sectorData == null) {
           Ps2ChdProcessor.debugLogIsolate('CHD FS: Failed to read directory sector $currentLogicalSector');
           break; // Stop if sector read fails
        }


        int offsetInLogicalData = 0;
        while (offsetInLogicalData < sectorData.length) {
           final recordLen = sectorData[offsetInLogicalData];
           if (recordLen == 0) {
              // Padding record, end of entries in this logical sector block
              break; // Move to next physical sector
           }


           // Basic validation for record length within the logical data block
           if (recordLen < 34 || offsetInLogicalData + recordLen > sectorData.length) {
              Ps2ChdProcessor.debugLogIsolate('CHD FS: Invalid directory record length ($recordLen) at logical sector $currentLogicalSector, offset $offsetInLogicalData. Skipping.');
              offsetInLogicalData += (recordLen > 0 ? recordLen : 34);
              bytesRead += (recordLen > 0 ? recordLen : 34);
              continue;
           }


           final recordStartOffsetInLogical = offsetInLogicalData;


           // Extract info from the record bytes (offsets relative to start of logical data)
           final fileFlags = sectorData[recordStartOffsetInLogical + 25];
           final isDirectory = (fileFlags & 0x02) != 0;
           final nameLen = sectorData[recordStartOffsetInLogical + 32];


           // Check type match and name length validity
           if (findDirectory == isDirectory && nameLen > 0 && recordStartOffsetInLogical + 33 + nameLen <= sectorData.length) {
              String entryName = '';
              try {
                 entryName = latin1.decode(sectorData.sublist(recordStartOffsetInLogical + 33, recordStartOffsetInLogical + 33 + nameLen));
              } catch (_) { entryName = ''; }


              // Skip "." and ".." entries
              if (entryName.isNotEmpty && entryName.codeUnitAt(0) != 0 && entryName.codeUnitAt(0) != 1) {
                 final versionIndex = entryName.lastIndexOf(';');
                 if (versionIndex > 0) entryName = entryName.substring(0, versionIndex);
                 entryName = entryName.toUpperCase();


                 if (entryName == targetName) {
                    // Found it! Get LBA and Size
                    final entryLba = ByteData.view(sectorData.buffer, sectorData.offsetInBytes).getUint32(recordStartOffsetInLogical + 2, Endian.little);
                    final entrySize = ByteData.view(sectorData.buffer, sectorData.offsetInBytes).getUint32(recordStartOffsetInLogical + 10, Endian.little);
                    return Ps2DirectoryEntry(
                       name: entryName, // Return normalized name
                       lba: entryLba,
                       size: entrySize,
                       isDirectory: isDirectory,
                    );
                 }
              }
           }


           // Move to the next record within the logical data block
           offsetInLogicalData += recordLen;
           bytesRead += recordLen; // Track total bytes processed across sectors
        }
        currentLogicalSector++; // Move to the next logical sector for the directory


        // Break if we've processed more bytes than the directory size indicates
        // (dirSize might be inaccurate sometimes, but helps prevent excessive reads)
        if (bytesRead >= dirSize) break;
     }


     if (sectorsChecked >= maxDirectorySectors) {
        Ps2ChdProcessor.debugLogIsolate("CHD FS: Directory search stopped after checking maximum sectors ($maxDirectorySectors). Target '$targetName' not found.");
     }


     return null; // Not found
  }
}


// --- Helper classes (can be defined in chd_read_common.dart if preferred) ---
// Re-defining minimally here for isolate self-containment if needed,
// but ideally these would come from a shared location if not already in chd_read_common.


/// Helper class for file info (replicated from ps2_filesystem.dart for clarity)
class Ps2FileInfo {
  final int lba;
  final int size;
  Ps2FileInfo({required this.lba, required this.size});
}


/// Helper class for directory entry (replicated from ps2_filesystem.dart for clarity)
class Ps2DirectoryEntry {
  final String name;
  final int lba;
  final int size;
  final bool isDirectory;
  Ps2DirectoryEntry({required this.name, required this.lba, required this.size, required this.isDirectory});
}
