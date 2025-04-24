import 'dart:async'; 
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart'; // For listEquals and debugPrint
import 'package:path/path.dart' as path;

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


// --- CUE/BIN Hashing ---

/// Hashes a CUE file by finding and processing the associated BIN file.
Future<String?> hashPcfxCueFile(String cuePath) async {
  debugPrint('[PcfxBinHasher] Processing CUE file: $cuePath');
  try {
    final cueFile = File(cuePath);
    if (!await cueFile.exists()) {
      debugPrint('[PcfxBinHasher] CUE file not found: $cuePath');
      return null;
    }

    // Basic CUE parsing
    final cueContent = await cueFile.readAsString();
    final fileRegExp = RegExp(r'FILE\s+"?([^"]+)"?\s+BINARY', caseSensitive: false);
    final trackRegExp = RegExp(r'TRACK\s+(\d+)\s+(\w+)(?:\/(\d+))?', caseSensitive: false);

    String? binFileName;
    int sectorSize = 2352; // Default assumption
    int dataOffset = 16;   // Default assumption for MODE1/2352
    bool formatSet = false;

    final lines = cueContent.split('\n');

    // Find the first BIN file
    for (final line in lines) {
        final fileMatch = fileRegExp.firstMatch(line.trim());
        if (fileMatch != null && fileMatch.group(1) != null) {
            binFileName = fileMatch.group(1)!;
            debugPrint('[PcfxBinHasher]   Found FILE directive: $binFileName');
            break;
        }
    }

    if (binFileName == null) {
      debugPrint('[PcfxBinHasher] Could not find valid FILE "..." BINARY statement in CUE.');
      return null;
    }

    // Find the format of the track associated with the first BIN file
    bool trackFoundForFile = false;
    for (final line in lines) {
        final trimmedLine = line.trim();
        // Check if the line contains the bin filename using contains for flexibility
        if (fileRegExp.firstMatch(trimmedLine)?.group(1) == binFileName) {
             trackFoundForFile = true;
             continue;
        }

        if (trackFoundForFile) {
            final trackMatch = trackRegExp.firstMatch(trimmedLine);
            if (trackMatch != null) {
                final trackType = trackMatch.group(2)?.toUpperCase();
                final trackSubType = trackMatch.group(3);

                if (trackType == 'MODE1') {
                    if (trackSubType == '2048') {
                        sectorSize = 2048; dataOffset = 0;
                        debugPrint('[PcfxBinHasher]   Detected MODE1/2048 for $binFileName.');
                    } else {
                        sectorSize = 2352; dataOffset = 16;
                        debugPrint('[PcfxBinHasher]   Detected MODE1/2352 for $binFileName.');
                    }
                } else if (trackType == 'MODE2') {
                    sectorSize = 2352; dataOffset = 16;
                    debugPrint('[PcfxBinHasher]   Detected MODE2 for $binFileName, using $sectorSize/$dataOffset.');
                } else {
                    sectorSize = 2352; dataOffset = 0;
                    debugPrint('[PcfxBinHasher]   Detected $trackType for $binFileName, using $sectorSize/$dataOffset.');
                }
                formatSet = true;
                break;
            }
            // Stop if we hit another FILE line
            if (fileRegExp.firstMatch(trimmedLine) != null && trimmedLine.contains(binFileName) == false) {
                 debugPrint('[PcfxBinHasher]   Found another FILE before a TRACK for $binFileName. Using defaults.');
                 break;
            }
        }
    }

     if (!formatSet) {
         debugPrint('[PcfxBinHasher]   Could not determine track format from CUE for $binFileName. Using defaults $sectorSize/$dataOffset.');
    }

    // Construct full BIN path
    final cueDir = path.dirname(cuePath);
    final binPath = path.isAbsolute(binFileName) ? binFileName : path.join(cueDir, binFileName);

    if (!await File(binPath).exists()) {
      debugPrint('[PcfxBinHasher] BIN file specified in CUE not found: $binPath');
      // Try case variations
      final binPathLower = path.join(cueDir, binFileName.toLowerCase());
      if (await File(binPathLower).exists()) {
         debugPrint('[PcfxBinHasher] Found BIN file with different case: $binPathLower');
         return await hashPcfxBinFile(binPathLower, sectorSize, dataOffset);
      }
      final binPathUpper = path.join(cueDir, binFileName.toUpperCase());
       if (await File(binPathUpper).exists()) {
         debugPrint('[PcfxBinHasher] Found BIN file with different case: $binPathUpper');
         return await hashPcfxBinFile(binPathUpper, sectorSize, dataOffset);
      }
      return null;
    }

    debugPrint('[PcfxBinHasher] Found BIN file: $binPath (Format: SectorSize=$sectorSize, DataOffset=$dataOffset)');
    return await hashPcfxBinFile(binPath, sectorSize, dataOffset);

  } catch (e) {
    debugPrint('[PcfxBinHasher] Error processing CUE file $cuePath: $e');
    return null;
  }
}


/// Hashes a BIN/IMG/ISO file directly.
Future<String?> hashPcfxBinFile(String filePath, int sectorSize, int dataOffset) async {
  debugPrint('[PcfxBinHasher] Processing BIN file: $filePath (SectorSize: $sectorSize, DataOffset: $dataOffset)');
  RandomAccessFile? randomAccessFile;
  try {
    final file = File(filePath);
    if (!await file.exists()) {
      debugPrint('[PcfxBinHasher] BIN file does not exist: $filePath');
      return null;
    }

    randomAccessFile = await file.open(mode: FileMode.read);
    final fileSize = await randomAccessFile.length();
    debugPrint('[PcfxBinHasher]   File size: $fileSize bytes');

    // 1. Read sector 0 data
    final sector0Buffer = Uint8List(sectorSize);
    await randomAccessFile.setPosition(0);
    final bytesRead0 = await randomAccessFile.readInto(sector0Buffer);

    if (bytesRead0 < dataOffset + _pcfxIdentifier.length) {
      debugPrint('[PcfxBinHasher] Error: Failed to read enough data from sector 0 ($bytesRead0 bytes read). Needed ${dataOffset + _pcfxIdentifier.length}.');
      return null;
    }
    final sector0Data = sector0Buffer.sublist(dataOffset);

    // 2. Check for PC-FX identifier
     bool identifierFound = false;
     if (sector0Data.length >= _identifierOffset + _pcfxIdentifier.length) {
        identifierFound = listEquals(
            sector0Data.sublist(_identifierOffset, _identifierOffset + _pcfxIdentifier.length),
            _pcfxIdentifier
        );
     } else {
         debugPrint('[PcfxBinHasher]   Sector 0 data after offset (${sector0Data.length} bytes) is too short for identifier check (needs ${_identifierOffset + _pcfxIdentifier.length} bytes).');
     }

    if (!identifierFound) {
      debugPrint('[PcfxBinHasher]   PC-FX identifier not found in sector 0 data (offset $dataOffset).');
      return null;
    }
    debugPrint('[PcfxBinHasher]   PC-FX identifier found in sector 0.');

    // 3. Read sector 1 data (program info)
    final sector1Position = _programInfoSectorIndex * sectorSize;
    if (fileSize < sector1Position + dataOffset + _programInfoSize) {
       debugPrint('[PcfxBinHasher] Error: File too small to contain sector 1 data (needs ${sector1Position + dataOffset + _programInfoSize} bytes, file size $fileSize).');
       return null;
    }
    final sector1Buffer = Uint8List(sectorSize);
    await randomAccessFile.setPosition(sector1Position);
    final bytesRead1 = await randomAccessFile.readInto(sector1Buffer);

    if (bytesRead1 < dataOffset + _programInfoSize) {
      debugPrint('[PcfxBinHasher] Error: Failed to read enough data from sector 1 ($bytesRead1 bytes read). Needed ${dataOffset + _programInfoSize}.');
      return null;
    }
    final programInfo = sector1Buffer.sublist(dataOffset, dataOffset + _programInfoSize);

    // 4. Extract program sector start and number of sectors
     if (programInfo.length < _numSectorsOffset + 3) {
          debugPrint("[PcfxBinHasher] Error: Program info data too small for offsets.");
          return null;
     }
     final programSector = programInfo[_programSectorOffset] |
                          (programInfo[_programSectorOffset + 1] << 8) |
                          (programInfo[_programSectorOffset + 2] << 16);
     final numSectors = programInfo[_numSectorsOffset] |
                       (programInfo[_numSectorsOffset + 1] << 8) |
                       (programInfo[_numSectorsOffset + 2] << 16);

    debugPrint('[PcfxBinHasher]     Extracted Program Sector Start (Relative): $programSector, Num Sectors: $numSectors');

      if (programSector < 0 || numSectors <= 0 || numSectors > 500000) {
          debugPrint('[PcfxBinHasher] Error: Invalid program sector ($programSector) or number of sectors ($numSectors).');
          return null;
      }

    // 5. Accumulate data for hashing
    final List<int> dataToHash = [];

    // Add the 128 bytes of program info
    dataToHash.addAll(programInfo);
    debugPrint('[PcfxBinHasher]     Added ${programInfo.length} bytes from sector 1 info to hash list.');

    // Calculate start position and read program data sectors
    final programDataStartPosition = programSector * sectorSize;
    debugPrint('[PcfxBinHasher]     Calculated Program Data Start Position: $programDataStartPosition');
    debugPrint('[PcfxBinHasher]     Reading $numSectors program sectors (each $_programDataSectorSize bytes)...');

    final programSectorBuffer = Uint8List(sectorSize);
    int sectorsHashed = 0;
    bool readError = false;
    for (int i = 0; i < numSectors; i++) {
      final currentSectorPosition = programDataStartPosition + (i * sectorSize);

      if (fileSize < currentSectorPosition + dataOffset + _programDataSectorSize) {
         debugPrint('[PcfxBinHasher] Error: File ended unexpectedly while trying to read program sector ${programSector + i} (at byte $currentSectorPosition). File size $fileSize, needed ${currentSectorPosition + dataOffset + _programDataSectorSize}. Read $sectorsHashed/$numSectors sectors.');
         readError = true;
         break;
      }

      await randomAccessFile.setPosition(currentSectorPosition);
      final bytesReadProg = await randomAccessFile.readInto(programSectorBuffer);

      if (bytesReadProg < sectorSize) {
         debugPrint('[PcfxBinHasher] Warning: Read fewer bytes ($bytesReadProg) than expected sector size ($sectorSize) for program sector ${programSector + i}. File might be truncated.');
         if (bytesReadProg < dataOffset + _programDataSectorSize) {
             debugPrint('[PcfxBinHasher] Error: Could not read full data portion for program sector ${programSector + i}. Needed ${dataOffset + _programDataSectorSize} bytes from start of sector, only read $bytesReadProg total.');
             readError = true;
             break;
         }
      }

      final programData = programSectorBuffer.sublist(
          dataOffset, dataOffset + _programDataSectorSize);
      dataToHash.addAll(programData); // Add data to the list
      sectorsHashed++;
    }

    if (readError) {
        return null; // Return null if there was an error reading sectors
    }

    debugPrint('[PcfxBinHasher]     Successfully read and processed $sectorsHashed program sectors.');
    debugPrint('[PcfxBinHasher]     Total bytes accumulated for hashing: ${dataToHash.length}');


    // 6. Compute final hash from the accumulated list
    final digest = md5.convert(dataToHash);
    final hash = digest.toString();
    debugPrint('[PcfxBinHasher]     Generated Hash: $hash');
    return hash;

  } catch (e, stack) {
    debugPrint('[PcfxBinHasher] Error hashing BIN file $filePath: $e');
    debugPrint('Stack trace: $stack');
    return null;
  } finally {
    await randomAccessFile?.close();
  }
}
