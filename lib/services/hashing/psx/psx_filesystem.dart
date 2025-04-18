import 'dart:convert';
import 'dart:typed_data';

import '../CHD/chd_read_common.dart';

/// Class to handle reading the PlayStation ISO9660 filesystem from a CHD
class PsxFilesystem {
  final ChdReader _chdReader;
  final String _filePath;
  final TrackInfo _dataTrack;
  
  // Cache for sectors to avoid repeated reads
  final Map<int, Uint8List> _sectorCache = {};
  final int _maxCacheSize = 50; // Limit cache size to avoid memory issues
  
  PsxFilesystem(this._chdReader, this._filePath, this._dataTrack);
  
  /// Find the location of the root directory with optimized sector reading
  Future<Map<String, dynamic>?> findRootDirectory() async {
    // The standard location for ISO9660 Primary Volume Descriptor is sector 16
    Uint8List? sectorData = await _readSectorCached(16);
    
    if (sectorData == null) {
      return null;
    }
    
    // Try different offsets where the CD001 marker might be located
    List<int> cd001 = [0x43, 0x44, 0x30, 0x30, 0x31]; // "CD001" in ASCII
    
    // For PlayStation discs, the CD001 marker is typically at offset 25 in MODE2_RAW format
    int offset = 25;
    if (_checkMarker(sectorData, offset, cd001)) {
      // PlayStation uses MODE2_XA format with a 24-byte header
      int descriptorOffset = 24;
      
      // Extract root directory information according to ISO 9660 standard
      int rootDirLBA = _readInt32(sectorData, descriptorOffset + 158);
      int rootDirSize = _readInt32(sectorData, descriptorOffset + 166);
      
      return {
        'lba': rootDirLBA,
        'size': rootDirSize,
      };
    }
    
    // If we didn't find it with the first approach, try other common offsets
    List<int> alternativeOffsets = [1, 17];
    for (int altOffset in alternativeOffsets) {
      if (_checkMarker(sectorData, altOffset, cd001)) {
        int descriptorOffset = (altOffset == 1) ? 0 : 16;
        
        int rootDirLBA = _readInt32(sectorData, descriptorOffset + 158);
        int rootDirSize = _readInt32(sectorData, descriptorOffset + 166);
        
        return {
          'lba': rootDirLBA,
          'size': rootDirSize,
        };
      }
    }
    
    return null;
  }

  // Helper method to check for a marker sequence
  bool _checkMarker(Uint8List data, int offset, List<int> marker) {
    if (offset + marker.length > data.length) return false;
    
    for (int j = 0; j < marker.length; j++) {
      if (data[offset + j] != marker[j]) {
        return false;
      }
    }
    return true;
  }

  // Helper method to read a 32-bit integer from a byte array
  int _readInt32(Uint8List data, int offset) {
    if (offset + 4 > data.length) {
      return 0;
    }
    return data[offset] | 
          (data[offset + 1] << 8) | 
          (data[offset + 2] << 16) | 
          (data[offset + 3] << 24);
  }
  
  // Cached sector reading to improve performance
  Future<Uint8List?> _readSectorCached(int sectorIndex) async {
    // Check if sector is in cache
    if (_sectorCache.containsKey(sectorIndex)) {
      return _sectorCache[sectorIndex];
    }
    
    // Read the sector
    Uint8List? sectorData = await _chdReader.readSector(_filePath, _dataTrack, sectorIndex);
    
    // Cache the sector if read was successful
    if (sectorData != null) {
      // Maintain cache size limit
      if (_sectorCache.length >= _maxCacheSize) {
        // Remove oldest entry (first key)
        _sectorCache.remove(_sectorCache.keys.first);
      }
      
      _sectorCache[sectorIndex] = sectorData;
    }
    
    return sectorData;
  }
  
  /// List files in a directory - optimized to reduce I/O operations
  Future<List<DirectoryEntry>?> listDirectory(int dirLBA, int dirSize) async {
    List<DirectoryEntry> entries = [];
    int currentSector = dirLBA;
    int bytesRead = 0;
    
    // Pre-allocate a buffer for multiple sectors to reduce I/O operations
    final sectorsNeeded = (dirSize + (_dataTrack.dataSize - 1)) ~/ _dataTrack.dataSize;
    List<Uint8List?> sectorBuffers = [];
    
    // Read all sectors in parallel for better performance
    List<Future<Uint8List?>> sectorReads = [];
    for (int i = 0; i < sectorsNeeded && i < 10; i++) { // Limit batch size to 10
      sectorReads.add(_readSectorCached(currentSector + i));
    }
    
    sectorBuffers = await Future.wait(sectorReads);
    
    // Process sectors one by one
    int sectorIndex = 0;
    while (bytesRead < dirSize && sectorIndex < sectorBuffers.length) {
      final sectorData = sectorBuffers[sectorIndex];
      if (sectorData == null) {
        return null;
      }
      
      // Apply the correct data offset for PlayStation discs
      int dataOffset = _dataTrack.dataOffset;
      
      // Make sure we're only looking at the actual data portion
      if (dataOffset >= sectorData.length) {
        return null;
      }
      
      // Process directory entries in this sector
      int offset = 0;
      while (offset < _dataTrack.dataSize) {
        // Get record length (first byte of directory record)
        int actualOffset = offset + dataOffset;
        if (actualOffset >= sectorData.length) {
          break;
        }
        
        int recordLen = sectorData[actualOffset];
        if (recordLen == 0) {
          // End of sector or padding
          break;
        }
        
        // Ensure we have enough data for a complete record
        if (actualOffset + recordLen > sectorData.length) {
          break;
        }
        
        // Extract file information with correct offsets
        int fileLBA = _readInt32(sectorData, actualOffset + 2);
        int fileSize = _readInt32(sectorData, actualOffset + 10);
        int fileFlags = sectorData[actualOffset + 25];
        int fileNameLen = sectorData[actualOffset + 32];
        
        bool isDirectory = (fileFlags & 0x02) == 0x02;
        
        // Get file name
        if (fileNameLen > 0 && actualOffset + 33 + fileNameLen <= sectorData.length) {
          Uint8List nameBytes = sectorData.sublist(actualOffset + 33, actualOffset + 33 + fileNameLen);
          String fileName = latin1.decode(nameBytes);
          
          // Skip "." and ".." entries
          if (fileName != '\u0000' && fileName != '\u0001') {
            // Remove version number if present
            int versionIndex = fileName.lastIndexOf(';');
            if (versionIndex > 0) {
              fileName = fileName.substring(0, versionIndex);
            }
            
            entries.add(DirectoryEntry(
              name: fileName,
              lba: fileLBA,
              size: fileSize,
              isDirectory: isDirectory,
            ));
          }
        }
        
        // Move to next record
        offset += recordLen;
        bytesRead += recordLen;
      }
      
      // Move to next sector
      sectorIndex++;
      
      // If we need more sectors and haven't loaded them yet
      if (sectorIndex >= sectorBuffers.length && bytesRead < dirSize) {
        currentSector += sectorBuffers.length;
        
        // Read next batch of sectors
        sectorReads = [];
        for (int i = 0; i < sectorsNeeded && i < 10; i++) {
          sectorReads.add(_readSectorCached(currentSector + i));
        }
        
        sectorBuffers = await Future.wait(sectorReads);
        sectorIndex = 0;
      }
    }
    
    return entries;
  }
  
  /// Find a file in the root directory
  Future<DirectoryEntry?> findFileInRoot(String fileName) async {
    // Get root directory information
    Map<String, dynamic>? rootDir = await findRootDirectory();
    if (rootDir == null) {
      return null;
    }
    
    // List files in the root directory
    List<DirectoryEntry>? entries = await listDirectory(rootDir['lba'], rootDir['size']);
    if (entries == null) {
      return null;
    }
    
    // Find the file
    String upperFileName = fileName.toUpperCase();
    for (var entry in entries) {
      if (entry.name.toUpperCase() == upperFileName) {
        return entry;
      }
    }
    
    return null; // File not found
  }
  
  /// Find a file at a specific path
  Future<DirectoryEntry?> findFile(String filePath) async {
    // Get root directory information
    Map<String, dynamic>? rootDir = await findRootDirectory();
    if (rootDir == null) {
      return null;
    }
    
    // Normalize the path
    filePath = _normalizePath(filePath);
    List<String> pathParts = filePath.split('/');
    
    if (pathParts.isEmpty) {
      return null;
    }
    
    // If it's just a file in the root directory
    if (pathParts.length == 1) {
      return findFileInRoot(pathParts[0]);
    }
    
    // Navigate through each directory in the path
    int currentDirLBA = rootDir['lba'];
    int currentDirSize = rootDir['size'];
    
    for (int i = 0; i < pathParts.length - 1; i++) {
      String dirName = pathParts[i].toUpperCase();
      
      // Skip empty path segments
      if (dirName.isEmpty) continue;
      
      // List files in the current directory
      List<DirectoryEntry>? entries = await listDirectory(currentDirLBA, currentDirSize);
      if (entries == null) {
        return null;
      }
      
      // Find the directory
      bool found = false;
      for (var entry in entries) {
        if (entry.isDirectory && entry.name.toUpperCase() == dirName) {
          currentDirLBA = entry.lba;
          currentDirSize = entry.size;
          found = true;
          break;
        }
      }
      
      if (!found) {
        return null; // Directory not found
      }
    }
    
    // Find the file in the final directory
    List<DirectoryEntry>? entries = await listDirectory(currentDirLBA, currentDirSize);
    if (entries == null) {
      return null;
    }
    
    // Find the file
    String fileName = pathParts.last.toUpperCase();
    for (var entry in entries) {
      if (!entry.isDirectory && entry.name.toUpperCase() == fileName) {
        return entry;
      }
    }
    
    return null; // File not found
  }
  
  /// Read a file's contents with optimized sector reading
  Future<Uint8List?> readFile(DirectoryEntry file) async {
    if (file.isDirectory) {
      return null; // Can't read directory content
    }
    
    // Return empty array for zero-size files
    if (file.size == 0) {
      return Uint8List(0);
    }
    
    // Calculate how many sectors we need to read
    int sectorsToRead = (file.size + 2047) ~/ 2048; // Ceiling division
    Uint8List fileData = Uint8List(file.size);
    
    // Read sectors in parallel batches to improve performance
    const BATCH_SIZE = 10;
    for (int batchStart = 0; batchStart < sectorsToRead; batchStart += BATCH_SIZE) {
      int batchEnd = (batchStart + BATCH_SIZE < sectorsToRead) ? batchStart + BATCH_SIZE : sectorsToRead;
      
      // Prepare batch of sector reads
      List<Future<Uint8List?>> sectorReads = [];
      for (int i = batchStart; i < batchEnd; i++) {
        sectorReads.add(_readSectorCached(file.lba + i));
      }
      
      // Wait for all sectors in batch to load
      List<Uint8List?> sectorBuffers = await Future.wait(sectorReads);
      
      // Process each sector in the batch
      for (int i = 0; i < sectorBuffers.length; i++) {
        Uint8List? sectorData = sectorBuffers[i];
        if (sectorData == null) {
          return null;
        }
        
        // Calculate how many bytes to read from this sector
        int bytesToRead = ((batchStart + i) == sectorsToRead - 1)
            ? file.size - ((batchStart + i) * 2048)
            : 2048;
        
        // Ensure bytesToRead is positive
        if (bytesToRead <= 0) {
          bytesToRead = 1;
        }
        
        // The actual data starts at the data offset defined in the track
        int dataOffset = _dataTrack.dataOffset;
        if (dataOffset >= sectorData.length) {
          return null;
        }
        
        // Make sure we don't read beyond the sector data
        if (bytesToRead > sectorData.length - dataOffset) {
          bytesToRead = sectorData.length - dataOffset;
        }
        
        // Copy data to our buffer
        int targetOffset = (batchStart + i) * 2048;
        if (targetOffset + bytesToRead > fileData.length) {
          bytesToRead = fileData.length - targetOffset;
        }
        
        if (bytesToRead > 0) {
          fileData.setRange(targetOffset, targetOffset + bytesToRead, 
                           sectorData.sublist(dataOffset, dataOffset + bytesToRead));
        }
      }
    }
    
    return fileData;
  }
  
  /// Helper method to read the content of a file by path
  Future<Uint8List?> readFileByPath(String filePath) async {
    DirectoryEntry? file = await findFile(filePath);
    if (file == null) {
      return null;
    }
    
    return readFile(file);
  }
  
  /// Parse SYSTEM.CNF file to find the executable path
  Future<String?> findExecutablePath() async {
    // Try to find SYSTEM.CNF in the root directory
    DirectoryEntry? systemCnf = await findFileInRoot('SYSTEM.CNF');
    if (systemCnf == null) {
      return null;
    }
    
    // Read the file
    Uint8List? cnfData = await readFile(systemCnf);
    if (cnfData == null) {
      return null;
    }
    
    // Convert to string and parse
    String cnfContent = ascii.decode(cnfData, allowInvalid: true);
    
    // Extract executable path from BOOT= line
    RegExp bootRegExp = RegExp(r'BOOT\s*=\s*([^\s;]+)', caseSensitive: false);
    Match? match = bootRegExp.firstMatch(cnfContent);
    
    if (match != null && match.groupCount >= 1) {
      String execPath = match.group(1)!.trim();
      return execPath;
    }
    
    return null;
  }
  
  /// Normalize a PlayStation executable path
  String _normalizePath(String path) {
    String result = path;
    
    // Remove cdrom: prefix
    if (result.toLowerCase().startsWith('cdrom:')) {
      result = result.substring(6);
    }
    
    // Standardize slashes
    result = result.replaceAll('\\', '/');
    
    // Remove leading slash if present
    if (result.startsWith('/')) {
      result = result.substring(1);
    }
    
    // Remove version number if present
    int versionIndex = result.lastIndexOf(';');
    if (versionIndex > 0) {
      result = result.substring(0, versionIndex);
    }
    
    return result.trim();
  }
}