import 'dart:math' as Math;

import 'package:crypto/crypto.dart';
import 'package:retroachievements_organizer/services/hashing/CHD/chd_read_common.dart';

/// Handles CHD files for PC Engine CD games
class PCECDChdHandler {
  final ChdReader _chdReader;
  
  PCECDChdHandler(this._chdReader);

  /// Hash a PC Engine CD from a CHD file
  /// Hash a PC Engine CD from a CHD file
/// Hash a PC Engine CD from a CHD file
/// Hash a PC Engine CD from a CHD file
Future<String?> hashPCECDFromChd(String chdPath) async {
  if (!_chdReader.isInitialized) {
    print('CHD reader is not initialized, cannot hash');
    return null;
  }
  
  try {
    // Process the CHD file to get track information
    print('Opening CHD file: $chdPath');
    final chdResult = await _chdReader.processChdFile(chdPath);
    
    if (!chdResult.isSuccess) {
      print('Failed to process CHD file: ${chdResult.error}');
      return null;
    }
    
    print('CHD file processed: ${chdResult.header}');
    print('Found ${chdResult.tracks.length} tracks in CHD file');
    
    // The marker we're looking for
    final marker = "PC Engine CD-ROM SYSTEM";
    
    // First try the common case - track 2 sector 1
    if (chdResult.tracks.length >= 2) {
      final track = chdResult.tracks[1]; // Track 2
      final sectorData = await _chdReader.readSector(chdPath, track, 1);
      
      if (sectorData != null) {
        final dataBuffer = sectorData.sublist(track.dataOffset);
        
        print('Checking for PC Engine CD marker in sector data:');
        final debugRange = dataBuffer.sublist(0, Math.min(100, dataBuffer.length));
        print('First ${debugRange.length} bytes in hex: ${debugRange.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');
        
        // Check for marker at the standard offset (32)
        if (dataBuffer.length >= 32 + marker.length &&
            String.fromCharCodes(dataBuffer.sublist(32, 32 + marker.length)) == marker) {
          // Process using the standard approach
          print('Found PC Engine CD marker at standard location (offset 32 in sector 1 of track 2)!');
          return processMarkerAndHash(chdPath, track, 1, 32, dataBuffer);
        }
      }
    }
    
    // Second, do a comprehensive scan of all tracks and many sectors
    print('PC Engine CD marker not found in standard location, doing comprehensive scan...');
    
    // Check all tracks to be thorough
    for (int trackIndex = 0; trackIndex < chdResult.tracks.length; trackIndex++) {
      final track = chdResult.tracks[trackIndex];
      print('Scanning track ${track.number}: ${track.type}');
      
      // Determine how many sectors to scan
      // For large data tracks, scan more sectors
      int sectorsToScan = track.type.contains('MODE1') || track.type.contains('MODE2') 
          ? Math.min(1000, track.totalFrames)  // Scan up to 1000 sectors for data tracks
          : Math.min(100, track.totalFrames);  // Scan up to 100 sectors for audio tracks
      
      // Scan sectors in batches to avoid reading too many at once
      for (int sectorIndex = 0; sectorIndex < sectorsToScan; sectorIndex++) {
        // Print progress every 100 sectors
        if (sectorIndex % 100 == 0) {
          print('  Scanning sector $sectorIndex of $sectorsToScan in track ${track.number}...');
        }
        
        final sectorData = await _chdReader.readSector(chdPath, track, sectorIndex);
        if (sectorData == null) continue;
        
        final dataBuffer = sectorData.sublist(track.dataOffset);
        
        // Skip if the buffer is too small for our marker
        if (dataBuffer.length < marker.length) continue;
        
        // Fast scan using String.fromCharCodes to compare blocks
        for (int offset = 0; offset <= dataBuffer.length - marker.length; offset++) {
          if (String.fromCharCodes(dataBuffer.sublist(offset, offset + marker.length)) == marker) {
            print('Found PC Engine CD marker at offset $offset in sector $sectorIndex of track ${track.number}!');
            return processMarkerAndHash(chdPath, track, sectorIndex, offset, dataBuffer);
          }
        }
      }
    }
    
    print('PC Engine CD marker not found after comprehensive scan');
    return null;
  } catch (e) {
    print('Error in hashPCECDFromChd: $e');
    return null;
  }
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
      print('Warning: Adjusted title offset to fit within buffer');
    }
    
    final titleBytes = dataBuffer.sublist(titleOffset, titleOffset + 22);
    
    // Title in ASCII
    final title = String.fromCharCodes(titleBytes.where((b) => b >= 32 && b <= 126)).trim();
    print('PC Engine CD title: "$title"');
    print('Title bytes: ${titleBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');
    
    // Determine program sector and size (always at beginning of data)
    final programSector = (dataBuffer[0] << 16) + 
                        (dataBuffer[1] << 8) + 
                        dataBuffer[2];
                        
    final numSectors = dataBuffer[3];
    
    print('Program starts at sector $programSector, size: $numSectors sectors');
    
    // Important: The program sector is relative to the FIRST track sector
    // In the original C implementation, the sector is adjusted by:
    // sector += rc_cd_first_track_sector(iterator, track_handle);
    
    // Create data to hash
    final dataToHash = <int>[];
    
    // First add title bytes exactly as in bin implementation
    dataToHash.addAll(titleBytes);
    
    print('Track starts at frame ${track.startFrame}');
    
    // The critical difference is probably here:
    // In the bin implementation, the marker sector is found after the index offset
    // In the CHD implementation, we need to account for the first track sector
    
    // We're going to follow the original C implementation directly
    // The program sector is relative to the first track sector 
    final absoluteProgramSector = track.startFrame + programSector;
    print('Absolute program sector: $absoluteProgramSector');
    
    // Add sectors from the bin file to hash calculations
    for (int i = 0; i < numSectors; i++) {
      final sector = absoluteProgramSector + i;
      
      // Read each program sector from track 2
      final programSectorData = await _chdReader.readSector(
        chdPath, 
        track, 
        programSector + i  // Use program sector directly (relative to track start)
      );
      
      if (programSectorData == null) {
        print('Failed to read program sector ${programSector + i}');
        continue;
      }
      
      // Extract the data portion (always 2048 bytes)
      if (programSectorData.length < track.dataOffset + 2048) {
        print('Warning: Sector size too small for data extraction');
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
    
    print('PC Engine CD hash: $hash');
    return hash;
  } catch (e) {
    print('Error processing marker and hashing: $e');
    return null;
  }
}

  /// Debug a CHD file to help diagnose issues
  Future<void> debugChdFile(String chdPath) async {
    if (!_chdReader.isInitialized) {
      print('CHD reader is not initialized, cannot debug');
      return;
    }
    
    try {
      // Process the CHD file to get track information
      final chdResult = await _chdReader.processChdFile(chdPath);
      
      if (!chdResult.isSuccess) {
        print('Failed to process CHD file: ${chdResult.error}');
        return;
      }
      
      print('CHD Header: ${chdResult.header}');
      print('Tracks found:');
      for (final track in chdResult.tracks) {
        print('- $track');
      }
      
      // For debugging, read a few sectors from each track
      for (final track in chdResult.tracks) {
        print('\nReading first 3 sectors from track ${track.number}:');
        
        for (int i = 0; i < 5; i++) {
          final sectorData = await _chdReader.readSector(chdPath, track, i);
          if (sectorData != null) {
            print('  Sector $i:');
            final sectorHex = sectorData.sublist(0, 100).map(
              (b) => b.toRadixString(16).padLeft(2, '0')
            ).join(' ');
            
            print('    First 64 bytes: $sectorHex');
            
            // For data tracks, look for the beginning of ISO9660 file system
            if (track.type.contains('MODE1') || track.type.contains('MODE2')) {
              final isoData = sectorData.sublist(track.dataOffset);
              
              // Check for CD001 pattern (standard ISO9660 identifier)
              if (isoData.length > 25) {
                final isoId = String.fromCharCodes(isoData.sublist(1, 6));
                if (isoId == 'CD001') {
                  print('    Found ISO9660 identifier at sector $i');
                }
              }
              
              // Check for PC Engine marker
              final data = String.fromCharCodes(
                isoData.where((b) => b >= 32 && b <= 126)
              );
              if (data.contains('PC Engine')) {
                print('    Found PC Engine marker in sector $i: $data');
              }
            }
          } else {
            print('  Failed to read sector $i');
          }
        }
      }
      
      // Try to look for PC Engine CD marker in early sectors
      print('\nScanning for PC Engine CD markers in early sectors:');
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
            print('Found PC Engine marker in sector $i!');
            print('Sector data: $data');
            break;
          }
        }
      }
    } catch (e) {
      print('Error debugging CHD file: $e');
    }
  }
}