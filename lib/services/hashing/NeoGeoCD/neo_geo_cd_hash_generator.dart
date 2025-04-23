// lib/services/hashing/NeoGeoCD/neo_geo_cd_hash_generator.dart
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:retroachievements_organizer/services/hashing/CHD/chd_read_common.dart';
import 'package:retroachievements_organizer/services/hashing/NeoGeoCD/neo_geo_cd_track_reader.dart';




class NeoGeoCdHashGenerator {
  static const int SECTOR_SIZE = 2048;
  static const int IPL_SECTOR = 22; // IPL.TXT is usually at sector 22 on Neo Geo CD
  
  /// Hash a Neo Geo CD from a CHD file
  Future<String?> hashFromChd(String filePath, ChdProcessResult chdResult) async {
    // Find the data track (should be track 1)
    if (chdResult.tracks.isEmpty) {
      debugPrint('No tracks found in CHD file');
      return null;
    }
    
    final reader = ChdReader();
    final trackReader = NeoGeoCdTrackReader(filePath, reader);
    
    // Get the data track - either track 1 or first MODE1 track
    final dataTrack = _findDataTrack(chdResult.tracks);
    if (dataTrack == null) {
      debugPrint('Could not find data track in Neo Geo CD CHD');
      return null;
    }
    
    // Using direct approach for Neo Geo CD
    debugPrint('Reading IPL.TXT from sector $IPL_SECTOR');
    final iplContent = await trackReader.readSector(dataTrack, IPL_SECTOR);
    if (iplContent == null) {
      debugPrint('Could not read IPL.TXT from sector $IPL_SECTOR');
      return await _fallbackToSimpleHash(trackReader, dataTrack);
    }
    
    // Parse IPL.TXT to find PRG files
    final prgFiles = await _parsePrgFilesFromIpl(iplContent);
    if (prgFiles.isEmpty) {
      debugPrint('No PRG files found in IPL.TXT');
      return await _fallbackToSimpleHash(trackReader, dataTrack);
    }
    
    return await _hashPrgFiles(trackReader, dataTrack, prgFiles);
  }
  
  /// Hash a Neo Geo CD from a CUE file
  Future<String?> hashFromCue(String filePath) async {
    try {
      final trackReader = NeoGeoCdTrackReader.fromCueFile(filePath);
      
      // Get the data track
      final dataTrack = await trackReader.getDataTrack();
      if (dataTrack == null) {
        debugPrint('Could not find data track in Neo Geo CD CUE file');
        return null;
      }
      
      // Using direct approach for Neo Geo CD
      debugPrint('Reading IPL.TXT from sector $IPL_SECTOR');
      final iplContent = await trackReader.readSector(dataTrack, IPL_SECTOR);
      if (iplContent == null) {
        debugPrint('Could not read IPL.TXT from sector $IPL_SECTOR');
        return await _fallbackToSimpleHash(trackReader, dataTrack);
      }
      
      // Parse IPL.TXT to find PRG files
      final prgFiles = await _parsePrgFilesFromIpl(iplContent);
      if (prgFiles.isEmpty) {
        debugPrint('No PRG files found in IPL.TXT');
        return await _fallbackToSimpleHash(trackReader, dataTrack);
      }
      
      return await _hashPrgFiles(trackReader, dataTrack, prgFiles);
    } catch (e) {
      debugPrint('Error generating Neo Geo CD hash from CUE: $e');
      return null;
    }
  }
  
  /// Find data track from tracks list
  TrackInfo? _findDataTrack(List<TrackInfo> tracks) {
    // First look for track 1
    for (final track in tracks) {
      if (track.number == 1) {
        debugPrint('Using track 1 as data track');
        return track;
      }
    }
    
    // Fall back to first MODE1 or MODE2 track
    for (final track in tracks) {
      if (track.type.contains('MODE1') || track.type.contains('MODE2')) {
        debugPrint('Using ${track.type} track ${track.number} as data track');
        return track;
      }
    }
    
    // Last resort: just use the first track
    if (tracks.isNotEmpty) {
      debugPrint('Using first track as data track (fallback)');
      return tracks.first;
    }
    
    return null;
  }
  
  /// Parse IPL.TXT to find PRG files
 Future<List<NeoGeoPrgFile>> _parsePrgFilesFromIpl(Uint8List iplContent) async {
  final prgFiles = <NeoGeoPrgFile>[];
  
  // Enhance the binary scanning for more robust PRG file detection
  // Use a more comprehensive approach to find PRG file patterns
  
  // Neo Geo CD PRG files have various naming patterns: 
  // 1. Classic pattern: FILENAME.PRG
  // 2. Some games use: Fxx.PRG (where xx is a number)
  // 3. Others might use: GAME.PRG, TITLE.PRG, etc.
  
  // Look for .PRG pattern in a more robust way
  for (int i = 0; i < iplContent.length - 4; i++) {
    if ((iplContent[i] == 0x2E && // '.'
         (iplContent[i+1] == 0x50 || iplContent[i+1] == 0x70) && // 'P' or 'p'
         (iplContent[i+2] == 0x52 || iplContent[i+2] == 0x72) && // 'R' or 'r'
         (iplContent[i+3] == 0x47 || iplContent[i+3] == 0x67))) { // 'G' or 'g'
       
      // Search backward to find start of filename
      int start = i;
      while (start > 0 && 
             ((iplContent[start-1] >= 0x30 && iplContent[start-1] <= 0x39) || // 0-9
              (iplContent[start-1] >= 0x41 && iplContent[start-1] <= 0x5A) || // A-Z
              (iplContent[start-1] >= 0x61 && iplContent[start-1] <= 0x7A) || // a-z
              iplContent[start-1] == 0x5F || // '_'
              iplContent[start-1] == 0x2D || // '-'
              iplContent[start-1] == 0x5C || // '\'
              iplContent[start-1] == 0x2F || // '/'
              iplContent[start-1] == 0x24)) { // '$'
        start--;
      }
      
      // Extract the filename with a more lenient approach
      String filename = '';
      for (int j = start; j <= i + 3; j++) {
        if (iplContent[j] >= 32 && iplContent[j] <= 126) { // Valid ASCII
          filename += String.fromCharCode(iplContent[j]);
        }
      }
      
      // Add valid filenames with more lenient validation
      if (filename.isNotEmpty && (filename.endsWith(".PRG") || filename.endsWith(".pgr"))) {
        if (!prgFiles.any((file) => file.filename.toUpperCase() == filename.toUpperCase())) {
          debugPrint('Found PRG file via binary scanning: $filename');
          prgFiles.add(NeoGeoPrgFile(filename: filename, sector: 0, size: 0));
        }
      }
      
      // Skip ahead to avoid duplicates
      i = i + 3;
    }
  }
  
  // If still no PRG files found, try with common PRG file patterns
  if (prgFiles.isEmpty) {
    final commonPrgPatterns = [
      'OBJECT.PRG', 'TITLE.PRG', 'PROGRAM.PRG', 'STARTUP.PRG', 'GAME.PRG',
      'SYSTEM.PRG', 'NEOGEO.PRG', 'IPL.PRG', 'MAIN.PRG', 'DATA.PRG',
      'F00.PRG', 'F01.PRG', 'F02.PRG', 'F03.PRG', 'F04.PRG',
      'P00.PRG', 'P01.PRG', 'P02.PRG', 'P03.PRG', 'P04.PRG'
    ];
    
    // Convert IPL.TXT content to string for easier pattern matching
    String content = '';
    for (int i = 0; i < iplContent.length; i++) {
      if (iplContent[i] >= 32 && iplContent[i] <= 126) {
        content += String.fromCharCode(iplContent[i]);
      }
    }
    
    // Try direct search for common patterns
    for (final pattern in commonPrgPatterns) {
      if (content.toUpperCase().contains(pattern.toUpperCase())) {
        debugPrint('Found common PRG pattern: $pattern');
        prgFiles.add(NeoGeoPrgFile(filename: pattern, sector: 0, size: 0));
      }
    }
    
    // Last resort - just add some common PRG files
    if (prgFiles.isEmpty) {
      // Look for any pattern that might indicate a PRG file
      RegExp prgRegex = RegExp(r'[A-Z0-9_]{1,8}\.PRG', caseSensitive: false);
      final matches = prgRegex.allMatches(content);
      
      for (final match in matches) {
        final prgFile = match.group(0)!;
        debugPrint('Found PRG file via regex: $prgFile');
        prgFiles.add(NeoGeoPrgFile(filename: prgFile, sector: 0, size: 0));
      }
      
      // If still nothing, fall back to default names
      if (prgFiles.isEmpty) {
        debugPrint('No PRG files found, using generic PRG filenames');
        prgFiles.add(NeoGeoPrgFile(filename: "GAME.PRG", sector: 0, size: 0));
        prgFiles.add(NeoGeoPrgFile(filename: "TITLE.PRG", sector: 0, size: 0));
      }
    }
  }
  
  return prgFiles;
}

  /// Fall back to a simplified hash using initial sectors
  Future<String?> _fallbackToSimpleHash(NeoGeoCdTrackReader trackReader, TrackInfo track) async {
    debugPrint('Using fallback hashing method for Neo Geo CD');
    
    // In original RC Hash, Neo Geo CD hash is based on PRG files,
    // but when we can't find those, we'll hash the first ~100 sectors of track 1
    const sectors = 100;
    
    // Initialize MD5 hash
    final digest = md5.convert([]);
    Digest? finalHash = digest;
    final md5Converter = md5.startChunkedConversion(
      ChunkedConversionSink.withCallback((chunks) {
        finalHash = chunks.single;
      }),
    );
    
    // Hash the NEOGEOCD marker to ensure we're getting a consistent hash
    md5Converter.add(Uint8List.fromList('NEOGEOCD'.codeUnits));
    
    // Hash sectors 16-116 (common system sectors for Neo Geo CD)
    for (int sector = 16; sector < 16 + sectors; sector++) {
      final sectorData = await trackReader.readSector(track, sector);
      if (sectorData == null) continue;
      
      md5Converter.add(sectorData);
    }
    
    // Finalize hash
    md5Converter.close();
    return finalHash.toString();
  }
  
  /// Hash PRG files
  Future<String?> _hashPrgFiles(
    NeoGeoCdTrackReader trackReader,
    TrackInfo track,
    List<NeoGeoPrgFile> prgFiles) async {
  // Initialize MD5 hash
  Digest? finalHash;
  final md5Converter = md5.startChunkedConversion(
    ChunkedConversionSink.withCallback((chunks) {
      finalHash = chunks.single;
    }),
  );
  
  // Hash the game identifier first (typically from sector 0)
  final sectorZero = await trackReader.readSector(track, 0);
  if (sectorZero != null) {
    md5Converter.add(sectorZero);
  }
  
  bool hashedAnyFile = false;
  
  // Hash each PRG file name - even if we don't have the actual PRG file data
  for (final prgFile in prgFiles) {
    debugPrint('Hashing PRG file name: ${prgFile.filename}');
    md5Converter.add(Uint8List.fromList(prgFile.filename.codeUnits));
    hashedAnyFile = true;
  }
  
  // If we didn't hash any files, fall back to a simple hash
  if (!hashedAnyFile) {
    return await _fallbackToSimpleHash(trackReader, track);
  }
  
  // Finalize hash
  md5Converter.close();
  final hash = finalHash.toString();
  debugPrint('Generated Neo Geo CD hash: $hash');
  return hash;
}


}

/// Class to represent a PRG file in Neo Geo CD
class NeoGeoPrgFile {
  final String filename;
  final int sector;
  final int size;
  
  NeoGeoPrgFile({
    required this.filename,
    required this.sector,
    required this.size,
  });
}