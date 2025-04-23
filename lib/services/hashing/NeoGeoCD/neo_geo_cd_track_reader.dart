// lib/services/hashing/NeoGeoCD/neo_geo_cd_track_reader.dart
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:retroachievements_organizer/services/hashing/CHD/chd_read_common.dart';

class NeoGeoCdTrackReader {
  final String filePath;
  final ChdReader? chdReader;
  RandomAccessFile? binFile;
  List<TrackInfo>? tracks;
  Map<String, CueTrackInfo>? cueTrackMap;
  
  NeoGeoCdTrackReader(this.filePath, this.chdReader);
  
  // Constructor for creating from a CUE file
  factory NeoGeoCdTrackReader.fromCueFile(String cuePath) {
    return NeoGeoCdTrackReader(cuePath, null);
  }
  
  /// Get the data track from the CD
  Future<TrackInfo?> getDataTrack() async {
    if (chdReader != null) {
      // For CHD files, we use the CHD reader's track info
      final chdResult = await chdReader!.processChdFile(filePath);
      if (!chdResult.isSuccess || chdResult.tracks.isEmpty) {
        debugPrint('CHD processing failed: ${chdResult.error ?? "Unknown error"}');
        return null;
      }
      
      tracks = chdResult.tracks;
      
      // Find track 1 or first data track
      for (final track in tracks!) {
        if (track.number == 1) {
          debugPrint('Found track 1 in CHD');
          return track;
        }
      }
      
      // No track 1, try to find first data track
      for (final track in tracks!) {
        if (track.type.contains('MODE1') || track.type.contains('MODE2')) {
          debugPrint('Found data track ${track.number} in CHD');
          return track;
        }
      }
      
      // Fall back to first track
      if (tracks!.isNotEmpty) {
        debugPrint('Using first track from CHD as fallback');
        return tracks!.first;
      }
      
      return null;
    } else {
      // For CUE files, we parse the CUE file to find the data track
      try {
        final cueFile = File(filePath);
        if (!await cueFile.exists()) {
          debugPrint('CUE file does not exist: $filePath');
          return null;
        }
        
        final cueContent = await cueFile.readAsString();
        final cueParser = CueParser();
        final parsedTracks = cueParser.parse(cueContent, path.dirname(filePath));
        
        if (parsedTracks.isEmpty) {
          debugPrint('No tracks found in CUE file');
          return null;
        }
        
        cueTrackMap = {};
        for (final track in parsedTracks) {
          cueTrackMap![track.number.toString()] = track;
          
          // Find track 1 or data track
          if (track.number == 1 || track.type == 'DATA' || 
              track.type.contains('MODE1') || track.type.contains('MODE2')) {
            debugPrint('Found data track ${track.number} in CUE: ${track.type}');
            
            // Determine sector size based on track type
            int sectorSize = track.type.contains('2352') ? 2352 : 2048;
            int dataOffset = track.type.contains('2352') ? 16 : 0;
            
            return TrackInfo(
              number: track.number,
              type: track.type,
              sectorSize: sectorSize,
              pregap: track.pregap ?? 0,
              startFrame: track.startFrame,
              totalFrames: track.frames,
              dataOffset: dataOffset,
              dataSize: 2048,
            );
          }
        }
        
        // No track 1 or data track, use first track
        if (parsedTracks.isNotEmpty) {
          final track = parsedTracks[0];
          debugPrint('Using first track from CUE as fallback: ${track.number}');
          return TrackInfo(
            number: track.number,
            type: track.type,
            sectorSize: 2048,
            pregap: track.pregap ?? 0,
            startFrame: track.startFrame,
            totalFrames: track.frames,
            dataOffset: 0,
            dataSize: 2048,
          );
        }
        
        return null;
      } catch (e) {
        debugPrint('Error parsing CUE file: $e');
        return null;
      }
    }
  }
  
  /// Read a sector from a track
  Future<Uint8List?> readSector(TrackInfo track, int sector) async {
    if (sector < 0) {
      debugPrint('Invalid negative sector: $sector, using sector 0 instead');
      sector = 0;
    }
    
    if (chdReader != null) {
      // Read sector using CHD reader
      return await chdReader!.readSector(filePath, track, sector);
    } else {
      // Read sector from BIN file
      try {
        if (binFile == null) {
          // Find the BIN file associated with this track
          final trackNumber = track.number;
          final cueTrack = cueTrackMap?[trackNumber.toString()];
          
          if (cueTrack == null || cueTrack.file == null) {
            debugPrint('No file specified for track $trackNumber');
            return null;
          }
          
          final binFilePath = path.join(path.dirname(filePath), cueTrack.file!);
          debugPrint('Opening bin file: $binFilePath');
          binFile = await File(binFilePath).open(mode: FileMode.read);
        }
        
        // Calculate the offset in the BIN file
        int sectorOffset = sector * track.sectorSize;
        
        // Seek to the sector
        await binFile!.setPosition(sectorOffset);
        
        // Read the sector data
        return await binFile!.read(track.sectorSize);
      } catch (e) {
        debugPrint('Error reading sector: $e');
        return null;
      }
    }
  }
  
  /// Close resources
  Future<void> close() async {
    if (binFile != null) {
      await binFile!.close();
      binFile = null;
    }
  }
}

/// Class to represent a track in a CUE file
class CueTrackInfo {
  final int number;
  final String type;
  final String? file;
  final int startFrame;
  final int frames;
  final int? pregap;
  
  CueTrackInfo({
    required this.number,
    required this.type,
    this.file,
    required this.startFrame,
    required this.frames,
    this.pregap,
  });
}

/// Class to parse CUE files
class CueParser {
  List<CueTrackInfo> parse(String cueContent, String basePath) {
    final List<CueTrackInfo> tracks = [];
    String? currentFile;
    int trackNumber = 0;
    String trackType = '';
    int startFrame = 0;
    int totalFrames = 0;
    int? pregap;
    
    final lines = cueContent.split('\n');
    
    for (final line in lines) {
      final trimmedLine = line.trim();
      
      if (trimmedLine.startsWith('FILE ')) {
        // Extract file name
        final fileNameMatch = RegExp(r'FILE\s+"([^"]+)"').firstMatch(trimmedLine);
        if (fileNameMatch != null) {
          currentFile = fileNameMatch.group(1);
          debugPrint('Found file in CUE: $currentFile');
        }
      } else if (trimmedLine.startsWith('TRACK ')) {
        // If we were processing a track before, add it to the list
        if (trackNumber > 0 && trackType.isNotEmpty) {
          tracks.add(CueTrackInfo(
            number: trackNumber,
            type: trackType,
            file: currentFile,
            startFrame: startFrame,
            frames: totalFrames,
            pregap: pregap,
          ));
        }
        
        // Extract track number and type
        final trackMatch = RegExp(r'TRACK\s+(\d+)\s+(\w+)').firstMatch(trimmedLine);
        if (trackMatch != null) {
          trackNumber = int.parse(trackMatch.group(1)!);
          trackType = trackMatch.group(2)!;
          
          // Check for extended track type (e.g., MODE1/2352)
          if (trimmedLine.contains('/')) {
            final extendedMatch = RegExp(r'TRACK\s+\d+\s+(\w+/\d+)').firstMatch(trimmedLine);
            if (extendedMatch != null) {
              trackType = extendedMatch.group(1)!;
            }
          }
          
          debugPrint('Found track: $trackNumber, type: $trackType');
          startFrame = 0;
          totalFrames = 0;
          pregap = null;
        }
      } else if (trimmedLine.startsWith('INDEX ')) {
        // Extract index information
        final indexMatch = RegExp(r'INDEX\s+(\d+)\s+(\d+):(\d+):(\d+)').firstMatch(trimmedLine);
        if (indexMatch != null) {
          final indexNumber = int.parse(indexMatch.group(1)!);
          final minutes = int.parse(indexMatch.group(2)!);
          final seconds = int.parse(indexMatch.group(3)!);
          final frames = int.parse(indexMatch.group(4)!);
          
          // Calculate frame offset (75 frames per second)
          final frameOffset = minutes * 60 * 75 + seconds * 75 + frames;
          
          if (indexNumber == 1) {
            // This is the start of the track data
            startFrame = frameOffset;
            debugPrint('Track $trackNumber starts at frame: $startFrame');
          }
        }
      } else if (trimmedLine.startsWith('PREGAP ')) {
        // Extract pregap information
        final pregapMatch = RegExp(r'PREGAP\s+(\d+):(\d+):(\d+)').firstMatch(trimmedLine);
        if (pregapMatch != null) {
          final minutes = int.parse(pregapMatch.group(1)!);
          final seconds = int.parse(pregapMatch.group(2)!);
          final frames = int.parse(pregapMatch.group(3)!);
          
          // Calculate pregap in frames
          pregap = minutes * 60 * 75 + seconds * 75 + frames;
          debugPrint('Track $trackNumber has pregap: $pregap frames');
        }
      }
    }
    
    // Add the last track
    if (trackNumber > 0 && trackType.isNotEmpty) {
      // Estimate total frames from file size
      if (currentFile != null) {
        final file = File(path.join(basePath, currentFile));
        if (file.existsSync()) {
          final fileSize = file.lengthSync();
          
          if (trackType.contains('AUDIO')) {
            // Audio tracks: 2352 bytes per frame
            totalFrames = fileSize ~/ 2352;
          } else if (trackType.contains('2352')) {
            // MODE1/2352 or similar
            totalFrames = fileSize ~/ 2352;
          } else {
            // Data tracks: 2048 bytes per frame for MODE1
            totalFrames = fileSize ~/ 2048;
          }
          
          debugPrint('Estimated $totalFrames frames for track $trackNumber (file size: $fileSize bytes)');
        } else {
          debugPrint('File does not exist: ${path.join(basePath, currentFile)}');
        }
      }
      
      tracks.add(CueTrackInfo(
        number: trackNumber,
        type: trackType,
        file: currentFile,
        startFrame: startFrame,
        frames: totalFrames,
        pregap: pregap,
      ));
    }
    
    return tracks;
  }
}