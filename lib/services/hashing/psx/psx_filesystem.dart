// FILE: psx_filesystem.dart (Based on Original, with _readSectorCached made public)

import 'dart:convert';
import 'dart:math'; // For min/max if used

import 'package:flutter/foundation.dart'; // For debugPrint

import '../CHD/chd_read_common.dart'; // Adjust import

/// Class to handle reading the PlayStation ISO9660 filesystem from a CHD
class PsxFilesystem {
  final ChdReader _chdReader;
  final String _filePath;
  final TrackInfo _dataTrack;

  // Cache for sectors to avoid repeated reads
  final Map<int, Uint8List> _sectorCache = {};
  // *** Use original cache size or keep the increased one? Let's keep 100 for now ***
  final int _maxCacheSize = 100;

  PsxFilesystem(this._chdReader, this._filePath, this._dataTrack);

  /// Find the location of the root directory with optimized sector reading (Original Logic)
  Future<Map<String, dynamic>?> findRootDirectory() async {
    // The standard location for ISO9660 Primary Volume Descriptor is sector 16
    // *** Make call public ***
    Uint8List? sectorData = await readSectorCached(16);

    if (sectorData == null) {
      return null;
    }

    // Try different offsets where the CD001 marker might be located (Original Logic)
    List<int> cd001 = [0x43, 0x44, 0x30, 0x30, 0x31]; // "CD001" in ASCII
    List<int> alternativeOffsets = [1, 17, 25]; // Check common offsets relative to sector start

    for (int startOffset in alternativeOffsets) {
        if (_checkMarker(sectorData, startOffset, cd001)) {
            int descriptorOffset = startOffset - 1;
             if (descriptorOffset >= 0 && descriptorOffset + 170 <= sectorData.length) {
                 int rootDirLBA = _readInt32LE(sectorData, descriptorOffset + 158);
                 int rootDirSize = _readInt32LE(sectorData, descriptorOffset + 166);
                 if (rootDirLBA > 0 && rootDirSize > 0) {
                    return {'lba': rootDirLBA, 'size': rootDirSize};
                 }
             }
        }
    }
    return null; // Not found
  }

  // Helper method to check for a marker sequence (Original Logic)
  bool _checkMarker(Uint8List data, int offset, List<int> marker) {
    if (offset < 0 || offset + marker.length > data.length) return false;
    for (int j = 0; j < marker.length; j++) {
      if (data[offset + j] != marker[j]) {
        return false;
      }
    }
    return true;
  }

  // Helper method to read a 32-bit little-endian integer (Original Logic - simplified)
  int _readInt32LE(Uint8List data, int offset) {
     if (offset < 0 || offset + 4 > data.length) {
        return 0;
     }
     // Using original bitwise logic (assuming little-endian platform or acceptable risk)
     // Or use ByteData for guaranteed LE read:
     // var byteData = data.buffer.asByteData(data.offsetInBytes + offset, 4);
     // return byteData.getInt32(0, Endian.little);
     return data[offset] |
           (data[offset + 1] << 8) |
           (data[offset + 2] << 16) |
           (data[offset + 3] << 24);
  }

  // *** Made public: Renamed _readSectorCached to readSectorCached ***
  Future<Uint8List?> readSectorCached(int sectorIndex) async {
    if (_sectorCache.containsKey(sectorIndex)) {
      return _sectorCache[sectorIndex];
    }
    // Use the ChdReader passed in constructor
    Uint8List? sectorData = await _chdReader.readSector(_filePath, _dataTrack, sectorIndex);
    if (sectorData != null) {
      if (_sectorCache.length >= _maxCacheSize) {
        _sectorCache.remove(_sectorCache.keys.first);
      }
      _sectorCache[sectorIndex] = sectorData;
    }
    return sectorData;
  }

  /// List files in a directory (Original Logic)
   Future<List<DirectoryEntry>?> listDirectory(int dirLBA, int dirSize) async {
    List<DirectoryEntry> entries = [];
    int currentSectorIndex = dirLBA;
    int bytesRemainingInDir = dirSize;
    int sectorReadAttempts = 0;
    const MAX_SECTOR_READ_ATTEMPTS = 500; // Safety break

    final int dataSizePerSector = _dataTrack.dataSize > 0 ? _dataTrack.dataSize : 2048;
    if (dataSizePerSector <= 0) return null;

    while (bytesRemainingInDir > 0 && sectorReadAttempts < MAX_SECTOR_READ_ATTEMPTS) {
      sectorReadAttempts++;
      // *** Make call public ***
      Uint8List? sectorData = await readSectorCached(currentSectorIndex);
      if (sectorData == null) return null; // Error reading

      int dataOffset = _dataTrack.dataOffset;
      int dataLen = sectorData.length - dataOffset;
      if (dataOffset < 0 || dataOffset >= sectorData.length || dataLen <= 0) {
          currentSectorIndex++;
          continue; // Skip bad sector offset
      }

      int offsetInSectorData = 0;
      while (offsetInSectorData < dataLen) {
          if (bytesRemainingInDir <= 0) break;

          int recordLen = sectorData[dataOffset + offsetInSectorData];
          if (recordLen == 0) {
             bytesRemainingInDir -= (dataLen - offsetInSectorData);
             break; // Padding, move to next sector
          }
          if (offsetInSectorData + recordLen > dataLen || offsetInSectorData + 33 > dataLen) {
             bytesRemainingInDir -= (dataLen - offsetInSectorData);
             break; // Corrupt record or spans sector, move to next sector
          }

          int baseOffset = dataOffset + offsetInSectorData;
          int fileLBA = _readInt32LE(sectorData, baseOffset + 2);
          int fileSize = _readInt32LE(sectorData, baseOffset + 10);
          int fileFlags = sectorData[baseOffset + 25];
          int fileNameLen = sectorData[baseOffset + 32];

          if (fileNameLen > 0 && baseOffset + 33 + fileNameLen <= sectorData.length) {
              Uint8List nameBytes = sectorData.sublist(baseOffset + 33, baseOffset + 33 + fileNameLen);
              String fileName = latin1.decode(nameBytes, allowInvalid: true);
              if (fileName != '\u0000' && fileName != '\u0001') {
                  entries.add(DirectoryEntry(
                      name: fileName, // Store raw name
                      lba: fileLBA,
                      size: fileSize,
                      isDirectory: (fileFlags & 0x02) == 0x02,
                  ));
              }
          }

          offsetInSectorData += recordLen;
          bytesRemainingInDir -= recordLen;
      }
      currentSectorIndex++;
    }
    return entries;
  }

  /// Find a file in the root directory (Original Logic)
  Future<DirectoryEntry?> findFileInRoot(String fileName) async {
    Map<String, dynamic>? rootDir = await findRootDirectory();
    if (rootDir == null) return null;
    List<DirectoryEntry>? entries = await listDirectory(rootDir['lba'], rootDir['size']);
    if (entries == null) return null;

    String upperFileName = fileName.toUpperCase();
    for (var entry in entries) {
       // Original comparison logic (normalize name for comparison)
       String entryNameUpper = entry.name.toUpperCase();
       int versionIndex = entryNameUpper.lastIndexOf(';');
       if (versionIndex > 0 && entryNameUpper.substring(versionIndex) == ';1') {
           entryNameUpper = entryNameUpper.substring(0, versionIndex);
       }
       if (!entry.isDirectory && entryNameUpper == upperFileName) {
         return entry;
       }
    }
    return null;
  }

  /// Find a file at a specific path (Original Logic)
  Future<DirectoryEntry?> findFile(String filePath) async {
    Map<String, dynamic>? rootDir = await findRootDirectory();
    if (rootDir == null) return null;

    String normalizedPath = _normalizePath(filePath); // Use original normalization
    List<String> pathParts = normalizedPath.split('/').where((part) => part.isNotEmpty).toList();
    if (pathParts.isEmpty) return null;

    int currentDirLBA = rootDir['lba'];
    int currentDirSize = rootDir['size'];
    DirectoryEntry? foundEntry;

    for (int i = 0; i < pathParts.length; i++) {
      String targetPartNameUpper = pathParts[i].toUpperCase();
      bool isLastPart = (i == pathParts.length - 1);
      List<DirectoryEntry>? entries = await listDirectory(currentDirLBA, currentDirSize);
      if (entries == null) return null;

      bool foundNext = false;
      for (var entry in entries) {
         String entryNameUpper = entry.name.toUpperCase();
         int versionIndex = entryNameUpper.lastIndexOf(';');
         if (versionIndex > 0 && entryNameUpper.substring(versionIndex) == ';1') {
             entryNameUpper = entryNameUpper.substring(0, versionIndex);
         }
         if (entryNameUpper == targetPartNameUpper) {
            if (isLastPart) {
                if (!entry.isDirectory) { foundEntry = entry; foundNext = true; break; }
            } else {
                if (entry.isDirectory) { currentDirLBA = entry.lba; currentDirSize = entry.size; foundNext = true; break; }
            }
         }
      }
      if (!foundNext) return null;
      if (foundEntry != null) break;
    }
    return foundEntry;
  }

  /// Read a file's contents (Original Logic) - Needed for SYSTEM.CNF
  Future<Uint8List?> readFile(DirectoryEntry file) async {
    if (file.isDirectory) return null;
    if (file.size <= 0) return Uint8List(0);

    final int dataSizePerSector = _dataTrack.dataSize > 0 ? _dataTrack.dataSize : 2048;
    if (dataSizePerSector <= 0) return null;
    int sectorsToRead = (file.size + (dataSizePerSector - 1)) ~/ dataSizePerSector;
    Uint8List fileData = Uint8List(file.size);
    int bytesCopied = 0;

    // ** Simpler sequential read as per original likely intent **
    // (Batching readFile was an optimization attempt, reverting)
    for (int i = 0; i < sectorsToRead; i++) {
       // *** Make call public ***
       Uint8List? sectorData = await readSectorCached(file.lba + i);
       if (sectorData == null) return null; // Read error

       int dataOffset = _dataTrack.dataOffset;
       int availableDataLength = sectorData.length - dataOffset;
       if (dataOffset < 0 || dataOffset >= sectorData.length || availableDataLength <= 0) continue;

       int remainingFileBytes = file.size - bytesCopied;
       int bytesToCopy = min(remainingFileBytes, availableDataLength);
       bytesToCopy = min(bytesToCopy, dataSizePerSector);

       if (bytesToCopy > 0) {
          try {
             fileData.setRange(bytesCopied, bytesCopied + bytesToCopy, sectorData, dataOffset);
             bytesCopied += bytesToCopy;
          } catch (e) { return null; } // Error during copy
       }
       if (bytesCopied >= file.size) break;
    }

    if (bytesCopied != file.size) {
        return fileData.sublist(0, bytesCopied); // Return partial on error/mismatch
    }
    return fileData;
  }


  /// Parse SYSTEM.CNF file to find the executable path (Original Logic)
  Future<String?> findExecutablePath() async {
    DirectoryEntry? systemCnf = await findFileInRoot('SYSTEM.CNF');
    if (systemCnf == null) return null;
    Uint8List? cnfData = await readFile(systemCnf); // Uses original readFile
    if (cnfData == null) return null;
    String cnfContent = ascii.decode(cnfData, allowInvalid: true);

    // Original Regex
    RegExp bootRegExp = RegExp(r'BOOT\s*=\s*([^\s;]+)', caseSensitive: false);
    Match? match = bootRegExp.firstMatch(cnfContent);
    if (match != null && match.groupCount >= 1) {
      String execPath = match.group(1)!.trim();
      return execPath.isNotEmpty ? execPath : null; // Return null if empty
    }
    return null;
  }

  /// Normalize a PlayStation executable path (Original Logic)
  String _normalizePath(String path) {
    String result = path;
    if (result.toLowerCase().startsWith('cdrom:')) {
      result = result.substring(6);
    }
    result = result.replaceAll('\\', '/'); // Use forward slash
    if (result.startsWith('/')) {
      result = result.substring(1);
    }
    // Remove version number like ;1 for lookups
    int versionIndex = result.lastIndexOf(';');
    if (versionIndex > 0 && result.substring(versionIndex) == ';1') {
      result = result.substring(0, versionIndex);
    }
    // Original didn't remove trailing slash or force uppercase here
    return result;
  }

   // *** ADDED HELPER FOR CHUNKED HASHING ***
   // Reads a sector and returns only the relevant data part.
   Future<Uint8List?> readSectorDataForHashing(int sectorIndex) async {
       Uint8List? fullSector = await readSectorCached(sectorIndex); // Uses the now public method
       if (fullSector == null) return null;

       int offset = _dataTrack.dataOffset;
       int size = _dataTrack.dataSize > 0 ? _dataTrack.dataSize : 2048;

       if (offset < 0 || offset >= fullSector.length) return Uint8List(0);

       int availableBytes = fullSector.length - offset;
       size = min(size, availableBytes);

       if (size <= 0) return Uint8List(0);

       try {
           return fullSector.sublist(offset, offset + size);
       } catch (e) {
           debugPrint('Error creating sublist for sector $sectorIndex data: $e');
           return null;
       }
   }
}