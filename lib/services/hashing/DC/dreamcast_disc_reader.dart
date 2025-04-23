// lib/services/hashing/dreamcast/dreamcast_disc_reader.dart
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:retroachievements_organizer/services/hashing/DC/dreamcast_hash_utils.dart';



 // Helper methods for GDI
  class GdiTrack {
    final int trackNumber;
    final int lba;
    final int type;
    final int sectorSize;
    final String filename;
    
    GdiTrack({
      required this.trackNumber,
      required this.lba,
      required this.type,
      required this.sectorSize,
      required this.filename,
    });
  }


class DreamcastDiscReader {
  static const int SECTOR_SIZE = 2048;
  
  Future<String?> processFile(String path, String extension) async {
    switch (extension) {
      case 'gdi':
        return await _processGdiFile(path);
      case 'cue':
        return await _processCueFile(path);
      case 'cdi':
        return await _processCdiFile(path);
      default:
        return null;
    }
  }
  

  
  Future<String?> _processGdiFile(String path) async {
    try {
      // 1. Read the GDI file to get track information
      final file = File(path);
      final gdiContent = await file.readAsString();
      final tracks = _parseGdiFile(gdiContent);
      
      if (tracks.isEmpty) {
        debugPrint('No tracks found in GDI file');
        return null;
      }
      
      // 2. Find the data track (usually track 3)
      GdiTrack? dataTrack = tracks.firstWhere(
        (t) => t.trackNumber == 3, 
        orElse: () => tracks.first
      );
      
      // 3. Find the track file path
      final dataFilePath = _resolveTrackFilePath(path, dataTrack.filename);
      if (dataFilePath == null) {
        debugPrint('Could not resolve data track file path');
        return null;
      }
      
      // 4. Extract IP.BIN from the data track
      final dataFile = File(dataFilePath);
      if (!await dataFile.exists()) {
        debugPrint('Data track file does not exist: $dataFilePath');
        return null;
      }
      
      final dataFileStream = await dataFile.open(mode: FileMode.read);
      
      // GD-ROM track files often have various sector sizes and formats
      // Try to determine the sector format and find the SEGAKATANA marker
      bool isValidDreamcast = false;
      Uint8List? ipBinData;
      
      // Read the first 2352 bytes (maximum sector size)
      final sectorBuffer = Uint8List(2352);
      await dataFileStream.readInto(sectorBuffer);
      
      if (DreamcastHashUtils.validateSegaSegakatana(sectorBuffer)) {
        isValidDreamcast = true;
        ipBinData = sectorBuffer.sublist(0, DreamcastHashUtils.IP_BIN_SIZE);
      } else {
        // Try checking for common sector formats
        // For 2048-byte sectors, data starts at offset 0
        if (sectorBuffer.length >= 2048 && 
            DreamcastHashUtils.validateSegaSegakatana(sectorBuffer.sublist(0, 2048))) {
          isValidDreamcast = true;
          ipBinData = sectorBuffer.sublist(0, DreamcastHashUtils.IP_BIN_SIZE);
        }
        // For 2352-byte sectors, data starts at offset 16
        else if (sectorBuffer.length >= 16 + DreamcastHashUtils.IP_BIN_SIZE && 
                 DreamcastHashUtils.validateSegaSegakatana(sectorBuffer.sublist(16))) {
          isValidDreamcast = true;
          ipBinData = sectorBuffer.sublist(16, 16 + DreamcastHashUtils.IP_BIN_SIZE);
        }
      }
      
      await dataFileStream.close();
      
      if (!isValidDreamcast || ipBinData == null) {
        debugPrint('Not a valid Dreamcast GDI: no SEGA SEGAKATANA marker found');
        return null;
      }
      
      // 5. Extract the boot file name from IP.BIN
      final bootFileName = DreamcastHashUtils.extractBootFileName(ipBinData);
      if (bootFileName == null || bootFileName.isEmpty) {
        debugPrint('Boot executable not specified in IP.BIN');
        return null;
      }
      
      debugPrint('Found boot file name: $bootFileName');
      
      // 6. For simplicity and compatibility with the original implementation,
      // use a dummy boot file content
      final dummyBootContent = Uint8List(64);
      
      // 7. Calculate the hash
      return DreamcastHashUtils.calculateDreamcastHash(
        ipBinData, bootFileName, dummyBootContent);
    } catch (e) {
      debugPrint('Error processing GDI file: $e');
      return null;
    }
  }
  
  Future<String?> _processCueFile(String path) async {
    try {
      // 1. Parse the CUE file to find the BIN file
      final file = File(path);
      final cueContent = await file.readAsString();
      
      final binFilePath = _parseCueFile(cueContent, path);
      if (binFilePath == null) {
        debugPrint('Could not find BIN file in CUE sheet');
        return null;
      }
      
      // 2. Open the BIN file
      final binFile = File(binFilePath);
      if (!await binFile.exists()) {
        debugPrint('BIN file does not exist: $binFilePath');
        return null;
      }
      
      // 3. Extract IP.BIN from the BIN file
      final binStream = await binFile.open(mode: FileMode.read);
      
      // Try to find the IP.BIN in the BIN file
      // Dreamcast CD tracks can be in various formats
      bool isValidDreamcast = false;
      Uint8List? ipBinData;
      
      // First try at offset 0 (raw data)
      final sectorBuffer = Uint8List(2352);
      await binStream.readInto(sectorBuffer);
      
      if (DreamcastHashUtils.validateSegaSegakatana(sectorBuffer)) {
        isValidDreamcast = true;
        ipBinData = sectorBuffer.sublist(0, DreamcastHashUtils.IP_BIN_SIZE);
      } else {
        // Try at offset 16 (2352-byte sectors with 16-byte header)
        if (sectorBuffer.length >= 16 + DreamcastHashUtils.IP_BIN_SIZE && 
            DreamcastHashUtils.validateSegaSegakatana(sectorBuffer.sublist(16))) {
          isValidDreamcast = true;
          ipBinData = sectorBuffer.sublist(16, 16 + DreamcastHashUtils.IP_BIN_SIZE);
        }
        // Try sector 16 (for GD-ROM images)
        else {
          await binStream.setPosition(16 * 2048);
          final gdromBuffer = Uint8List(2048);
          await binStream.readInto(gdromBuffer);
          
          if (DreamcastHashUtils.validateSegaSegakatana(gdromBuffer)) {
            isValidDreamcast = true;
            ipBinData = gdromBuffer.sublist(0, DreamcastHashUtils.IP_BIN_SIZE);
          }
        }
      }
      
      await binStream.close();
      
      if (!isValidDreamcast || ipBinData == null) {
        debugPrint('Not a valid Dreamcast BIN: no SEGA SEGAKATANA marker found');
        return null;
      }
      
      // 4. Extract the boot file name from IP.BIN
      final bootFileName = DreamcastHashUtils.extractBootFileName(ipBinData);
      if (bootFileName == null || bootFileName.isEmpty) {
        debugPrint('Boot executable not specified in IP.BIN');
        return null;
      }
      
      debugPrint('Found boot file name: $bootFileName');
      
      // 5. Use a dummy boot file content for compatibility
      final dummyBootContent = Uint8List(64);
      
      // 6. Calculate the hash
      return DreamcastHashUtils.calculateDreamcastHash(
        ipBinData, bootFileName, dummyBootContent);
    } catch (e) {
      debugPrint('Error processing CUE file: $e');
      return null;
    }
  }
  
  Future<String?> _processCdiFile(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) {
        debugPrint('CDI file does not exist: $path');
        return null;
      }
      
      final fileSize = await file.length();
      if (fileSize < 2048) {
        debugPrint('CDI file too small: $path');
        return null;
      }
      
      // CDI files have a complex format, but we just need to find the IP.BIN data
      final fileStream = await file.open(mode: FileMode.read);
      
      // Try common offsets where the SEGA marker might be found
      final offsets = [0, 16, 32, 64, 128, 2048, 2352, 4096, 8192, 16384, 32768];
      bool isValidDreamcast = false;
      Uint8List? ipBinData;
      
      for (final offset in offsets) {
        if (offset + 2048 > fileSize) continue;
        
        await fileStream.setPosition(offset);
        final buffer = Uint8List(2048);
        await fileStream.readInto(buffer);
        
        if (DreamcastHashUtils.validateSegaSegakatana(buffer)) {
          isValidDreamcast = true;
          ipBinData = buffer.sublist(0, DreamcastHashUtils.IP_BIN_SIZE);
          break;
        }
      }
      
      await fileStream.close();
      
      if (!isValidDreamcast || ipBinData == null) {
        debugPrint('Not a valid Dreamcast CDI: no SEGA SEGAKATANA marker found');
        return null;
      }
      
      // Extract the boot file name from IP.BIN
      final bootFileName = DreamcastHashUtils.extractBootFileName(ipBinData);
      if (bootFileName == null || bootFileName.isEmpty) {
        debugPrint('Boot executable not specified in IP.BIN');
        return null;
      }
      
      debugPrint('Found boot file name: $bootFileName');
      
      // Use a dummy boot file content
      final dummyBootContent = Uint8List(64);
      
      // Calculate the hash
      return DreamcastHashUtils.calculateDreamcastHash(
        ipBinData, bootFileName, dummyBootContent);
    } catch (e) {
      debugPrint('Error processing CDI file: $e');
      return null;
    }
  }
  
 
  
  List<GdiTrack> _parseGdiFile(String content) {
  final tracks = <GdiTrack>[];
  final lines = content.split('\n');
  
  if (lines.isEmpty) return tracks;
  
  // First line contains the number of tracks
  final trackCount = int.tryParse(lines.first.trim());
  if (trackCount == null || trackCount <= 0) return tracks;
  
  // Parse each track line
  for (int i = 1; i <= trackCount && i < lines.length; i++) {
    final line = lines[i].trim();
    if (line.isEmpty) continue;
    
    // Handle both space and tab delimiters
    List<String> parts;
    if (line.contains('\t')) {
      parts = line.split('\t');
    } else {
      // Regular expression to handle multiple spaces
      parts = line.split(RegExp(r'\s+'));
    }
    
    if (parts.length < 5) {
      debugPrint('Invalid GDI track line format: $line');
      continue;
    }
    
    final trackNumber = int.tryParse(parts[0]);
    final lba = int.tryParse(parts[1]);
    final type = int.tryParse(parts[2]);
    final sectorSize = int.tryParse(parts[3]);
    
    // Handle quoted filenames
    String filename = parts[4];
    if (parts.length > 5 && filename.startsWith('"') && !filename.endsWith('"')) {
      // Filename with spaces is split across multiple parts
      for (int j = 5; j < parts.length; j++) {
        filename += " ${parts[j]}";
        if (parts[j].endsWith('"')) break;
      }
    }
    filename = filename.replaceAll('"', '');
    
    if (trackNumber == null || lba == null || type == null || sectorSize == null) {
      debugPrint('Invalid GDI track data: $line');
      continue;
    }
    
    debugPrint('Found track: #$trackNumber, file: $filename');
    
    tracks.add(GdiTrack(
      trackNumber: trackNumber,
      lba: lba,
      type: type,
      sectorSize: sectorSize,
      filename: filename,
    ));
  }
  
  return tracks;
}


 String? _resolveTrackFilePath(String gdiPath, String trackFilename) {
  final directory = File(gdiPath).parent;
  
  // Try several variations of the path
  final possiblePaths = [
    '${directory.path}${Platform.pathSeparator}$trackFilename',
    '${directory.path}${Platform.pathSeparator}${trackFilename.replaceAll('"', '')}',
    // Try with lowercase filename
    '${directory.path}${Platform.pathSeparator}${trackFilename.toLowerCase()}',
    // Try with just the filename part (no directories)
    '${directory.path}${Platform.pathSeparator}${trackFilename.replaceAll('"', '').split(Platform.pathSeparator).last}'
  ];
  
  for (final path in possiblePaths) {
    if (File(path).existsSync()) {
      return path;
    }
  }
  
  // Debug what files are actually in the directory
  try {
    final dirContents = directory.listSync();
    debugPrint('Directory contents for ${directory.path}:');
    for (var file in dirContents) {
      debugPrint('  ${file.path}');
    }
    debugPrint('Looking for track: $trackFilename');
  } catch (e) {
    debugPrint('Error listing directory: $e');
  }
  
  return null;
}


  String? _parseCueFile(String cueContent, String cuePath) {
    final lines = cueContent.split('\n');
    
    for (final line in lines) {
      final trimmedLine = line.trim();
      if (trimmedLine.startsWith('FILE ')) {
        // Extract the file name (may be in quotes)
        final quoteStart = trimmedLine.indexOf('"');
        final quoteEnd = trimmedLine.lastIndexOf('"');
        
        if (quoteStart >= 0 && quoteEnd > quoteStart) {
          final filename = trimmedLine.substring(quoteStart + 1, quoteEnd);
          final directory = File(cuePath).parent;
          final binPath = '${directory.path}/$filename';
          
          if (File(binPath).existsSync()) {
            return binPath;
          }
        } else {
          // Try without quotes
          final parts = trimmedLine.split(' ');
          if (parts.length >= 2) {
            final filename = parts[1];
            final directory = File(cuePath).parent;
            final binPath = '${directory.path}/$filename';
            
            if (File(binPath).existsSync()) {
              return binPath;
            }
          }
        }
      }
    }
    
    return null;
  }
}