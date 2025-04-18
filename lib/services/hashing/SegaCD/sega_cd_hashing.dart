import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:retroachievements_organizer/services/hashing/CHD/chd_read_common.dart';

// Message to send to the isolate
class SegaCDSaturnProcessRequest {
  final String filePath;
  final SendPort sendPort;
  final bool isSaturn; // To differentiate between Sega CD and Saturn

  SegaCDSaturnProcessRequest(this.filePath, this.sendPort, this.isSaturn);
}

// Response from the isolate
class SegaCDSaturnProcessResponse {
  final String? hash;
  final String? error;
  final String filePath;
  final double progress; // 0.0 to 1.0

  SegaCDSaturnProcessResponse({
    this.hash,
    this.error,
    required this.filePath,
    this.progress = 1.0,
  });
}

/// Class to handle Sega CD and Saturn filesystem operations
class SegaCDSaturnReader {
  // Constants for identifiers - exact matches from the C code
  static final List<int> SEGA_CD_IDENTIFIER = utf8.encode("SEGADISCSYSTEM  ");
  static final List<int> SEGA_SATURN_IDENTIFIER = utf8.encode("SEGA SEGASATURN ");
  
  static const int HEADER_SIZE = 512;
  static const int SECTOR_SIZE = 2352;
  
  final String filePath;
  final bool isSaturn;
  
  // For CHD files
  final ChdReader? chdReader;
  TrackInfo? trackInfo;
  
  SegaCDSaturnReader(this.filePath, this.isSaturn, {this.chdReader, this.trackInfo});
  
  /// Read the header data from a BIN/ISO file
  Future<Uint8List?> readHeaderFromBinIso() async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        debugPrint('File does not exist: $filePath');
        return null;
      }
      
      final randomAccessFile = await file.open(mode: FileMode.read);
      try {
        // Try different potential sector offsets
        final sectorOffsets = [0, 16];
        
        for (final offset in sectorOffsets) {
          // Position file pointer
          await randomAccessFile.setPosition(offset);
          
          // Read header
          final headerData = Uint8List(HEADER_SIZE);
          final bytesRead = await randomAccessFile.readInto(headerData);
          
          if (bytesRead < HEADER_SIZE) {
            debugPrint('Failed to read complete header: $bytesRead bytes read');
            continue;
          }
          
          // Debug print the header
          _debugPrintHeader(headerData);
          
          // Check if it's a valid header
          if (_hasValidIdentifier(headerData)) {
            return headerData;
          }
        }
        
        // If we get here, we tried all offsets without finding a valid header
        debugPrint('No valid header found at any offset');
        return null;
      } finally {
        await randomAccessFile.close();
      }
    } catch (e) {
      debugPrint('Error reading header: $e');
      return null;
    }
  }
  
  /// Read the header data from a CHD file
  Future<Uint8List?> readHeaderFromChd() async {
    if (chdReader == null || trackInfo == null) {
      debugPrint('CHD reader or track info is null');
      return null;
    }
    
    try {
      // For CD formats, we need to check multiple sectors
      // Try sectors 0, 16, and 17 (common locations for system area)
      final sectorsToCheck = [0, 16, 17]; 
      
      for (final sector in sectorsToCheck) {
        debugPrint('Checking sector $sector for header...');
        
        final sectorData = await chdReader!.readSector(filePath, trackInfo!, sector);
        if (sectorData == null) {
          debugPrint('Failed to read sector $sector from CHD');
          continue;
        }
        
        // For debugging, print parts of the sector as hex and string
        debugPrint('Sector $sector data (first 16 bytes):');
        _debugPrintHeader(sectorData);
        
        // For CD formats, there's often a 16-byte sync pattern at the start
        // Try both with and without the sync pattern
        final offsets = [0, 16, 24];
        
        for (final offset in offsets) {
          if (offset + HEADER_SIZE > sectorData.length) {
            continue;
          }
          
          final headerCandidate = sectorData.sublist(offset, offset + HEADER_SIZE);
          debugPrint('Checking at offset $offset:');
          _debugPrintHeader(headerCandidate);
          
          if (_hasValidIdentifier(headerCandidate)) {
            debugPrint('Found valid header at sector $sector, offset $offset');
            return headerCandidate;
          }
        }
      }
      
      // If we get here, we couldn't find a valid header in any of the checked sectors
      debugPrint('No valid header found in any sector');
      return null;
    } catch (e) {
      debugPrint('Error reading header from CHD: $e');
      return null;
    }
  }
  
  /// Check if the data has a valid Sega CD or Saturn identifier
  bool _hasValidIdentifier(Uint8List data) {
    if (data.length < 16) return false;
    
    // Extract the first 16 bytes for identification
    final identifier = data.sublist(0, 16);
    
    // Try to convert to string for easier comparison
    final identifierString = utf8.decode(identifier, allowMalformed: true);
    
    // For debugging
    debugPrint('Checking identifier: "$identifierString"');
    
    // Check if it matches either identifier
    final matchesSegaCD = _compareBytes(identifier, 0, SEGA_CD_IDENTIFIER, 0, 16);
    final matchesSaturn = _compareBytes(identifier, 0, SEGA_SATURN_IDENTIFIER, 0, 16);
    
    // For debugging
    if (matchesSegaCD) debugPrint('MATCH! Valid Sega CD identifier');
    if (matchesSaturn) debugPrint('MATCH! Valid Saturn identifier');
    
    return (isSaturn && matchesSaturn) || (!isSaturn && matchesSegaCD);
  }
  
  /// Check if the header is valid for the requested system
  bool isValidHeader(Uint8List headerData) {
    return _hasValidIdentifier(headerData);
  }
  
  /// Helper for debugging header data
  void _debugPrintHeader(Uint8List data) {
    if (data.length < 16) return;
    
    // Print as hex
    final hexBytes = data.sublist(0, 16).map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
    
    // Try to interpret as string
    String stringBytes;
    try {
      stringBytes = utf8.decode(data.sublist(0, 16), allowMalformed: true);
    } catch (e) {
      stringBytes = "<not valid UTF-8>";
    }
    
    debugPrint('Header data: $hexBytes ("$stringBytes")');
  }
  
  /// Helper to compare byte sequences
  bool _compareBytes(List<int> a, int aOffset, List<int> b, int bOffset, int length) {
    if (a.length < aOffset + length || b.length < bOffset + length) {
      return false;
    }
    
    for (int i = 0; i < length; i++) {
      if (a[aOffset + i] != b[bOffset + i]) {
        return false;
      }
    }
    
    return true;
  }
  
  /// Generate hash from header data
  String generateHash(Uint8List headerData) {
    // For Sega CD/Saturn, we hash the first 512 bytes of sector 0
    final digest = md5.convert(headerData);
    return digest.toString();
  }
}


/// Class to process Sega CD and Saturn files in a separate isolate
class IsolateSegaCDSaturnProcessor {
  /// Process a Sega CD/Saturn file in an isolate and return the hash
  static Future<String?> processFile(String filePath, bool isSaturn) async {
    final receivePort = ReceivePort();
    final completer = Completer<String?>();
    
    // Create and spawn the isolate
    final isolate = await Isolate.spawn(
      _processFileInIsolate,
      SegaCDSaturnProcessRequest(filePath, receivePort.sendPort, isSaturn),
      debugName: isSaturn ? 'Sega Saturn Processor' : 'Sega CD Processor',
    );
    
    // Listen for messages from the isolate
    receivePort.listen((message) {
      if (message is SegaCDSaturnProcessResponse) {
        // Complete when we get the final result
        if (message.hash != null) {
          completer.complete(message.hash);
        } else {
          debugPrint('Error processing file: ${message.error}');
          completer.complete(null);
        }
        
        // Clean up
        receivePort.close();
        isolate.kill();
      }
    });
    
    return completer.future;
  }
  
  /// The isolate entry point
  static void _processFileInIsolate(SegaCDSaturnProcessRequest request) async {
  final sendPort = request.sendPort;
  final filePath = request.filePath;
  final isSaturn = request.isSaturn;
  final fileExt = filePath.toLowerCase();
  
  try {
    Uint8List? headerData;
    
    debugPrint('Processing ${isSaturn ? "Saturn" : "Sega CD"} file: $filePath');
    
    // Handle different file types
    if (fileExt.endsWith('.chd')) {
      // Handle CHD files
      final chdReader = ChdReader();
      
      if (!chdReader.isInitialized) {
        sendPort.send(SegaCDSaturnProcessResponse(
          filePath: filePath,
          error: 'Failed to initialize CHD library',
        ));
        return;
      }
      
      // Process the CHD file
      final result = await chdReader.processChdFile(filePath);
      
      if (!result.isSuccess) {
        sendPort.send(SegaCDSaturnProcessResponse(
          filePath: filePath,
          error: 'Error processing CHD file: ${result.error}',
        ));
        return;
      }
      
      // Check if it's a data disc and has tracks
      if (!result.isDataDisc || result.tracks.isEmpty) {
        sendPort.send(SegaCDSaturnProcessResponse(
          filePath: filePath,
          error: result.tracks.isEmpty ? 'No tracks found' : 'Not a data disc',
        ));
        return;
      }
      
      debugPrint('CHD processed, found ${result.tracks.length} tracks');
      
      // Create the reader
      final reader = SegaCDSaturnReader(
        filePath, 
        isSaturn,
        chdReader: chdReader,
        trackInfo: result.tracks[0],
      );
      
      // Read the header
      headerData = await reader.readHeaderFromChd();
    } else if (fileExt.endsWith('.cue')) {
      // For CUE files, find and open the associated BIN file
      final cueFile = File(filePath);
      if (!await cueFile.exists()) {
        sendPort.send(SegaCDSaturnProcessResponse(
          filePath: filePath,
          error: 'CUE file does not exist',
        ));
        return;
      }
      
      try {
        final cueContent = await cueFile.readAsString();
        final fileRegExp = RegExp(r'FILE\s+"(.+?)"\s+BINARY', caseSensitive: false);
        final match = fileRegExp.firstMatch(cueContent);
        
        if (match != null) {
          final binFileName = match.group(1);
          if (binFileName != null) {
            final directory = File(filePath).parent.path;
            final binPath = '$directory${Platform.pathSeparator}$binFileName';
            
            if (await File(binPath).exists()) {
              debugPrint('Found associated BIN file: $binPath');
              
              // Read from BIN file
              final reader = SegaCDSaturnReader(binPath, isSaturn);
              headerData = await reader.readHeaderFromBinIso();
            } else {
              debugPrint('Associated BIN file not found: $binPath');
            }
          }
        }
        
        if (headerData == null) {
          sendPort.send(SegaCDSaturnProcessResponse(
            filePath: filePath,
            error: 'Could not find associated BIN file in CUE',
          ));
          return;
        }
      } catch (e) {
        debugPrint('Error processing CUE file: $e');
        sendPort.send(SegaCDSaturnProcessResponse(
          filePath: filePath,
          error: 'Error processing CUE file: $e',
        ));
        return;
      }
    } else if (fileExt.endsWith('.iso') || fileExt.endsWith('.bin') || fileExt.endsWith('.img')) {
      // Handle BIN/ISO files
      final reader = SegaCDSaturnReader(filePath, isSaturn);
      headerData = await reader.readHeaderFromBinIso();
    } else {
      sendPort.send(SegaCDSaturnProcessResponse(
        filePath: filePath,
        error: 'Unsupported file format',
      ));
      return;
    }
    
    if (headerData == null) {
      sendPort.send(SegaCDSaturnProcessResponse(
        filePath: filePath,
        error: 'Failed to read header data',
      ));
      return;
    }
    
    // Validate header
    final reader = SegaCDSaturnReader(filePath, isSaturn);
    if (!reader.isValidHeader(headerData)) {
      sendPort.send(SegaCDSaturnProcessResponse(
        filePath: filePath,
        error: isSaturn ? 'Not a valid Saturn disc' : 'Not a valid Sega CD disc',
      ));
      return;
    }
    
    // Generate hash
    final hash = reader.generateHash(headerData);
    debugPrint('Generated hash: $hash');
    
    // Send the final result
    sendPort.send(SegaCDSaturnProcessResponse(
      filePath: filePath,
      hash: hash,
    ));
  } catch (e, stackTrace) {
    debugPrint('Error in isolate: $e');
    debugPrint('Stack trace: $stackTrace');
    
    sendPort.send(SegaCDSaturnProcessResponse(
      filePath: filePath,
      error: 'Exception: $e',
    ));
  }
}

}

/// Class for handling M3U playlists
class M3UPlaylistHandler {
  /// Extract the first path from a M3U playlist
  static Future<String?> getFirstDiscPath(String m3uPath) async {
    try {
      final file = File(m3uPath);
      if (!await file.exists()) {
        debugPrint('M3U file does not exist: $m3uPath');
        return null;
      }
      
      final lines = await file.readAsLines();
      
      // Find the first non-comment, non-empty line
      for (final line in lines) {
        final trimmedLine = line.trim();
        if (trimmedLine.isEmpty || trimmedLine.startsWith('#')) {
          continue;
        }
        
        // Check if it's a relative path
        String discPath = trimmedLine;
        if (!_isAbsolutePath(discPath)) {
          // Convert to absolute path relative to the M3U file
          final directory = File(m3uPath).parent.path;
          discPath = '$directory${Platform.pathSeparator}$discPath';
        }
        
        // Check if the file exists
        if (await File(discPath).exists()) {
          return discPath;
        }
      }
      
      debugPrint('No valid disc path found in M3U file');
      return null;
    } catch (e) {
      debugPrint('Error reading M3U file: $e');
      return null;
    }
  }
  
  /// Check if a path is absolute
  static bool _isAbsolutePath(String path) {
    if (Platform.isWindows) {
      // Windows absolute paths start with drive letter or UNC path
      return path.contains(':') || path.startsWith('\\\\');
    } else {
      // Unix-like absolute paths start with /
      return path.startsWith('/');
    }
  }
}

/// Main integration class for Sega CD/Saturn hashing
class SegaCDSaturnHashIntegration {
  /// Hash files in the given folders
  Future<Map<String, String>> hashFilesInFolders(
    List<String> folders, 
    bool isSaturn, 
    {void Function(int current, int total)? progressCallback}
  ) async {
    final Map<String, String> hashes = {};
    final validExtensions = ['.iso', '.bin', '.img', '.chd'];
    
    try {
      // Get all files with valid extensions
      final allFiles = await _findFilesWithExtensions(folders, validExtensions);
      final total = allFiles.length;
      
      debugPrint('Found ${allFiles.length} files to process');
      
      // Process each file
      for (int i = 0; i < allFiles.length; i++) {
        final filePath = allFiles[i];
        
        try {
          String fileToProcess = filePath;
          
          
          // Process the file
          final hash = await IsolateSegaCDSaturnProcessor.processFile(fileToProcess, isSaturn);
          
          if (hash != null) {
            hashes[filePath] = hash;
            debugPrint('Successfully hashed: $filePath -> $hash');
          } else {
            debugPrint('Failed to hash: $filePath');
          }
        } catch (e) {
          debugPrint('Error processing file $filePath: $e');
        }
        
        // Update progress
        if (progressCallback != null) {
          progressCallback(i + 1, total);
        }
      }
      
      debugPrint('Completed hashing ${hashes.length} out of $total files');
      return hashes;
    } catch (e) {
      debugPrint('Error in hashFilesInFolders: $e');
      return hashes;
    }
  }
  
  /// Find all files with the given extensions in the folders
  Future<List<String>> _findFilesWithExtensions(
    List<String> folders, 
    List<String> extensions
  ) async {
    final List<String> result = [];
    
    for (final folder in folders) {
      try {
        final directory = Directory(folder);
        if (!await directory.exists()) {
          debugPrint('Directory does not exist: $folder');
          continue;
        }
        
        await for (final entity in directory.list(recursive: true)) {
          if (entity is File) {
            final lowerPath = entity.path.toLowerCase();
            if (extensions.any((ext) => lowerPath.endsWith(ext))) {
              result.add(entity.path);
            }
          }
        }
      } catch (e) {
        debugPrint('Error scanning directory $folder: $e');
      }
    }
    
    return result;
  }
}