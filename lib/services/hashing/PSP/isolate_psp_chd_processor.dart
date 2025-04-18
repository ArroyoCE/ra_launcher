import 'dart:async';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:retroachievements_organizer/services/hashing/CHD/chd_read_common.dart';




// Message to send to the isolate
class PspChdProcessRequest {
  final String filePath;
  final SendPort sendPort;

  PspChdProcessRequest(this.filePath, this.sendPort);
}

// Response from the isolate
class PspChdProcessResponse {
  final String? hash;
  final String? error;
  final String filePath;
  final double progress; // 0.0 to 1.0

  PspChdProcessResponse({
    this.hash,
    this.error,
    required this.filePath,
    this.progress = 1.0,
  });
}

/// Class to handle PSP filesystem operations for CHD files
class PspChdFilesystem {
  final ChdReader chdReader;
  final String filePath;
  final TrackInfo trackInfo;
  
  PspChdFilesystem(this.chdReader, this.filePath, this.trackInfo);
  
  /// Find the root directory in the ISO9660 filesystem
  Future<Map<String, dynamic>?> findRootDirectory() async {
    // Start by searching for the ISO9660 primary volume descriptor
    final pvdSector = await readSector(16);
    
    if (pvdSector == null) {
      debugPrint('Failed to read primary volume descriptor');
      return null;
    }
    
    // Check for ISO9660 identifier
    if (!checkIso9660Identifier(pvdSector)) {
      debugPrint('Not a valid ISO9660 filesystem');
      return null;
    }
    
    // Get root directory record
    return getRootDirectoryEntry(pvdSector);
  }
  
  /// Check if a sector contains the ISO9660 identifier
  bool checkIso9660Identifier(Uint8List sector) {
    // Check for "CD001" at offset 1
    if (sector.length < 6) return false;
    
    return sector[1] == 0x43 && // C
           sector[2] == 0x44 && // D
           sector[3] == 0x30 && // 0
           sector[4] == 0x30 && // 0
           sector[5] == 0x31;   // 1
  }
  
  /// Extract the root directory entry from the primary volume descriptor
  Map<String, dynamic>? getRootDirectoryEntry(Uint8List pvdSector) {
    if (pvdSector.length < 156 + 34) return null;
    
    // Root directory record starts at offset 156
    final size = pvdSector[156 + 10] | 
                (pvdSector[156 + 11] << 8) | 
                (pvdSector[156 + 12] << 16) | 
                (pvdSector[156 + 13] << 24);
                
    final lba = pvdSector[156 + 2] | 
               (pvdSector[156 + 3] << 8) | 
               (pvdSector[156 + 4] << 16) | 
               (pvdSector[156 + 5] << 24);
               
    return {
      'lba': lba,
      'size': size,
      'isDirectory': true,
    };
  }
  
  /// Read a sector at the given index
  Future<Uint8List?> readSector(int sectorIndex) async {
    return await chdReader.readSector(filePath, trackInfo, sectorIndex);
  }
  
  /// Find a file entry with the given name in a directory
  Future<Map<String, dynamic>?> findFileEntry(
      Map<String, dynamic> dirEntry, String name) async {
    final dirSector = dirEntry['lba'] as int;
    final dirSize = dirEntry['size'] as int;
    
    // Calculate how many sectors to read
    final sectorsToRead = (dirSize + 2047) ~/ 2048; // Round up
    
    // Read all sectors that make up the directory
    for (int i = 0; i < sectorsToRead; i++) {
      final sectorData = await readSector(dirSector + i);
      if (sectorData == null) continue;
      
      // Parse directory entries in this sector
      int offset = 0;
      while (offset < sectorData.length) {
        final recordLength = sectorData[offset];
        if (recordLength == 0) {
          // Move to next record or next sector
          offset++;
          if (offset >= sectorData.length) break;
          continue;
        }
        
        // Get the name length
        final nameLength = sectorData[offset + 32];
        if (nameLength == 0) {
          offset += recordLength;
          continue;
        }
        
        // Skip special entries (. and ..)
        if (nameLength == 1 && (sectorData[offset + 33] == 0 || sectorData[offset + 33] == 1)) {
          offset += recordLength;
          continue;
        }
        
        // Get the name
        String entryName = '';
        for (int i = 0; i < nameLength; i++) {
          // Handle semicolons which mark version numbers (;1)
          if (sectorData[offset + 33 + i] == 0x3B) break;
          entryName += String.fromCharCode(sectorData[offset + 33 + i]);
        }
        
        // Check if this is the entry we're looking for
        if (entryName.toUpperCase() == name.toUpperCase()) {
          final fileFlags = sectorData[offset + 25];
          final isDirectory = (fileFlags & 0x02) != 0;
          
          final lba = sectorData[offset + 2] | 
                     (sectorData[offset + 3] << 8) | 
                     (sectorData[offset + 4] << 16) | 
                     (sectorData[offset + 5] << 24);
                     
          final size = sectorData[offset + 10] | 
                      (sectorData[offset + 11] << 8) | 
                      (sectorData[offset + 12] << 16) | 
                      (sectorData[offset + 13] << 24);
                      
          return {
            'lba': lba,
            'size': size,
            'isDirectory': isDirectory,
          };
        }
        
        offset += recordLength;
      }
    }
    
    return null;
  }
  
  /// Find a directory entry with the given name in a directory
  Future<Map<String, dynamic>?> findDirectoryEntry(
      Map<String, dynamic> dirEntry, String name) async {
    final entry = await findFileEntry(dirEntry, name);
    if (entry != null && entry['isDirectory'] == true) {
      return entry;
    }
    return null;
  }
  
  /// Read a file with the given entry
  Future<Uint8List?> readFile(Map<String, dynamic> fileEntry) async {
    final lba = fileEntry['lba'] as int;
    final size = fileEntry['size'] as int;
    
    if (size <= 0) return null;
    
    // Create a buffer for the file data
    final buffer = Uint8List(size);
    int bytesRead = 0;
    
    // Calculate how many full sectors to read
    final fullSectors = size ~/ 2048;
    final remainder = size % 2048;
    
    // Read full sectors
    for (int i = 0; i < fullSectors; i++) {
      final sectorData = await readSector(lba + i);
      if (sectorData == null) {
        debugPrint('Failed to read sector ${lba + i}');
        return null;
      }
      
      // For data sectors, we only want the data part
      final dataOffset = trackInfo.dataOffset;
      final dataSize = min(2048, trackInfo.dataSize);
      
      if (dataOffset + dataSize <= sectorData.length) {
        buffer.setRange(bytesRead, bytesRead + dataSize, 
                       sectorData.sublist(dataOffset, dataOffset + dataSize));
      } else {
        buffer.setRange(bytesRead, bytesRead + sectorData.length - dataOffset, 
                       sectorData.sublist(dataOffset));
      }
      
      bytesRead += 2048;
    }
    
    // Read the remainder
    if (remainder > 0) {
      final sectorData = await readSector(lba + fullSectors);
      if (sectorData == null) {
        debugPrint('Failed to read sector ${lba + fullSectors}');
        return buffer.sublist(0, bytesRead); // Return what we have so far
      }
      
      final dataOffset = trackInfo.dataOffset;
      final dataSize = min(remainder, trackInfo.dataSize);
      
      if (dataOffset + dataSize <= sectorData.length) {
        buffer.setRange(bytesRead, bytesRead + dataSize, 
                       sectorData.sublist(dataOffset, dataOffset + dataSize));
      } else {
        buffer.setRange(bytesRead, bytesRead + sectorData.length - dataOffset, 
                       sectorData.sublist(dataOffset));
      }
    }
    
    return buffer;
  }
  
  /// Find and read the PARAM.SFO file from the PSP disc
  Future<Uint8List?> findAndReadParamSfo() async {
    // Get root directory
    final rootDir = await findRootDirectory();
    if (rootDir == null) {
      debugPrint('Could not find root directory');
      return null;
    }
    
    // Find PSP_GAME directory
    final pspGameDir = await findDirectoryEntry(rootDir, 'PSP_GAME');
    if (pspGameDir == null) {
      debugPrint('Could not find PSP_GAME directory');
      return null;
    }
    
    // Find PARAM.SFO file
    final paramSfoEntry = await findFileEntry(pspGameDir, 'PARAM.SFO');
    if (paramSfoEntry == null) {
      debugPrint('Could not find PARAM.SFO file');
      return null;
    }
    
    // Read PARAM.SFO file
    return await readFile(paramSfoEntry);
  }
  
  /// Find and read the EBOOT.BIN file from the PSP disc
  Future<Uint8List?> findAndReadEbootBin() async {
    // Get root directory
    final rootDir = await findRootDirectory();
    if (rootDir == null) {
      debugPrint('Could not find root directory');
      return null;
    }
    
    // Find PSP_GAME directory
    final pspGameDir = await findDirectoryEntry(rootDir, 'PSP_GAME');
    if (pspGameDir == null) {
      debugPrint('Could not find PSP_GAME directory');
      return null;
    }
    
    // Find SYSDIR directory
    final sysdirEntry = await findDirectoryEntry(pspGameDir, 'SYSDIR');
    if (sysdirEntry == null) {
      debugPrint('Could not find SYSDIR directory');
      return null;
    }
    
    // Find EBOOT.BIN file
    final ebootBinEntry = await findFileEntry(sysdirEntry, 'EBOOT.BIN');
    if (ebootBinEntry == null) {
      debugPrint('Could not find EBOOT.BIN file');
      return null;
    }
    
    // Read EBOOT.BIN file
    return await readFile(ebootBinEntry);
  }
  
  // Helper function for min value
  int min(int a, int b) {
    return a < b ? a : b;
  }
}

/// Class to process PSP CHD files in a separate isolate
class IsolatePspChdProcessor {
  /// Process a PSP CHD file in an isolate and return the hash
  static Future<String?> processPspChd(String filePath) async {
    final receivePort = ReceivePort();
    final completer = Completer<String?>();
    
    // Create and spawn the isolate
    final isolate = await Isolate.spawn(
      _processPspChdFileInIsolate,
      PspChdProcessRequest(filePath, receivePort.sendPort),
      debugName: 'PSP CHD Processor',
    );
    
    // Listen for messages from the isolate
    receivePort.listen((message) {
      if (message is PspChdProcessResponse) {
        // Complete when we get the final result
        if (message.hash != null) {
          completer.complete(message.hash);
        } else {
          debugPrint('Error processing PSP CHD: ${message.error}');
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
  static void _processPspChdFileInIsolate(PspChdProcessRequest request) async {
    final sendPort = request.sendPort;
    final filePath = request.filePath;
    
    try {
      // Create CHD reader
      final chdReader = ChdReader();
      
      if (!chdReader.isInitialized) {
        sendPort.send(PspChdProcessResponse(
          filePath: filePath,
          error: 'Failed to initialize CHD library',
        ));
        return;
      }
      
      // Process the CHD file
      final result = await chdReader.processChdFile(filePath);
      
      if (!result.isSuccess) {
        sendPort.send(PspChdProcessResponse(
          filePath: filePath,
          error: 'Error processing CHD file: ${result.error}',
        ));
        return;
      }
      
      // Check if it's a data disc
      if (!result.isDataDisc) {
        sendPort.send(PspChdProcessResponse(
          filePath: filePath,
          error: 'Not a data disc',
        ));
        return;
      }
      
      // Create the PSP filesystem handler
      final filesystem = PspChdFilesystem(chdReader, filePath, result.tracks[0]);
      
      // Test filesystem access
      var rootDir = await filesystem.findRootDirectory();
      if (rootDir == null) {
        sendPort.send(PspChdProcessResponse(
          filePath: filePath,
          error: 'Could not find root directory in filesystem',
        ));
        return;
      }
      
      // Read PARAM.SFO file
      final paramSfoData = await filesystem.findAndReadParamSfo();
      if (paramSfoData == null) {
        sendPort.send(PspChdProcessResponse(
          filePath: filePath,
          error: 'Could not find or read PARAM.SFO',
        ));
        return;
      }
      
      // Read EBOOT.BIN file
      final ebootBinData = await filesystem.findAndReadEbootBin();
      if (ebootBinData == null) {
        sendPort.send(PspChdProcessResponse(
          filePath: filePath,
          error: 'Could not find or read EBOOT.BIN',
        ));
        return;
      }
      
      // Calculate hash using both files
      final bytes = [...paramSfoData, ...ebootBinData];
      final digest = md5.convert(bytes);
      final hash = digest.toString();
      
      // Send the final result
      sendPort.send(PspChdProcessResponse(
        filePath: filePath,
        hash: hash,
      ));
    } catch (e, stackTrace) {
      debugPrint('Error in PSP CHD isolate: $e');
      debugPrint('Stack trace: $stackTrace');
      
      sendPort.send(PspChdProcessResponse(
        filePath: filePath,
        error: 'Exception: $e',
      ));
    }
  }
}