// arduboy_hash.dart

import 'dart:io';
import 'dart:typed_data'; // Import for Uint8List, BytesBuilder

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

/// Class to handle Arduboy game hashing specifically, matching rc_hash_text logic
class ArduboyHashIntegration {
  /// Hashes all Arduboy games (.hex files) in the provided folders
  /// Returns a map of file paths to MD5 hashes, matching rc_hash_text
  Future<Map<String, String>> hashArduboyFilesInFolders(List<String> folders) async {
    debugPrint('Starting Arduboy hashing (rc_hash_text logic, non-incremental), this might take some time...');

    final Map<String, String> arduboyHashes = {};
    const int CR = 13; // ASCII Carriage Return
    const int LF = 10; // ASCII Line Feed

    for (final folderPath in folders) {
      final directory = Directory(folderPath);

      if (await directory.exists()) {
        await for (final entity in directory.list(recursive: true)) {
          if (entity is File) {
            final extension = path.extension(entity.path).toLowerCase();

            // Only process .hex files for Arduboy
            if (extension == '.hex') {
              try {
                // Read the raw bytes of the file
                final Uint8List fileBytes = await entity.readAsBytes();

                // --- Correction Start ---
                // Use BytesBuilder to construct the byte sequence to be hashed
                final bytesBuilder = BytesBuilder(copy: false); // Avoid unnecessary copies
                // --- Correction End ---

                int currentPos = 0;
                final int endPos = fileBytes.length;

                while (currentPos < endPos) {
                  int lineStart = currentPos;
                  // Find end of line content (before CR or LF)
                  while (currentPos < endPos && fileBytes[currentPos] != CR && fileBytes[currentPos] != LF) {
                    currentPos++;
                  }

                  // Add the line content bytes to the builder
                  if (currentPos > lineStart) {
                    // Add view of bytes directly
                    bytesBuilder.add(Uint8List.sublistView(fileBytes, lineStart, currentPos));
                  }

                  // ALWAYS add a normalized newline (LF byte) to the builder
                  bytesBuilder.addByte(LF);

                  // Skip the original line ending characters (CR, LF, or CRLF)
                  if (currentPos < endPos && fileBytes[currentPos] == CR) {
                    currentPos++;
                  }
                  if (currentPos < endPos && fileBytes[currentPos] == LF) {
                    currentPos++;
                  }
                }

                // --- Correction Start ---
                // 2. Get the final byte sequence from the builder
                final Uint8List bytesToHash = bytesBuilder.toBytes();

                // 3. Hash the constructed bytes all at once using md5.convert
                final hashDigest = md5.convert(bytesToHash);

                // 4. Convert the resulting Digest to a hex string
                final hash = hashDigest.toString();
                // --- Correction End ---


                arduboyHashes[entity.path] = hash;
                debugPrint('Hashed Arduboy file (rc_hash_text logic): ${entity.path} -> $hash');

              } catch (e) {
                debugPrint('Error hashing Arduboy file ${entity.path}: $e');
              }
            }
          }
        }
      }
    }

    return arduboyHashes;
  }

  // --- Removed helper function as Digest.toString() is used ---
}