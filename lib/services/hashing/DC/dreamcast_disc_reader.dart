// lib/services/hashing/DC/dreamcast_disc_reader.dart
import 'dart:convert';
import 'dart:io';
import 'dart:math'; // For min()

import 'package:flutter/foundation.dart';
// Ensure these paths are correct for your project structure
import 'package:retroachievements_organizer/services/hashing/DC/dreamcast_hash_utils.dart';
import 'package:retroachievements_organizer/services/hashing/DC/iso_parser.dart'; // Import the ISO parser

/// Helper class to store parsed GDI track information.
class GdiTrack {
  final int trackNumber;
  final int lba; // Logical Block Address (sector start) on the original GD-ROM
  final int type; // 4 = data, 0 = audio
  final int sectorSize; // Raw sector size reported in GDI (e.g., 2352, 2048)
  final String filename; // Relative path to the track file

  GdiTrack({
    required this.trackNumber,
    required this.lba,
    required this.type,
    required this.sectorSize,
    required this.filename,
  });
}

/// Reads Dreamcast disc image formats (GDI, CUE/BIN, CDI) and generates hashes.
class DreamcastDiscReader {

  /// Processes the file at the given path based on its extension.
  Future<String?> processFile(String path, String extension) async {
    switch (extension.toLowerCase()) { // Use lowercase extension
      case 'gdi':
        return await _processGdiFile(path);
      case 'cue':
        return await _processCueFile(path);
      case 'cdi':
        // CDI processing remains basic and likely produces incorrect hashes
        // as it doesn't parse the CDI filesystem to find the real boot file.
        debugPrint('CDI boot file extraction not fully implemented, hash may be incorrect.');
        return await _processCdiFile(path);
      default:
        debugPrint('Unsupported extension for DreamcastDiscReader: $extension');
        return null;
    }
  }

  /// Processes a GDI (GD-ROM Image) file set.
   Future<String?> _processGdiFile(String gdiPath) async {
    RandomAccessFile? trackFileHandle;
    SectorReader? sectorReader;
    int determinedDataOffset = 16; // Start with default

    try {
      // 1. Parse GDI
      final file = File(gdiPath);
      if (!await file.exists()) return null;
      final gdiContent = await file.readAsString();
      final tracks = _parseGdiFile(gdiContent);
      if (tracks.isEmpty) return null;

      // 2. Find Data Track
      GdiTrack? dataTrack = tracks.firstWhere(
        (t) => t.trackNumber == 3 && t.type == 4,
        orElse: () {
           return tracks.firstWhere((t) => t.type == 4); 
         
        });
      if (dataTrack == null) return null;
      debugPrint('Using GDI data track: #${dataTrack.trackNumber}, File: ${dataTrack.filename}, Raw Sector Size: ${dataTrack.sectorSize}');

      // 3. Open Track File
      final dataTrackFilePath = _resolveTrackFilePath(gdiPath, dataTrack.filename);
      if (dataTrackFilePath == null) return null;
      final dataTrackFile = File(dataTrackFilePath);
      if (!await dataTrackFile.exists()) return null;
      trackFileHandle = await dataTrackFile.open(mode: FileMode.read);

      // 4. Determine Offset *BEFORE* creating SectorReader (if applicable)
      int physicalSectorSize = dataTrack.sectorSize;
      if (physicalSectorSize == 2352) {
          final rawSector0 = Uint8List(physicalSectorSize);
          int bytesRead = 0;
          try {
              // Read the first raw sector directly
              bytesRead = await trackFileHandle.readInto(rawSector0);
              await trackFileHandle.setPosition(0); // Reset position!
              if (bytesRead > 0) {
                 determinedDataOffset = DreamcastHashUtils.detectDataOffset(
                    rawSector0.sublist(0, bytesRead),
                    0 // Checking logical sector 0
                 );
              } else {
                 debugPrint('GDI Warning: Read 0 bytes from start of track file. Using default offset $determinedDataOffset.');
              }
          } catch (e) {
              debugPrint('GDI Warning: Error reading start of track file. Using default offset $determinedDataOffset. Error: $e');
              await trackFileHandle.setPosition(0); // Attempt reset anyway
          }
      } else {
          determinedDataOffset = 0; // Assume offset 0 for non-2352 sizes
      }
      debugPrint('Using physicalSectorSize: $physicalSectorSize, dataOffsetInSector: $determinedDataOffset for GDI track reader.');

      // 5. Create SectorReader with determined offset
      sectorReader = FileSectorReader(
        trackFileHandle,
        physicalSectorSize: physicalSectorSize,
        dataOffsetInSector: determinedDataOffset // Pass the determined offset
      );

      // 6. Extract IP.BIN (using the sector reader)
      Uint8List? ipBinData;
      Uint8List? logicalSector0Data = await sectorReader.readSector(0);
      if (logicalSector0Data != null &&
          logicalSector0Data.length >= DreamcastHashUtils.IP_BIN_SIZE &&
          DreamcastHashUtils.validateSegaSegakatana(logicalSector0Data)) {
        ipBinData = logicalSector0Data.sublist(0, DreamcastHashUtils.IP_BIN_SIZE);
        debugPrint('Found SEGA SEGAKATANA marker and extracted IP.BIN from GDI logical sector 0.');
      } else {
         // Try sector 1 as fallback
        final logicalSector1Data = await sectorReader.readSector(1);
        if (logicalSector1Data != null &&
            logicalSector1Data.length >= DreamcastHashUtils.IP_BIN_SIZE &&
            DreamcastHashUtils.validateSegaSegakatana(logicalSector1Data)) {
          ipBinData = logicalSector1Data.sublist(0, DreamcastHashUtils.IP_BIN_SIZE);
          debugPrint('Found SEGA SEGAKATANA marker and extracted IP.BIN from GDI logical sector 1.');
        } else {
           debugPrint('SEGA SEGAKATANA marker not found in logical sector 0 or 1 of GDI track file.');
           return null;
        }
      }

      // 7. Extract Boot File Name Bytes
      final bootFileNameBytes = DreamcastHashUtils.extractBootFileNameBytes(ipBinData);
      if (bootFileNameBytes == null || bootFileNameBytes.isEmpty) return null;
      String isoBootFileName;
      try {
         isoBootFileName = ascii.decode(bootFileNameBytes, allowInvalid: true).toUpperCase().split(';').first;
      } catch(e) { return null; }
      debugPrint('Found boot file name in IP.BIN (Using: $isoBootFileName for lookup)');


      // 8. Find and Read Boot File
      IsoFileInfo? bootFileInfo = await IsoParser.findFileInIso(sectorReader!, isoBootFileName);
      if (bootFileInfo == null && isoBootFileName == "1ST_READ.BIN") {
        debugPrint('Using fixed fallback location for 1ST_READ.BIN');
        bootFileInfo = IsoFileInfo(45032, 1024 * 1024);
      }
      if (bootFileInfo == null) {
         debugPrint('Could not locate boot file "$isoBootFileName"');
         return null;
      }

      Uint8List? actualBootFileContent = await IsoParser.readFileContent(sectorReader, bootFileInfo);
      if (actualBootFileContent == null) {
        debugPrint('Failed to read content for boot file "$isoBootFileName".');
        return null;
      }
      debugPrint('Successfully read ${actualBootFileContent.length} bytes for boot file.');

      // 9. Calculate Hash
      final hash = DreamcastHashUtils.calculateDreamcastHash(
        ipBinData,
        bootFileNameBytes,
        actualBootFileContent
      );

      return hash; // Return null if calculation failed

    } catch (e, s) {
      debugPrint('Error processing GDI file $gdiPath: $e\n$s');
      return null;
    } finally {
      await sectorReader?.close(); // No-op for FileSectorReader
      try { await trackFileHandle?.close(); } catch (_) {}
    }
  }

  /// Processes a CUE/BIN file set.
     Future<String?> _processCueFile(String cuePath) async {
    RandomAccessFile? binFileHandle;
    String? binFilePath;
    SectorReader? sectorReader;
    int determinedDataOffset = 16; // Default assumption

    try {
      // 1. Parse CUE
      final cueFile = File(cuePath);
       if (!await cueFile.exists()) return null;
      final cueContent = await cueFile.readAsString();
      binFilePath = _parseCueFileForBin(cueContent, cuePath);
      if (binFilePath == null) return null;
      debugPrint('Found BIN file for CUE: $binFilePath');

      // 2. Open BIN
      final binFile = File(binFilePath);
      if (!await binFile.exists()) return null;
      binFileHandle = await binFile.open(mode: FileMode.read);

      // 3. Detect BIN format & Determine Offset *BEFORE* creating SectorReader
      Uint8List? ipBinData;
      int physicalSectorSize = 2048; // Start assuming Mode 1

      // Read start of file to detect format based on IP.BIN location
      final initialData = Uint8List(2352 * 2); // Read enough for offset checks
      int bytesReadInitial = 0;
       try {
         bytesReadInitial = await binFileHandle.readInto(initialData);
         await binFileHandle.setPosition(0); // Reset position!
         if (bytesReadInitial == 0) return null; // Failed to read

         final actualInitialData = initialData.sublist(0, bytesReadInitial);

        // Check different offsets assuming 2352 layout first
        if (actualInitialData.length >= 16 + DreamcastHashUtils.IP_BIN_SIZE &&
            DreamcastHashUtils.validateSegaSegakatana(actualInitialData.sublist(16))) {
           ipBinData = actualInitialData.sublist(16, 16 + DreamcastHashUtils.IP_BIN_SIZE);
           determinedDataOffset = 16;
           physicalSectorSize = 2352;
           debugPrint('Found IP.BIN at offset 16 in BIN file (Assuming Mode 2/2352).');
        } else if (actualInitialData.length >= 24 + DreamcastHashUtils.IP_BIN_SIZE &&
                   DreamcastHashUtils.validateSegaSegakatana(actualInitialData.sublist(24))) {
           ipBinData = actualInitialData.sublist(24, 24 + DreamcastHashUtils.IP_BIN_SIZE);
           determinedDataOffset = 24;
           physicalSectorSize = 2352;
           debugPrint('Found IP.BIN at offset 24 in BIN file (Assuming Mode 2 Form 2/2352).');
        } else if (actualInitialData.length >= DreamcastHashUtils.IP_BIN_SIZE &&
                   DreamcastHashUtils.validateSegaSegakatana(actualInitialData)) {
           ipBinData = actualInitialData.sublist(0, DreamcastHashUtils.IP_BIN_SIZE);
           determinedDataOffset = 0;
           physicalSectorSize = 2048; // Assume Mode 1 if marker is at offset 0
           debugPrint('Found IP.BIN at offset 0 in BIN file (Assuming Mode 1/2048).');
        } else {
           // If no marker found, cannot proceed reliably for Dreamcast
           debugPrint('Could not find SEGA SEGAKATANA marker near start of BIN file: $binFilePath');
           return null;
        }
       } catch (e) {
          debugPrint('Error reading initial data from BIN file: $e');
          await binFileHandle.setPosition(0); // Attempt reset
          return null;
       }

      // 4. Create SectorReader with determined parameters
      sectorReader = FileSectorReader(
          binFileHandle,
          physicalSectorSize: physicalSectorSize,
          dataOffsetInSector: determinedDataOffset // Use determined offset
      );

      // 5. Extract Boot File Name Bytes
      final bootFileNameBytes = DreamcastHashUtils.extractBootFileNameBytes(ipBinData!); // ipBinData checked above
      if (bootFileNameBytes == null || bootFileNameBytes.isEmpty) return null;
      String isoBootFileName;
      try {
         isoBootFileName = ascii.decode(bootFileNameBytes, allowInvalid: true).toUpperCase().split(';').first;
      } catch(e) { return null; }
       debugPrint('Found boot file name in IP.BIN (Using: $isoBootFileName for lookup)');

      // 6. Find and Read Boot File
      IsoFileInfo? bootFileInfo = await IsoParser.findFileInIso(sectorReader, isoBootFileName);
      if (bootFileInfo == null && isoBootFileName == "1ST_READ.BIN") {
        debugPrint('Using fixed fallback location for 1ST_READ.BIN');
        bootFileInfo = IsoFileInfo(45032, 1024 * 1024);
      }
      if (bootFileInfo == null) {
         debugPrint('Could not locate boot file "$isoBootFileName"');
         return null;
      }

      Uint8List? actualBootFileContent = await IsoParser.readFileContent(sectorReader, bootFileInfo);
      if (actualBootFileContent == null) {
         debugPrint('Failed to read content for boot file "$isoBootFileName".');
        return null;
      }
      debugPrint('Successfully read ${actualBootFileContent.length} bytes for boot file.');

      // 7. Calculate Hash
      final hash = DreamcastHashUtils.calculateDreamcastHash(
          ipBinData,
          bootFileNameBytes,
          actualBootFileContent);

      return hash;

    } catch (e, s) {
      debugPrint('Error processing CUE file $cuePath (BIN: $binFilePath): $e\n$s');
      return null;
    } finally {
      await sectorReader?.close();
      try { await binFileHandle?.close(); } catch (_) {}
    }
  }
  /// Processes a CDI (DiscJuggler Image) file.
  /// NOTE: This implementation is basic. It finds IP.BIN heuristically but
  /// DOES NOT parse the CDI filesystem to find the actual boot file content.
  /// Hashes generated for CDI files using this method will likely be INCORRECT
  /// compared to reference implementations that read the real boot file.
  Future<String?> _processCdiFile(String path) async {
    RandomAccessFile? fileStream;
    try {
      final file = File(path);
      if (!await file.exists()) {
        debugPrint('CDI file does not exist: $path');
        return null;
      }

      final fileSize = await file.length();
      if (fileSize < DreamcastHashUtils.IP_BIN_SIZE) {
        debugPrint('CDI file too small: $path');
        return null;
      }

      fileStream = await file.open(mode: FileMode.read);

      // Heuristically search for IP.BIN near the beginning of the file
      // Search up to 1 MB or file size, whichever is smaller
      final searchLimit = min(fileSize, 1 * 1024 * 1024);
      final initialData = Uint8List(searchLimit);
      int bytesRead = 0;
      try {
        bytesRead = await fileStream.readInto(initialData);
      } catch (e) {
        debugPrint('Error reading initial data from CDI: $e');
        return null;
      }

      if (bytesRead < DreamcastHashUtils.IP_BIN_SIZE) {
        debugPrint('Could not read enough data from CDI to find IP.BIN');
        return null;
      }

      final actualInitialData = initialData.sublist(0, bytesRead);

      Uint8List? ipBinData;
      // Search on common sector data boundaries (0, 16, 24) within the searched range
      final searchOffsets = [0, 16, 24]; // Common data offsets
      // Extend search a bit further on sector boundaries if needed
      for (int baseOffset = 0; baseOffset + 2352 <= actualInitialData.length; baseOffset += 2048) { // Step by logical sectors
         for (int dataOffset in searchOffsets) {
            int checkOffset = baseOffset + dataOffset;
            if (checkOffset + DreamcastHashUtils.IP_BIN_SIZE <= actualInitialData.length) {
               if (DreamcastHashUtils.validateSegaSegakatana(actualInitialData.sublist(checkOffset))) {
                  ipBinData = actualInitialData.sublist(checkOffset, checkOffset + DreamcastHashUtils.IP_BIN_SIZE);
                  debugPrint('Found IP.BIN marker in CDI at approximate offset $checkOffset');
                  break; // Stop searching offset types
               }
            }
         }
         if (ipBinData != null) break; // Stop searching sectors
         // Limit sector search depth to avoid excessive searching in large CDIs
         if (baseOffset > 10 * 2048) break; // Stop after ~10 sectors
      }


      if (ipBinData == null) {
        // Marker not found near the start
        debugPrint('Not a valid Dreamcast CDI: no SEGA SEGAKATANA marker found near start.');
        return null;
      }

      // Extract boot file name from the found IP.BIN
      final bootFileName = DreamcastHashUtils.extractBootFileNameBytes(ipBinData);
      if (bootFileName == null || bootFileName.isEmpty) {
        debugPrint('Boot executable not specified in IP.BIN (CDI)');
        return null; // Cannot proceed without boot filename for hashing standard
      }
      debugPrint('Found boot file name in IP.BIN (CDI): $bootFileName');

      // *** CRITICAL LIMITATION FOR CDI ***
      // This part uses DUMMY data because parsing CDI filesystem is not implemented.
      // The resulting hash WILL NOT MATCH reference implementations.
      debugPrint('Warning: Using dummy boot file content for CDI. Hash will likely be incorrect.');
      final dummyBootContent = Uint8List(0); // Placeholder, size doesn't really matter here

      // Calculate hash using the dummy boot file content
      final hash = DreamcastHashUtils.calculateDreamcastHash(
          ipBinData, bootFileName, dummyBootContent);

      debugPrint('Generated Dreamcast hash for CDI (using dummy boot file): $hash');
      return hash; // Return the potentially incorrect hash

    } catch (e, s) {
      debugPrint('Error processing CDI file $path: $e\n$s');
      return null;
    } finally {
       // Ensure file handle is closed
       try {
          await fileStream?.close();
       } catch (_) {}
    }
  }


  // --- Helper Methods ---

  /// Parses the content of a GDI file into a list of GdiTrack objects.
  List<GdiTrack> _parseGdiFile(String content) {
    final tracks = <GdiTrack>[];
    // Split by lines, handling both \n and \r\n
    final lines = content.split(RegExp(r'\r?\n'));

    if (lines.isEmpty) return tracks; // Empty file

    // First line should be the number of tracks
    final trackCount = int.tryParse(lines.first.trim());
    if (trackCount == null || trackCount <= 0) {
       debugPrint('Invalid or missing track count in GDI file: ${lines.first}');
       return tracks; // Invalid format
    }

    // Parse each subsequent line expected to contain track info
    for (int i = 1; i <= trackCount && i < lines.length; i++) {
      final line = lines[i].trim();
      // Skip empty lines or lines potentially starting with comments (though not standard)
      if (line.isEmpty || line.startsWith('#')) continue;

      // Split the line by whitespace, robustly handling multiple spaces/tabs
       final parts = line.split(RegExp(r'\s+'));

      // Expect at least 5 parts: Track#, LBA, Type, SectorSize, Filename
      // GDI spec often includes a 6th "Offset" part (usually 0 for tracks) which we can ignore for hashing.
      if (parts.length < 5) {
        debugPrint('Invalid GDI track line format (too few parts): $line');
        continue; // Skip malformed line
      }

      // Parse individual parts with error checking
      final trackNumber = int.tryParse(parts[0]);
      final lba = int.tryParse(parts[1]); // Start sector (LBA)
      final type = int.tryParse(parts[2]); // 0=Audio, 4=Data
      final sectorSize = int.tryParse(parts[3]); // e.g., 2336, 2352, 2048

      // Handle filenames that might contain spaces and be quoted
      String filename;
      if (parts[4].startsWith('"')) {
          // Find the full quoted filename, potentially spanning multiple parts
          final startIndex = line.indexOf('"') + 1;
          final endIndex = line.lastIndexOf('"');
          if (startIndex > 0 && endIndex > startIndex) {
              filename = line.substring(startIndex, endIndex);
          } else {
              // Malformed quotes, try just taking the 5th part without quotes
              filename = parts[4].replaceAll('"', '');
              debugPrint('Warning: Malformed quotes in GDI filename, using: $filename');
          }
      } else {
          // Filename is not quoted, just use the 5th part
          filename = parts[4];
      }


      // Validate parsed integer values
      if (trackNumber == null || lba == null || type == null || sectorSize == null) {
        debugPrint('Invalid GDI track data (parsing failed for numeric values): $line');
        continue; // Skip line with invalid numbers
      }

      // Add the successfully parsed track to the list
      tracks.add(GdiTrack(
        trackNumber: trackNumber,
        lba: lba,
        type: type,
        sectorSize: sectorSize,
        filename: filename,
      ));
    }
    // Return the list of parsed tracks
    return tracks;
  }

  /// Resolves the absolute path to a track file given the GDI path and track filename.
  /// Handles potential case variations.
  String? _resolveTrackFilePath(String gdiPath, String trackFilename) {
    final directory = File(gdiPath).parent; // Directory containing the GDI file
    final separator = Platform.pathSeparator; // System-specific path separator

    // Clean the track filename: remove potential directory parts, keep only filename.ext
    final cleanTrackFilename = trackFilename.split(RegExp(r'[/\\]')).last;

    // List of potential paths to check (exact case, lowercase, uppercase)
    final possiblePaths = [
      '${directory.path}$separator$cleanTrackFilename', // Exact case as in GDI
      '${directory.path}$separator${cleanTrackFilename.toLowerCase()}', // All lowercase
      '${directory.path}$separator${cleanTrackFilename.toUpperCase()}', // All uppercase
    ];

    // Check each potential path for existence
    for (final path in possiblePaths) {
       try {
          // Use FileStat.statSync for faster existence check than File.existsSync()
          final stat = FileStat.statSync(path);
          if (stat.type != FileSystemEntityType.notFound) {
             // debugPrint('Resolved track file path: $path');
             return path; // Return the first existing path found
          }
       } catch (e) {
          // Ignore errors like "Permission denied", file not found is handled by stat type
          if (e is! FileSystemException || e.osError?.errorCode != 2 /* ENOENT */ ) {
             debugPrint("Error checking file path $path: $e");
          }
       }
    }

    // If no path was found, log directory contents for debugging aid
    try {
      debugPrint('Could not resolve track file "$cleanTrackFilename". Directory contents (${directory.path}):');
      directory.listSync().forEach((entity) {
        // Print only the filename part of each entity in the directory
        debugPrint('  - ${entity.path.split(separator).last}');
      });
    } catch (e) {
      // Handle potential errors listing the directory (e.g., permissions)
      debugPrint('Error listing directory for debugging: $e');
    }

    // Return null if the track file could not be found
    return null;
  }

  /// Parses a CUE sheet content to find the first referenced binary file (BIN, IMG, ISO).
  String? _parseCueFileForBin(String cueContent, String cuePath) {
    // Split cue content into lines, handling different line endings
    final lines = cueContent.split(RegExp(r'\r?\n'));
    String? currentFileName; // Track filename from the last FILE command

    // Iterate through each line of the CUE sheet
    for (final line in lines) {
      final trimmedLine = line.trim(); // Remove leading/trailing whitespace
      // Check for FILE command (case-insensitive)
      if (trimmedLine.toUpperCase().startsWith('FILE')) {
          // Extract filename, robustly handling quotes
          int startQuote = trimmedLine.indexOf('"');
          int endQuote = trimmedLine.lastIndexOf('"');
          String filename;

          if (startQuote != -1 && endQuote > startQuote) {
              // Filename is quoted
              filename = trimmedLine.substring(startQuote + 1, endQuote);
          } else {
              // Filename is not quoted, find first space after FILE and take the rest
              // (Handle potential spaces in "FILE " command itself)
              int firstSpace = trimmedLine.indexOf(RegExp(r'\s'));
              if (firstSpace != -1) {
                  String potentialFilenamePart = trimmedLine.substring(firstSpace).trim();
                  // Check if it ends with BINARY/MOTOROLA/etc. and remove it
                  List<String> parts = potentialFilenamePart.split(RegExp(r'\s+'));
                  if (parts.length > 1 && ['BINARY', 'MOTOROLA', 'AIFF', 'WAVE', 'MP3'].contains(parts.last.toUpperCase())) {
                     filename = parts.sublist(0, parts.length - 1).join(' ');
                  } else {
                     filename = potentialFilenamePart;
                  }
              } else {
                  continue; // Malformed FILE line
              }
          }

        // Check if the file extension indicates a binary data track
        final fileExt = filename.toLowerCase().split('.').last;
        if (['bin', 'img', 'iso'].contains(fileExt)) { // Common extensions for data tracks
           currentFileName = filename; // Store the potential candidate filename
           // Construct the absolute path relative to the CUE file's directory
           final directory = File(cuePath).parent;
           final binPath = '${directory.path}${Platform.pathSeparator}$currentFileName';
           // Check if this file actually exists using statSync for speed
           try {
              final stat = FileStat.statSync(binPath);
              if (stat.type != FileSystemEntityType.notFound) {
                 return binPath; // Return the path of the first valid BIN/IMG/ISO found
              } else {
                 // Log if referenced file doesn't exist, but continue searching
                 debugPrint('Referenced BIN file "$currentFileName" not found at "$binPath".');
              }
           } catch (e) {
              if (e is! FileSystemException || e.osError?.errorCode != 2) {
                  debugPrint("Error checking CUE referenced file path $binPath: $e");
              }
              debugPrint('Referenced BIN file "$currentFileName" not found at "$binPath".');
           }
        }
      }
    }

    // Return null if no suitable and existing BIN/IMG/ISO file was found
    return null;
  }

}