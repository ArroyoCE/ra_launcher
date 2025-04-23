// ignore: library_prefixes
import 'dart:math' as Math;

import 'package:crypto/crypto.dart';
import 'package:retroachievements_organizer/services/hashing/CHD/chd_read_common.dart';

/// Handles CHD files for PC Engine CD games
class PCECDChdHandler {
  final ChdReader _chdReader;
  
  PCECDChdHandler(this._chdReader);




// Add this method to the PCECDChdHandler class
Future<Map<String, dynamic>> extractCueInfoFromChd(String chdPath, ChdProcessResult chdResult) async {
  // Default values
  int indexOffset = 0;
  String trackType = 'MODE1/2352';
  int dataOffset = 16;
  int sectorSize = 2352;
  
  // Find the first data track (MODE1 or MODE2)
  TrackInfo? dataTrack;
  for (final track in chdResult.tracks) {
    if (track.type.contains('MODE1') || track.type.contains('MODE2')) {
      dataTrack = track;
      break;
    }
  }
  
  if (dataTrack == null && chdResult.tracks.isNotEmpty) {
    // No data track found, use the first track as fallback
    dataTrack = chdResult.tracks[0];
  }
  
  if (dataTrack != null) {
    // Determine values based on track info
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




  /// Hash a PC Engine CD from a CHD file
Future<String?> hashPCECDFromChd(String chdPath) async {
  if (!_chdReader.isInitialized) {
    return null;
  }
  
  try {
    // Process the CHD file to get track information
    final chdResult = await _chdReader.processChdFile(chdPath);
    
    if (!chdResult.isSuccess) {
      return null;
    }
    
    
    // Extract cue-like information from CHD
    
    // The marker we're looking for
    const marker = "PC Engine CD-ROM SYSTEM";
    
    // Calculate the sector to check based on index offset (same as cue implementation)
// Just like in the cue implementation
    
    // Find the appropriate track for reading
    TrackInfo? dataTrack;
    for (final track in chdResult.tracks) {
      if (track.type.contains('MODE1') || track.type.contains('MODE2')) {
        dataTrack = track;
        break;
      }
    }
    
    if (dataTrack == null && chdResult.tracks.isNotEmpty) {
      dataTrack = chdResult.tracks[0];
    }
    
    if (dataTrack == null) {
      return null;
    }
    
    // Read the sector to check for PC Engine marker
    final sectorData = await _chdReader.readSector(
      chdPath, 
      dataTrack, 
      1 // Always check sector 1 relative to track start, like in cue implementation
    );
    
    if (sectorData == null) {
      return null;
    }
    
    final dataBuffer = sectorData.sublist(dataTrack.dataOffset);
    
    dataBuffer.sublist(0, Math.min(100, dataBuffer.length));
    
    // Check for marker
    bool isPCECD = false;
    int markerPos = -1;
    
    // Do a flexible search for the marker
    for (int offset = 0; offset <= 40; offset++) {
      if (offset + marker.length <= dataBuffer.length) {
        if (String.fromCharCodes(dataBuffer.sublist(offset, offset + marker.length)) == marker) {
          isPCECD = true;
          markerPos = offset;
          break;
        }
      }
    }
    
    // If not found in sector 1, do comprehensive scan as backup
    if (!isPCECD) {
      
      for (int trackIndex = 0; trackIndex < chdResult.tracks.length; trackIndex++) {
        final track = chdResult.tracks[trackIndex];
        if (!track.type.contains('MODE1') && !track.type.contains('MODE2')) continue;
        
        
        int sectorsToScan = Math.min(1000, track.totalFrames);
        
        for (int sectorIndex = 0; sectorIndex < sectorsToScan; sectorIndex++) {
          if (sectorIndex % 100 == 0) {
          }
          
          final sectorData = await _chdReader.readSector(chdPath, track, sectorIndex);
          if (sectorData == null) continue;
          
          final dataBuffer = sectorData.sublist(track.dataOffset);
          
          if (dataBuffer.length < marker.length) continue;
          
          for (int offset = 0; offset <= dataBuffer.length - marker.length; offset++) {
            if (String.fromCharCodes(dataBuffer.sublist(offset, offset + marker.length)) == marker) {
              isPCECD = true;
              markerPos = offset;
              dataTrack = track;
              
              // Return to the original implementation for consistent hashing
              return hashPCECDFromFoundMarker(chdPath, dataTrack, sectorIndex, markerPos, dataBuffer);
            }
          }
        }
      }
    }
    
    if (isPCECD) {
      return hashPCECDFromFoundMarker(chdPath, dataTrack!, 1, markerPos, dataBuffer);
    }
    
    return null;
  } catch (e) {
    return null;
  }
}


// New helper method that handles hashing when marker is found
// This follows the bin implementation more closely
Future<String?> hashPCECDFromFoundMarker(
    String chdPath, TrackInfo track, int sectorIndex, int markerOffset, List<int> dataBuffer) async {
  try {
    // Extract title from the marker sector
    int titleOffset = 106;
    
    if (markerOffset != 32 && markerOffset > 0) {
      titleOffset = markerOffset + "PC Engine CD-ROM SYSTEM".length + (106 - (32 + "PC Engine CD-ROM SYSTEM".length));
    }
    
    if (titleOffset + 22 > dataBuffer.length) {
      titleOffset = dataBuffer.length - 22;
    }
    
    final titleBytes = dataBuffer.sublist(titleOffset, titleOffset + 22);
    String.fromCharCodes(titleBytes.where((b) => b >= 32 && b <= 126)).trim();
    
    // Get program sector and size from the marker sector
    final programSector = (dataBuffer[0] << 16) + 
                        (dataBuffer[1] << 8) + 
                        dataBuffer[2];
    final numSectors = dataBuffer[3];
    
    
    final firstTrackSector = track.startFrame;
    
    // CRITICAL DECISION: Which sector calculation to use
    final bool isStandardLocation = (sectorIndex <= 1);
    int absoluteProgramSector;
    
    if (isStandardLocation) {
      // Standard format: program sector is relative to track start
      absoluteProgramSector = firstTrackSector + programSector;
    } else {
      // Non-standard format: program sector is relative to marker location
      absoluteProgramSector = firstTrackSector + sectorIndex + programSector;
    }
    
    // Create data to hash
    final dataToHash = <int>[];
    
    // First add title bytes
    dataToHash.addAll(titleBytes);
    
    // Read the first program sector to verify we have data
    final firstSectorToRead = absoluteProgramSector - firstTrackSector;
    final firstSectorData = await _chdReader.readSector(chdPath, track, firstSectorToRead);
    
    if (firstSectorData != null) {
    }
    
    // Read and hash all program sectors
    for (int i = 0; i < numSectors; i++) {
      final sectorToRead = absoluteProgramSector + i - firstTrackSector;
      
      final programSectorData = await _chdReader.readSector(chdPath, track, sectorToRead);
      
      if (programSectorData == null) {
        continue;
      }
      
      if (programSectorData.length < track.dataOffset + 2048) {
        continue;
      }
      
      final programData = programSectorData.sublist(track.dataOffset, track.dataOffset + 2048);
      
      // Add to hash data
      dataToHash.addAll(programData);
    }
    
    // Compute final MD5 hash
    final digest = md5.convert(dataToHash);
    final hash = digest.toString();
    
    return hash;
  } catch (e) {
    return null;
  }
}

// Helper method to compute hash with given parameters
Future<String?> computeHash(
    String chdPath, TrackInfo track, List<int> titleBytes, 
    int absoluteProgramSector, int numSectors) async {
  
  // Create data to hash
  final dataToHash = <int>[];
  
  // First add title bytes
  dataToHash.addAll(titleBytes);
  
  // Now read and hash the program sectors
  for (int i = 0; i < numSectors; i++) {
    // Calculate the relative sector to read
    final sectorToRead = (absoluteProgramSector + i) - track.startFrame;
    
    // Read each program sector
    final programSectorData = await _chdReader.readSector(chdPath, track, sectorToRead);
    
    if (programSectorData == null) {
      continue;
    }
    
    // Extract the data portion (always 2048 bytes)
    if (programSectorData.length < track.dataOffset + 2048) {
      continue;
    }
    
    final programData = programSectorData.sublist(track.dataOffset, track.dataOffset + 2048);
    
    // Add to hash data
    dataToHash.addAll(programData);
  }
  
  // Compute final MD5 hash
  final digest = md5.convert(dataToHash);
  final hash = digest.toString();
  
  return hash;
}



/// Process a found PC Engine CD marker and generate the hash
Future<String?> processMarkerAndHash(String chdPath, TrackInfo track, int sectorIndex, 
    int markerOffset, List<int> dataBuffer) async {
  try {
    // Extract title (22 bytes) at offset 106 from the beginning of the data
    int titleOffset = 106;
    
    // If marker position is not at standard position (32), adjust title offset
    if (markerOffset != 32 && markerOffset > 0) {
      // PC Engine CD header is standard layout: marker at 32, title at 106
      titleOffset = markerOffset + "PC Engine CD-ROM SYSTEM".length + (106 - (32 + "PC Engine CD-ROM SYSTEM".length));
    }
    
    // Ensure titleOffset is within bounds
    if (titleOffset + 22 > dataBuffer.length) {
      titleOffset = dataBuffer.length - 22;
    }
    
    final titleBytes = dataBuffer.sublist(titleOffset, titleOffset + 22);
    
    // Title in ASCII
    String.fromCharCodes(titleBytes.where((b) => b >= 32 && b <= 126)).trim();
    
    // Determine program sector and size (always at beginning of data)
    final programSector = (dataBuffer[0] << 16) + 
                        (dataBuffer[1] << 8) + 
                        dataBuffer[2];
                        
    final numSectors = dataBuffer[3];
    
    
    // Important: The program sector is relative to the FIRST track sector
    // In the original C implementation, the sector is adjusted by:
    // sector += rc_cd_first_track_sector(iterator, track_handle);
    
    // Create data to hash
    final dataToHash = <int>[];
    
    // First add title bytes exactly as in bin implementation
    dataToHash.addAll(titleBytes);
    
    
    // The critical difference is probably here:
    // In the bin implementation, the marker sector is found after the index offset
    // In the CHD implementation, we need to account for the first track sector
    
    // We're going to follow the original C implementation directly
    // The program sector is relative to the first track sector 
    
    // Add sectors from the bin file to hash calculations
    for (int i = 0; i < numSectors; i++) {
      
      // Read each program sector from track 2
      final programSectorData = await _chdReader.readSector(
        chdPath, 
        track, 
        programSector + i  // Use program sector directly (relative to track start)
      );
      
      if (programSectorData == null) {
        continue;
      }
      
      // Extract the data portion (always 2048 bytes)
      if (programSectorData.length < track.dataOffset + 2048) {
        continue;
      }
      
      final programData = programSectorData.sublist(
        track.dataOffset, 
        track.dataOffset + 2048
      );
      
      // Add to hash data
      dataToHash.addAll(programData);
    }
    
    // Compute final MD5 hash - use Dart's native implementation
    final digest = md5.convert(dataToHash);
    final hash = digest.toString();
    
    return hash;
  } catch (e) {
    return null;
  }
}





  /// Debug a CHD file to help diagnose issues
  Future<void> debugChdFile(String chdPath) async {
    if (!_chdReader.isInitialized) {
      return;
    }
    
    try {
      // Process the CHD file to get track information
      final chdResult = await _chdReader.processChdFile(chdPath);
      
      if (!chdResult.isSuccess) {
        return;
      }
      
     
      
      
      // For debugging, read a few sectors from each track
      for (final track in chdResult.tracks) {
        
        for (int i = 0; i < 5; i++) {
          final sectorData = await _chdReader.readSector(chdPath, track, i);
          if (sectorData != null) {
            sectorData.sublist(0, 100).map(
              (b) => b.toRadixString(16).padLeft(2, '0')
            ).join(' ');
            
            
            // For data tracks, look for the beginning of ISO9660 file system
            if (track.type.contains('MODE1') || track.type.contains('MODE2')) {
              final isoData = sectorData.sublist(track.dataOffset);
              
              // Check for CD001 pattern (standard ISO9660 identifier)
              if (isoData.length > 25) {
                final isoId = String.fromCharCodes(isoData.sublist(1, 6));
                if (isoId == 'CD001') {
                }
              }
              
              // Check for PC Engine marker
              final data = String.fromCharCodes(
                isoData.where((b) => b >= 32 && b <= 126)
              );
              if (data.contains('PC Engine')) {
              }
            }
          } else {
          }
        }
      }
      
      // Try to look for PC Engine CD marker in early sectors
      final dataTrack = chdResult.tracks.firstWhere(
        (track) => track.type.contains('MODE1') || track.type.contains('MODE2'),
        orElse: () => chdResult.tracks[0]
      );
      
      for (int i = 0; i < 30; i++) {
        final sectorData = await _chdReader.readSector(chdPath, dataTrack, i);
        if (sectorData != null) {
          final dataBuffer = sectorData.sublist(dataTrack.dataOffset);
          final data = String.fromCharCodes(
            dataBuffer.where((b) => b >= 32 && b <= 126)
          );
          
          if (data.contains('PC Engine CD-ROM SYSTEM')) {
            break;
          }
        }
      }
    // ignore: empty_catches
    } catch (e) {
    }
  }
}