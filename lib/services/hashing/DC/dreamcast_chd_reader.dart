// lib/services/hashing/DC/dreamcast_chd_reader.dart
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
// Ensure these paths are correct for your project structure
import 'package:retroachievements_organizer/services/hashing/CHD/chd_read_common.dart';
import 'package:retroachievements_organizer/services/hashing/DC/dreamcast_hash_utils.dart';
import 'package:retroachievements_organizer/services/hashing/DC/iso_parser.dart'; // Import the ISO parser

/// Implementation of SectorReader specific to CHD files.
/// It reads raw sectors from the CHD using the underlying ChdReader
/// and attempts to extract the 2048-byte logical sector data expected by the IsoParser.
class ChdSectorReader implements SectorReader {
  final ChdReader chdReader;
  final String filePath;
  final TrackInfo trackInfo;
  final int logicalSectorSize = 2048; // ISO standard logical sector size

  ChdSectorReader(this.chdReader, this.filePath, this.trackInfo);

  /// Reads a single logical sector (2048 bytes) from the CHD track.
  /// Handles extracting the logical data from various raw sector formats.
  @override
Future<Uint8List?> readSector(int logicalSectorNumber) async {
  // CHD sector numbers are relative to the start of the track's logical data.
  final rawSectorData = await chdReader.readSector(filePath, trackInfo, logicalSectorNumber);

  if (rawSectorData == null) {
    return null;
  }

  // Determine the offset of the 2048-byte user data within the raw sector
  int dataOffset = 0;
  
  // Try multiple offsets for finding data (this is critical for Dreamcast discs)
  if (trackInfo.sectorSize == 2352) {
    // Try multiple common data offsets for 2352-byte sectors
    final possibleOffsets = [16, 24, 0];
    
    for (final offset in possibleOffsets) {
      // Check for SEGA SEGAKATANA marker at this offset (for IP.BIN)
      if (logicalSectorNumber == 0 && 
          offset + 16 <= rawSectorData.length && 
          _checkForSegaMarker(rawSectorData, offset)) {
        dataOffset = offset;
        debugPrint('Found SEGA marker at offset $offset in sector 0');
        break;
      }
      
      // Check for CD001 marker (for ISO filesystem)
      if (offset + 5 <= rawSectorData.length && 
          rawSectorData[offset + 1] == 0x43 && 
          rawSectorData[offset + 2] == 0x44 && 
          rawSectorData[offset + 3] == 0x30 && 
          rawSectorData[offset + 4] == 0x30 && 
          rawSectorData[offset + 5] == 0x31) {
        dataOffset = offset;
        debugPrint('Found CD001 marker at offset $offset in sector $logicalSectorNumber');
        break;
      }
    }
    
    // If no markers found, use the most common default
    if (dataOffset == 0) {
      dataOffset = 16;
      
    }
  } else if (trackInfo.sectorSize == 2048) {
    dataOffset = 0;
  } else if (trackInfo.sectorSize == 2336) {
    dataOffset = 0;
  }

  // Ensure we have enough data in the raw sector to extract a logical sector
  if (dataOffset + logicalSectorSize > rawSectorData.length) {
    debugPrint('Raw sector $logicalSectorNumber data too small for offset $dataOffset');
    if (rawSectorData.length > dataOffset) {
      return rawSectorData.sublist(dataOffset);
    }
    return null;
  }

  try {
    return rawSectorData.sublist(dataOffset, dataOffset + logicalSectorSize);
  } catch (e) {
    debugPrint('Error sublisting raw sector $logicalSectorNumber: $e');
    return null;
  }
}

// Helper to check for SEGA SEGAKATANA marker
bool _checkForSegaMarker(Uint8List data, int offset) {
  if (offset + 16 > data.length) return false;
  
  const String marker = 'SEGA SEGAKATANA ';
  final markerBytes = utf8.encode(marker);
  
  for (int i = 0; i < 16; i++) {
    if (data[offset + i] != markerBytes[i]) return false;
  }
  
  return true;
}


  /// Reads multiple consecutive logical sectors (2048 bytes each).
  @override
  Future<Uint8List?> readSectors(int startLogicalSector, int count) async {
     if (count <= 0) return Uint8List(0);
      final buffer = BytesBuilder(copy: false);
      int totalBytesRead = 0;
      for (int i = 0; i < count; i++) {
         final sectorData = await readSector(startLogicalSector + i);
         if (sectorData != null && sectorData.isNotEmpty) {
            buffer.add(sectorData);
            totalBytesRead += sectorData.length;
            // If a partial sector was read, it indicates the end of the track data
            if (sectorData.length < logicalSectorSize) break;
         } else {
            // Error reading sector or reached end of track prematurely
            // debugPrint('ChdSectorReader: Stopping readSectors at sector ${startLogicalSector + i}');
            break;
         }
      }
      if (totalBytesRead > 0) {
        return buffer.toBytes();
      }
      // debugPrint('ChdSectorReader: readSectors failed to read any data for $count sectors from $startLogicalSector');
      return null; // Return null if nothing could be read
  }

  /// Reads a specific range of bytes relative to the logical data stream.
  /// This implementation reads logical sectors and pieces the result together.
  @override
  Future<Uint8List?> readBytes(int startLogicalSector, int offsetInLogicalSector, int length) async {
     if (length <= 0) return Uint8List(0);

     final buffer = BytesBuilder(copy: false);
     int bytesReadCount = 0; // Track how many bytes we've actually added
     int currentLogicalSector = startLogicalSector;
     // Calculate how many bytes to skip in the first sector we read
     int bytesToSkipInCurrentSector = offsetInLogicalSector;

     while(bytesReadCount < length) {
       final sectorData = await readSector(currentLogicalSector);
       if (sectorData == null || sectorData.isEmpty) {
          debugPrint('CHD Read Error: Failed to read logical sector $currentLogicalSector during readBytes. Read $bytesReadCount/$length bytes.');
          break; // Stop if we can't read a sector
       }

       // Ensure skip amount is not out of bounds for this sector
       if (bytesToSkipInCurrentSector >= sectorData.length) {
           // The skip amount is greater than or equal to the sector size.
           // Adjust the skip amount for the next sector and continue.
           bytesToSkipInCurrentSector -= sectorData.length;
           currentLogicalSector++;
           continue;
       }

       // Calculate how many bytes are actually available to read in this sector after skipping
       final bytesAvailableInSector = sectorData.length - bytesToSkipInCurrentSector;

       // Determine how many bytes to copy from the current sector's available data
       final remainingNeeded = length - bytesReadCount;
       final bytesToCopy = (remainingNeeded < bytesAvailableInSector)
                                 ? remainingNeeded // Copy remaining needed bytes
                                 : bytesAvailableInSector; // Copy all available after skip

       // Add the relevant portion of the sector data to the buffer
       buffer.add(sectorData.sublist(bytesToSkipInCurrentSector, bytesToSkipInCurrentSector + bytesToCopy));
       bytesReadCount += bytesToCopy; // Update count of bytes read

       // For subsequent sectors, we start reading from the beginning (no skip)
       bytesToSkipInCurrentSector = 0;
       currentLogicalSector++; // Move to the next logical sector

       // If the last sector read was partial, we've likely hit the end of the track data
       if (sectorData.length < logicalSectorSize) {
           if (bytesReadCount < length) {
             debugPrint('CHD Read Warning: Reached end of track data reading sector $currentLogicalSector, but only got $bytesReadCount/$length bytes.');
           }
           break;
       }
     }

     final result = buffer.toBytes();
      // Verify if the expected number of bytes were read
      if (result.length != length) {
         debugPrint('CHD Read Warning: Tried to read $length bytes, but actually got ${result.length} bytes starting at $startLogicalSector:$offsetInLogicalSector.');
      }
      return result;
  }


  @override
  Future<void> close() async {
    // The ChdReader instance is likely managed externally, so no action needed here.
    return Future.value();
  }
}

/// Processes Dreamcast CHD files to generate a hash.
class DreamcastChdReader {

  /// Processes the given CHD file path to calculate the Dreamcast hash.
   Future<String?> processFile(String path) async {
    ChdReader? chdReader;
    SectorReader? sectorReader;

    try {
      // Initialize the CHD reader library/wrapper
      chdReader = ChdReader(); // Assuming constructor handles initialization
      if (!chdReader.isInitialized) {
        debugPrint('CHD library not initialized for Dreamcast hashing');
        return null;
      }

      // Process the CHD file to get header info and track list
      final result = await chdReader.processChdFile(path);
      if (!result.isSuccess || result.tracks.isEmpty) {
        debugPrint('Error processing CHD file or no tracks found: ${result.error}');
        return null;
      }

      // Find the primary data track (usually track 3 for GD-ROM format)
      TrackInfo? dataTrack;
      try {
        // Prioritize track 3 as it's standard for GD-ROM data
        dataTrack = result.tracks.firstWhere((track) => track.number == 3);
         debugPrint('Found potential GD-ROM data track 3.');
      } catch (e) {
         // Fallback if track 3 isn't present (e.g., MIL-CD in CHD?)
         debugPrint('Track 3 not found, searching for first MODE1/MODE2 or first track.');
        dataTrack = result.tracks.firstWhere(
          (track) => track.type.contains('MODE1') || track.type.contains('MODE2'), // Look for standard data modes
          orElse: () => result.tracks.first); // Default to the very first track if no data track found
      }
       debugPrint('Using track ${dataTrack.number} (Type: ${dataTrack.type}, Raw Sector Size: ${dataTrack.sectorSize}) for hashing.');

      // Create the specialized sector reader for this CHD track
      sectorReader = ChdSectorReader(chdReader, path, dataTrack);

      // Attempt to read the *logical* sector 0 of the data track to find IP.BIN
      // It might be in sector 0 or 1 relative to the logical start.
      Uint8List? ipBinData;
      Uint8List? logicalSector0Data = await sectorReader.readSector(0);
      if (logicalSector0Data != null && logicalSector0Data.length >= DreamcastHashUtils.IP_BIN_SIZE && DreamcastHashUtils.validateSegaSegakatana(logicalSector0Data)) {
         ipBinData = logicalSector0Data.sublist(0, DreamcastHashUtils.IP_BIN_SIZE);
         debugPrint('Found SEGA SEGAKATANA marker and extracted IP.BIN from logical sector 0.');
      } else {
         // As a fallback, check logical sector 1 (less common, but possible)
         final logicalSector1Data = await sectorReader.readSector(1);
          if (logicalSector1Data != null && logicalSector1Data.length >= DreamcastHashUtils.IP_BIN_SIZE && DreamcastHashUtils.validateSegaSegakatana(logicalSector1Data)) {
             ipBinData = logicalSector1Data.sublist(0, DreamcastHashUtils.IP_BIN_SIZE);
             debugPrint('Found SEGA SEGAKATANA marker and extracted IP.BIN from logical sector 1.');
          } else {
             // If not found in sector 0 or 1, assume it's not a valid Dreamcast image
             debugPrint('Not a valid Dreamcast CHD: no SEGA SEGAKATANA marker found in logical sector 0 or 1 of track ${dataTrack.number}.');
             // Try reading sector 0 again just in case readSector failed initially but might work now? (Unlikely)
             logicalSector0Data ??= await sectorReader.readSector(0);
             debugPrint('Logical Sector 0 (${logicalSector0Data?.length ?? 'null'} bytes): ${logicalSector0Data?.sublist(0, min(32, logicalSector0Data.length)).map((b) => b.toRadixString(16).padLeft(2,'0')).join(' ')}');
             return null;
          }
      }

      // --- MODIFIED PART START ---
      // Extract the boot file name BYTES from the located IP.BIN data
      final bootFileNameBytes = DreamcastHashUtils.extractBootFileNameBytes(ipBinData); // Get bytes
      if (bootFileNameBytes == null || bootFileNameBytes.isEmpty) {
        debugPrint('Boot executable not specified or extraction failed in IP.BIN');
        // The C reference code errors out here, so we do the same.
        return null;
      }
      // Prepare filename STRING for ISO lookup (uppercase, no version)
      // Still need the string version for lookup
      String isoBootFileName;
      String bootFileNameForDisplay;
      try {
         // Use allowInvalid: true for robustness, though IP.BIN should be ASCII
         bootFileNameForDisplay = ascii.decode(bootFileNameBytes, allowInvalid: true);
         isoBootFileName = bootFileNameForDisplay.toUpperCase().split(';').first;
      } catch(e) {
         debugPrint("Error decoding boot filename bytes: $e. Cannot proceed.");
         return null;
      }
      debugPrint('Found boot file name in IP.BIN: $bootFileNameForDisplay (Using: $isoBootFileName for lookup)');
      // --- MODIFIED PART END ---

      // --- Find and Read Actual Boot File Content using IsoParser ---
      Uint8List? actualBootFileContent;
      // Use the IsoParser with our ChdSectorReader to navigate the filesystem
      final bootFileInfo = await IsoParser.findFileInIso(sectorReader, isoBootFileName);

      if (bootFileInfo != null) {
        // If the file is found in the directory structure
        debugPrint('Located boot file "$isoBootFileName" via ISO parser: Logical Sector=${bootFileInfo.sector}, Size=${bootFileInfo.size}');
        // Read the actual content of the boot file
        actualBootFileContent = await IsoParser.readFileContent(sectorReader, bootFileInfo);
        if (actualBootFileContent == null) {
           // Handle case where reading the file content failed
           debugPrint('Failed to read content for boot file "$isoBootFileName".');
           return null; // Error out
        }
         debugPrint('Successfully read ${actualBootFileContent.length} bytes for boot file.');
      } else {
        // If the file specified in IP.BIN couldn't be found in the ISO filesystem
        debugPrint('Could not locate boot file "$isoBootFileName" using ISO parser in CHD track.');
        // The C reference code errors out if the boot file isn't found.
        return null;
      }
      // --- End Boot File Reading ---

      // --- MODIFIED PART START ---
      // Calculate the final hash using IP.BIN, RAW boot filename bytes, and actual boot file content
      final hash = DreamcastHashUtils.calculateDreamcastHash(
          ipBinData,
          bootFileNameBytes, // Pass the raw bytes here
          actualBootFileContent);
      // --- MODIFIED PART END ---

      if (hash == null) {
          debugPrint('Hash calculation returned null.');
          return null;
      }

      debugPrint('Generated Dreamcast hash for CHD: $hash');
      return hash; // Return the calculated hash

    } catch (e, s) {
      // Catch-all for unexpected errors during processing
      debugPrint('Error processing Dreamcast CHD file $path: $e\n$s');
      return null;
    } finally {
       // Ensure the sector reader resources are cleaned up (if any)
       // In this case, ChdSectorReader doesn't hold closable resources itself.
       await sectorReader?.close(); // Calls the (currently empty) close method
       // Consider if chdReader needs explicit disposal if it holds native resources
       // chdReader?.dispose(); // Uncomment if your ChdReader requires disposal
    }
  }
}


