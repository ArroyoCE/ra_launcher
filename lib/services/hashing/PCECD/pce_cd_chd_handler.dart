// ignore: library_prefixes
import 'dart:math' as Math;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:retroachievements_organizer/services/hashing/CHD/chd_read_common.dart';


Future<String?> _hashPceCdChdInIsolate(String chdPath) async {
  final chdReader = ChdReader();
  if (!chdReader.isInitialized) {
    return null;
  }

  try {
    final chdResult = await chdReader.processChdFile(chdPath);
    if (!chdResult.isSuccess || chdResult.tracks.isEmpty) {
      return null;
    }

    const marker = "PC Engine CD-ROM SYSTEM";

    TrackInfo? dataTrack;
    for (final track in chdResult.tracks) {
      if (track.type.contains('MODE1') || track.type.contains('MODE2')) {
        dataTrack = track;
        break;
      }
    }
    if (dataTrack == null && chdResult.tracks.isNotEmpty) {
        dataTrack = chdResult.tracks.firstWhere(
            (t) => t.type.contains('MODE1') || t.type.contains('MODE2'),
            orElse: () => chdResult.tracks[0]);
    }
    if (dataTrack == null) {
      return null;
    }

    bool markerFound = false;
    int foundMarkerOffset = -1;
    int foundSectorIndex = -1;
    TrackInfo foundTrack = dataTrack;
    Uint8List? foundDataBuffer;

    const int initialCheckRelativeSector = 1;

    final initialSectorData =
        await chdReader.readSector(chdPath, dataTrack, initialCheckRelativeSector);

    if (initialSectorData != null && initialSectorData.length >= dataTrack.dataOffset) {
      final initialBuffer = initialSectorData.sublist(dataTrack.dataOffset);
      for (int offset = 0; offset <= 40; offset++) {
        if (offset + marker.length <= initialBuffer.length) {
          if (String.fromCharCodes(
                  initialBuffer.sublist(offset, offset + marker.length)) ==
              marker) {
            markerFound = true;
            foundMarkerOffset = offset;
            foundSectorIndex = initialCheckRelativeSector;
            foundTrack = dataTrack;
            foundDataBuffer = initialBuffer;
            break;
          }
        }
      }
    } else {
    }

    if (!markerFound) {
      scanLoop:
      for (int trackIndex = 0; trackIndex < chdResult.tracks.length; trackIndex++) {
        final track = chdResult.tracks[trackIndex];
        if (!track.type.contains('MODE1') && !track.type.contains('MODE2')) continue;
        int sectorsToScan = Math.min(1000, track.totalFrames);

        for (int sectorIndex = 0; sectorIndex < sectorsToScan; sectorIndex++) {
          if (track == dataTrack && sectorIndex == initialCheckRelativeSector && initialSectorData != null) {
            continue;
          }
          final scanSectorData =
              await chdReader.readSector(chdPath, track, sectorIndex);
          if (scanSectorData == null || scanSectorData.length < track.dataOffset) continue;
          final scanDataBuffer = scanSectorData.sublist(track.dataOffset);
          if (scanDataBuffer.length < marker.length) continue;

          for (int offset = 0; offset <= scanDataBuffer.length - marker.length; offset++) {
            if (offset > 64) break;
            if (String.fromCharCodes(
                    scanDataBuffer.sublist(offset, offset + marker.length)) ==
                marker) {
              markerFound = true;
              foundMarkerOffset = offset;
              foundSectorIndex = sectorIndex;
              foundTrack = track;
              foundDataBuffer = scanDataBuffer;
              break scanLoop;
            }
          }
        }
      }
    }

    if (markerFound && foundDataBuffer != null) {

      int titleOffset = 106;
      if (foundMarkerOffset != 32 && foundMarkerOffset >= 0) {
         titleOffset = foundMarkerOffset + marker.length + (106 - (32 + marker.length));
      }
      if (titleOffset < 0) titleOffset = 0;
      if (titleOffset + 22 > foundDataBuffer.length) {
          titleOffset = foundDataBuffer.length - 22;
          if (titleOffset < 0) { return null; }
      }
      final titleBytes = foundDataBuffer.sublist(titleOffset, titleOffset + 22);


      if (foundDataBuffer.length < 4) {
          return null;
      }
      final programSector = (foundDataBuffer[0] << 16) + (foundDataBuffer[1] << 8) + foundDataBuffer[2];
      final numSectors = foundDataBuffer[3];


      int firstDataSectorBase;
      if (foundTrack == dataTrack && foundSectorIndex == initialCheckRelativeSector) {
          firstDataSectorBase = foundTrack.startFrame;
      } else {
          firstDataSectorBase = foundTrack.startFrame + foundTrack.pregap;
      }

      int absoluteProgramSector = firstDataSectorBase + programSector;

      final dataToHash = <int>[];
      dataToHash.addAll(titleBytes);

      for (int i = 0; i < numSectors; i++) {
        final currentAbsoluteSector = absoluteProgramSector + i;
        final sectorToRead = currentAbsoluteSector - foundTrack.startFrame;

        if (sectorToRead < 0 || sectorToRead >= foundTrack.totalFrames) {
          return null;
        }

        final programSectorData =
            await chdReader.readSector(chdPath, foundTrack, sectorToRead);
        if (programSectorData == null) {
          return null;
        }
        if (programSectorData.length < foundTrack.dataOffset + 2048) {
          return null;
        }

        final programData = programSectorData.sublist(
            foundTrack.dataOffset, foundTrack.dataOffset + 2048);
        dataToHash.addAll(programData);
      }

      if (dataToHash.length <= titleBytes.length) {
        return null;
      }
      final digest = md5.convert(dataToHash);
      final hash = digest.toString();
      return hash;

    } else {
      return null;
    }
  } catch (e) {
    return null;
  } finally {
    // If ChdReader needs cleanup (e.g., chdReader.dispose()), add it here.
  }
}




/// Handles CHD files for PC Engine CD games
class PCECDChdHandler {
  final ChdReader _chdReader;

  PCECDChdHandler(this._chdReader);

  /// Hash a PC Engine CD from a CHD file using a background isolate.
  Future<String?> hashPCECDFromChd(String chdPath) async {
    if (!_chdReader.isInitialized) {
       return null;
    }
    return compute(_hashPceCdChdInIsolate, chdPath);
  }


  Future<Map<String, dynamic>> extractCueInfoFromChd(
      String chdPath, ChdProcessResult chdResult) async {
      int indexOffset = 0;
      String trackType = 'MODE1/2352';
      int dataOffset = 16;
      int sectorSize = 2352;

      TrackInfo? dataTrack;
      for (final track in chdResult.tracks) {
        if (track.type.contains('MODE1') || track.type.contains('MODE2')) {
          dataTrack = track;
          break;
        }
      }

      if (dataTrack == null && chdResult.tracks.isNotEmpty) {
         dataTrack = chdResult.tracks.firstWhere(
            (t) => t.type.contains('MODE1') || t.type.contains('MODE2'),
            orElse: () => chdResult.tracks[0]);
      }

      if (dataTrack != null) {
        trackType = dataTrack.type;
        indexOffset = dataTrack.startFrame;
        dataOffset = dataTrack.dataOffset;
        sectorSize = dataTrack.sectorSize;
      }

      return {
        'trackType': trackType,
        'indexOffset': indexOffset,
        'dataOffset': dataOffset,
        'sectorSize': sectorSize
      };
  }


  /// Debug a CHD file to help diagnose issues.
  Future<void> debugChdFile(String chdPath) async {
     // Consider running this in an isolate if it causes UI freezes
     // using compute and a dedicated top-level function.
     await _performDebugChdFile(chdPath);
  }

  Future<void> _performDebugChdFile(String chdPath) async {
      if (!_chdReader.isInitialized) {
        return;
      }

      try {
        final chdResult = await _chdReader.processChdFile(chdPath);
        if (!chdResult.isSuccess) {
          return;
        }
        

        for (final track in chdResult.tracks) {
          for (int i = 0; i < Math.min(5, track.totalFrames); i++) {
            final sectorData = await _chdReader.readSector(chdPath, track, i);
            if (sectorData != null) {
               // Original debug checks can go here:
                if (track.type.contains('MODE1') || track.type.contains('MODE2')) {
                  final isoData = sectorData.sublist(track.dataOffset);
                  if (isoData.length > 6 && String.fromCharCodes(isoData.sublist(1, 6)) == 'CD001') {
                  }
                  final dataString = String.fromCharCodes(isoData.where((b) => b >= 32 && b <= 126));
                  if (dataString.contains('PC Engine')) {
                  }
               }
            } else {
            }
          }
        }
      } finally {
      }
  }

} 