// lib/services/hashing/ps2/ps2_hash.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

// Consider adding a package for controlling concurrency like 'pool'
// import 'package:pool/pool.dart';

import 'ps2_chd_processor.dart';
import 'ps2_filesystem.dart';

class Ps2HashCalculator {
  static const String _bootKey = "BOOT2";

  Future<Map<String, String>> hashPs2FilesInFolders(List<String> folders) async {
    final Map<String, String> hashes = {};
    final validExtensions = ['.iso', '.bin', '.chd'];

    // --- Start of modifications ---

    final List<File> chdFiles = [];
    final List<File> isoBinFiles = [];

    // 1. Find and separate files by type first
    for (final folder in folders) {
      try {
        final dir = Directory(folder);
        if (!await dir.exists()) {
          debugPrint('Warning: Folder not found: $folder');
          continue;
        }

        await for (final entity in dir.list(recursive: true, followLinks: false)) {
          if (entity is File) {
             final fileExtension = path.extension(entity.path).toLowerCase();
             if (validExtensions.contains(fileExtension)) {
                 if (fileExtension == '.chd') {
                     chdFiles.add(entity);
                 } else { // .iso or .bin
                     isoBinFiles.add(entity);
                 }
             }
          }
        }
      } catch (e, stackTrace) {
        debugPrint('Error listing files in folder $folder: $e');
        debugPrint('Stack trace: $stackTrace');
      }
    }

    final totalFiles = chdFiles.length + isoBinFiles.length;
    debugPrint('Found ${chdFiles.length} CHD files and ${isoBinFiles.length} ISO/BIN files.');
    if (totalFiles == 0) return {};

    // --- Process CHDs Concurrently ---
    debugPrint('Starting concurrent CHD processing...');
    final List<Future<MapEntry<String, String?>>> chdFutures = [];

    // Optional: Limit concurrency using a Pool
    // Adjust the number based on testing (e.g., number of CPU cores)
    // final pool = Pool(Platform.numberOfProcessors);

    for (int i = 0; i < chdFiles.length; i++) {
        final file = chdFiles[i];
        final filePath = file.path;

        // Check existence right before adding future
        if (!await file.exists()) {
             debugPrint('Skipping CHD (not found): ${path.basename(filePath)}');
             continue;
        }

        debugPrint('Queueing CHD ${i + 1}/${chdFiles.length}: ${path.basename(filePath)}');

        // Create a future for each CHD hash calculation
        final future = () async {
            String? hash;
            try {
                // Use the isolate processor
                hash = await Ps2ChdProcessor.processChd(filePath);
            } catch (e, stackTrace) {
                debugPrint('Error processing CHD $filePath in future: $e');
                debugPrint('Stack trace: $stackTrace');
                hash = null; // Ensure it returns null on error
            }
            // Return a MapEntry with the path and the resulting hash (or null)
            return MapEntry(filePath, hash);
        }(); // Immediately invoke the async closure to get the Future

        // // To use with Pool:
        // final future = pool.withResource(() async {
        //    // ... same async logic as above ...
        //    return MapEntry(filePath, hash);
        // });

        chdFutures.add(future);
    }

    // Wait for all CHD processing futures to complete
    final List<MapEntry<String, String?>> chdResults = await Future.wait(chdFutures);

    // Add successful CHD hashes to the map
    int chdSuccessCount = 0;
    for (final result in chdResults) {
        if (result.value != null && result.value!.isNotEmpty) {
            hashes[result.key] = result.value!;
            chdSuccessCount++;
            debugPrint('✓ Hashed PS2 (chd): ${path.basename(result.key)} -> ${result.value}');
        } else {
            debugPrint('✗ Failed to hash PS2 CHD: ${path.basename(result.key)}');
        }
    }
    debugPrint('Finished concurrent CHD processing. $chdSuccessCount successful hashes.');


    // --- Process ISO/BIN Files Sequentially (for now) ---
    debugPrint('Starting sequential ISO/BIN processing...');
    int isoBinProcessedCount = 0;
    for (final file in isoBinFiles) {
        final filePath = file.path;
        final fileExtension = path.extension(filePath).toLowerCase();
        isoBinProcessedCount++;

        try {
            if (!await file.exists()) {
               debugPrint('Skipping ISO/BIN (not found): ${path.basename(filePath)}');
               continue;
            }

            debugPrint('Processing ISO/BIN $isoBinProcessedCount/${isoBinFiles.length}: ${path.basename(filePath)}');
            String? hash = await _hashPs2IsoBinFile(filePath); // Still sequential

            if (hash != null && hash.isNotEmpty) {
              hashes[filePath] = hash;
              debugPrint('✓ Hashed PS2 (${fileExtension.substring(1)}): ${path.basename(filePath)} -> $hash');
            } else {
              debugPrint('✗ Failed to hash PS2 ISO/BIN: ${path.basename(filePath)}');
            }
          } catch (e, stackTrace) {
            debugPrint('Error hashing PS2 ISO/BIN file $filePath: $e');
            debugPrint('Stack trace: $stackTrace');
          }
           // Optional delay to yield UI thread if needed during long sync processing
           // await Future.delayed(Duration.zero);
    }
    debugPrint('Finished sequential ISO/BIN processing.');

    debugPrint('Finished PS2 hashing. Found ${hashes.length} hashes.');
    return hashes;
  }

  /// Hashes a PS2 ISO or BIN file using direct filesystem access.
  ///
  /// [filePath]: Path to the .iso or .bin file.
  /// Returns the MD5 hash or null on error.
  Future<String?> _hashPs2IsoBinFile(String filePath) async {
    final file = File(filePath);
    // Existence already checked in the calling loop, but double-check doesn't hurt
    if (!await file.exists()) {
       debugPrint('ISO/BIN file not found: $filePath');
       return null;
    }


    try {
      // Use the dedicated filesystem reader for ISO/BIN
      final fsReader = Ps2FilesystemReader(file);

      // 1. Find and read SYSTEM.CNF
      final systemCnfData = await fsReader.findAndReadFile('SYSTEM.CNF');
      if (systemCnfData == null) {
        debugPrint('Could not find or read SYSTEM.CNF in $filePath');
        // Attempt fallback? For PS2, SYSTEM.CNF is usually mandatory.
        return null;
      }

      // 2. Parse SYSTEM.CNF to find the boot executable (BOOT2)
      final exePath = _findBootExecutable(systemCnfData);
      if (exePath == null) {
        debugPrint('Could not find BOOT2 executable path in SYSTEM.CNF for $filePath');
        return null;
      }
      debugPrint('Found PS2 boot executable in ISO/BIN: $exePath');


      // 3. Find and read the executable file
      // Note: exePath is relative to the root, e.g., "SLUS_123.45" or "MYGAME/EXEC.ELF"
      final exeData = await fsReader.findAndReadFile(exePath);
      if (exeData == null) {
        debugPrint('Could not find or read executable "$exePath" in $filePath');
        return null;
      }

      // Optional: Check for ELF header
      if (exeData.length >= 4) {
         if (exeData[0] != 0x7F || exeData[1] != 0x45 || exeData[2] != 0x4C || exeData[3] != 0x46) {
            debugPrint('Warning: PS2 executable "$exePath" in ISO/BIN does not have ELF header.');
         }
      } else {
          debugPrint('Warning: PS2 executable "$exePath" in ISO/BIN is very small (< 4 bytes).');
      }


      // 4. Calculate the MD5 hash
      // Hash combines the executable path string (UTF-8) and the executable content.
      final pathBytes = utf8.encode(exePath); // Use the path found in SYSTEM.CNF
      final combinedData = Uint8List(pathBytes.length + exeData.length);
      combinedData.setRange(0, pathBytes.length, pathBytes);
      combinedData.setRange(pathBytes.length, combinedData.length, exeData);

      final digest = crypto.md5.convert(combinedData);
      return digest.toString();

    } catch (e, stackTrace) {
      debugPrint('Error hashing PS2 ISO/BIN file $filePath: $e');
      debugPrint('Stack trace: $stackTrace');
      return null;
    }
  }

  /// Parses the content of SYSTEM.CNF to find the BOOT2 executable path.
  /// (Static helper method, could be moved elsewhere if needed)
  static String? _findBootExecutable(Uint8List data) {
    // Re-uses the same logic as in Ps2ChdProcessor
    const String cdromPrefix = "cdrom0:";
    try {
      final content = utf8.decode(data, allowMalformed: true);
      final bootPattern = RegExp(
          r'^\s*' + _bootKey + r'\s*=\s*' + cdromPrefix + r'\\?([^\s;]+)',
          caseSensitive: false,
          multiLine: true,
      );
      final match = bootPattern.firstMatch(content);

      if (match != null && match.groupCount >= 1) {
        String execPath = match.group(1)!;
        execPath = execPath.split(';').first.trim();
        execPath = execPath.replaceAll('\\', '/'); // Use forward slash
         if (execPath.startsWith('/')) {
           execPath = execPath.substring(1); // Remove leading slash
         }
        return execPath;
      }
       debugPrint('BOOT2 key not found or invalid format in SYSTEM.CNF content.');
      return null;
    } catch (e) {
      debugPrint('Error parsing SYSTEM.CNF for BOOT2 key: $e');
      return null;
    }
  }
}
