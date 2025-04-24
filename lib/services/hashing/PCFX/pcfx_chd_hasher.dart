import 'dart:async';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart'; // For compute, listEquals, debugPrint

// Assuming chd_read_common.dart is in the correct relative path
import '../CHD/chd_read_common.dart';

// --- Constants ---
const int _programDataSectorSize = 2048;
const List<int> _pcfxIdentifier = [
  80, 67, 45, 70, 88, 58, 72, 117, 95, 67, 68, 45, 82, 79, 77 // "PC-FX:Hu_CD-ROM"
];
const int _identifierOffset = 0;
const int _programInfoSectorIndex = 1;
const int _programInfoSize = 128;
const int _programSectorOffset = 32;
const int _numSectorsOffset = 36;

// Helper function
bool listEquals<T>(List<T>? a, List<T>? b) {
  if (a == null) return b == null;
  if (b == null || a.length != b.length) return false;
  if (identical(a, b)) return true;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

// --- CHD Hashing ---

/// Hashes a CHD file using native FFI implementation via ChdReader.
Future<String?> hashPcfxChdFile(String filePath) async {
  debugPrint('[PcfxChdHasher] Hashing CHD file: $filePath');
  return compute(_hashPcfxChdInIsolate, filePath);
}


/// Isolate function for hashing PC-FX CHD files.
Future<String?> _hashPcfxChdInIsolate(String chdPath) async {
  debugPrint("[PCFX CHD Isolate] Starting process for: $chdPath");
  final chdReader = ChdReader();
  if (!chdReader.isInitialized) {
    debugPrint("[PCFX CHD Isolate] Error: CHD Reader failed to initialize for $chdPath");
    return null;
  }

  try {
    // 1. Process CHD to get header and tracks
    final chdResult = await chdReader.processChdFile(chdPath);
    if (!chdResult.isSuccess || chdResult.tracks.isEmpty) {
      debugPrint("[PCFX CHD Isolate] Error processing CHD or no tracks found: ${chdResult.error}");
      return null;
    }
    debugPrint("[PCFX CHD Isolate]   CHD Header: ${chdResult.header}");
    for (var t in chdResult.tracks) {
      debugPrint("[PCFX CHD Isolate]   Found Track: $t");
    }

    // 2. Find the primary data track
    TrackInfo? dataTrack;
    // Try first MODE1/MODE2 track
    for (final track in chdResult.tracks) {
      if (track.type.contains('MODE1') || track.type.contains('MODE2')) {
        dataTrack = track;
        debugPrint("[PCFX CHD Isolate]   Using Initial Data Track: ${dataTrack.number} (${dataTrack.type})");
        break;
      }
    }
    // Fallback 1: Try track 2
    if (dataTrack == null && chdResult.tracks.length >= 2) {
         final track2 = chdResult.tracks[1];
          if (track2.type.contains('MODE1') || track2.type.contains('MODE2')) {
             dataTrack = track2;
             debugPrint("[PCFX CHD Isolate]   Fallback 1: Using Track 2: ${dataTrack.number} (${dataTrack.type})");
          }
    }
    // Fallback 2: Try largest data track
    if (dataTrack == null) {
         TrackInfo? largestTrack;
         int largestSize = 0;
         for (final track in chdResult.tracks) {
            if (track.type.contains('MODE1') || track.type.contains('MODE2')) {
                if (track.totalFrames > largestSize) {
                    largestSize = track.totalFrames;
                    largestTrack = track;
                }
            }
         }
         if (largestTrack != null) {
             dataTrack = largestTrack;
             debugPrint("[PCFX CHD Isolate]   Fallback 2: Using Largest Data Track: ${dataTrack.number} (${dataTrack.type})");
         }
    }

    if (dataTrack == null) {
         debugPrint("[PCFX CHD Isolate] Error: No suitable MODE1/MODE2 data track found after fallbacks.");
         return null;
    }
    debugPrint("[PCFX CHD Isolate]   Final Data Track Selected: ${dataTrack.number} (${dataTrack.type}) Start: ${dataTrack.startFrame} Pregap: ${dataTrack.pregap} DataOffset: ${dataTrack.dataOffset}");


    // 3. Read sector 0 data
    final sector0Raw = await chdReader.readSector(chdPath, dataTrack, 0);
    if (sector0Raw == null || sector0Raw.length < dataTrack.dataOffset + _pcfxIdentifier.length) {
      debugPrint("[PCFX CHD Isolate] Error: Failed to read sector 0 or data too small (read ${sector0Raw?.length ?? 'null'} bytes, needed offset ${dataTrack.dataOffset} + id length ${_pcfxIdentifier.length}).");
      return null;
    }
    final sector0Data = sector0Raw.sublist(dataTrack.dataOffset);

    // 4. Check for PC-FX identifier
    bool identifierFound = false;
    if (sector0Data.length >= _identifierOffset + _pcfxIdentifier.length) {
       identifierFound = listEquals(
           sector0Data.sublist(_identifierOffset, _identifierOffset + _pcfxIdentifier.length),
           _pcfxIdentifier
       );
    } else {
        debugPrint("[PCFX CHD Isolate]   Sector 0 data after offset (${sector0Data.length} bytes) is too short for identifier check.");
    }

    if (!identifierFound) {
      debugPrint("[PCFX CHD Isolate]   PC-FX identifier not found in Track ${dataTrack.number} Sector 0 data.");
      return null;
    }
    debugPrint("[PCFX CHD Isolate]   PC-FX identifier found in Track ${dataTrack.number} Sector 0.");

    // 5. Read sector 1 data (program info)
    final sector1Raw = await chdReader.readSector(chdPath, dataTrack, _programInfoSectorIndex);
     if (sector1Raw == null || sector1Raw.length < dataTrack.dataOffset + _programInfoSize) {
      debugPrint("[PCFX CHD Isolate] Error: Failed to read sector 1 or data too small (read ${sector1Raw?.length ?? 'null'} bytes, needed offset ${dataTrack.dataOffset} + info size $_programInfoSize).");
      return null;
    }
    final programInfo = sector1Raw.sublist(dataTrack.dataOffset, dataTrack.dataOffset + _programInfoSize);

    // 6. Extract program sector start and number of sectors
    if (programInfo.length < _numSectorsOffset + 3) {
         debugPrint("[PCFX CHD Isolate] Error: Program info data too small for offsets.");
         return null;
    }
    final programSector = programInfo[_programSectorOffset] |
                         (programInfo[_programSectorOffset + 1] << 8) |
                         (programInfo[_programSectorOffset + 2] << 16);
    final numSectors = programInfo[_numSectorsOffset] |
                      (programInfo[_numSectorsOffset + 1] << 8) |
                      (programInfo[_numSectorsOffset + 2] << 16);

    debugPrint('[PCFX CHD Isolate]     Extracted Program Sector Start (Relative): $programSector, Num Sectors: $numSectors');

     if (programSector < 0 || numSectors <= 0 || numSectors > 500000) {
         debugPrint('[PCFX CHD Isolate] Error: Invalid program sector ($programSector) or number of sectors ($numSectors).');
         return null;
     }

    // 7. Accumulate data for hashing
    final List<int> dataToHash = []; // Initialize the list

    // Add the 128 bytes of program info
    dataToHash.addAll(programInfo); // Add program info to the list
    debugPrint('[PCFX CHD Isolate]     Added ${programInfo.length} bytes from sector 1 info to hash list.');

    // Calculate absolute start sector and read program data
    final absoluteProgramStartSector = dataTrack.startFrame + programSector;
    debugPrint('[PCFX CHD Isolate]     Calculated Absolute Program Sector Start: $absoluteProgramStartSector');
    debugPrint('[PCFX CHD Isolate]     Reading $numSectors program sectors (each $_programDataSectorSize bytes)...');

    int sectorsHashed = 0;
    bool readError = false;
    for (int i = 0; i < numSectors; i++) {
      final currentAbsoluteSector = absoluteProgramStartSector + i;
      final relativeSectorToRead = currentAbsoluteSector - dataTrack.startFrame;

      if (relativeSectorToRead < 0 || relativeSectorToRead >= dataTrack.totalFrames) {
        debugPrint('[PCFX CHD Isolate] Error: Calculated relative sector $relativeSectorToRead is out of bounds for Track ${dataTrack.number} (0-${dataTrack.totalFrames - 1}). Absolute sector: $currentAbsoluteSector');
        readError = true;
        break;
      }

      final programSectorRaw = await chdReader.readSector(chdPath, dataTrack, relativeSectorToRead);
      if (programSectorRaw == null) {
        debugPrint('[PCFX CHD Isolate] Error: Failed to read program sector $relativeSectorToRead (absolute $currentAbsoluteSector)');
        readError = true;
        break;
      }

      if (programSectorRaw.length < dataTrack.dataOffset + _programDataSectorSize) {
        debugPrint('[PCFX CHD Isolate] Error: Program sector $relativeSectorToRead data length (${programSectorRaw.length}) is too small for offset ${dataTrack.dataOffset} + $_programDataSectorSize');
        readError = true;
        break;
      }

      final programData = programSectorRaw.sublist(
          dataTrack.dataOffset, dataTrack.dataOffset + _programDataSectorSize);
      
      dataToHash.addAll(programData); // Add program data to the list
      sectorsHashed++;
    }

    if (readError) {
        return null; // Don't compute hash if read failed
    }
    
    debugPrint('[PCFX CHD Isolate]     Successfully read and processed $sectorsHashed program sectors.');
    debugPrint('[PCFX CHD Isolate]     Total bytes accumulated for hashing: ${dataToHash.length}');


    // 8. Compute final hash from the accumulated list
    final digest = md5.convert(dataToHash); // Convert the whole list at once
    final hash = digest.toString();
    debugPrint('[PCFX CHD Isolate]     Generated Hash: $hash');
    debugPrint("[PCFX CHD Isolate] <-- Completed Hashing Successfully");
    return hash;

  } catch (e, stacktrace) {
    debugPrint("[PCFX CHD Isolate] Exception during PCFX CHD hash: $e");
    debugPrint("[PCFX CHD Isolate] Stacktrace: $stacktrace");
    return null;
  } finally {
    debugPrint("[PCFX CHD Isolate] Exiting process for: $chdPath");
  }
}
