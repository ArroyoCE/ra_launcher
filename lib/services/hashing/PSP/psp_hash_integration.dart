import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:retroachievements_organizer/services/hashing/PSP/isolate_psp_chd_processor.dart';


class PspHashIntegration {
  /// Hash PSP files in the provided folders
  Future<Map<String, String>> hashPspFilesInFolders(List<String> folders) async {
    final Map<String, String> hashes = {};
    final validExtensions = ['.iso', '.bin', '.chd', '.pbp'];
    
    // List to collect all files that need hashing
    final List<String> filesToHash = [];
    
    // First, collect all files to hash
    for (final folder in folders) {
      try {
        final directory = Directory(folder);
        if (!directory.existsSync()) continue;
        
        await for (final entity in directory.list(recursive: true)) {
          if (entity is File) {
            final ext = path.extension(entity.path).toLowerCase();
            if (validExtensions.contains(ext)) {
              filesToHash.add(entity.path);
            }
          }
        }
      } catch (e) {
        debugPrint('Error scanning folder $folder: $e');
      }
    }
    
    // Update progress with total files found
    final int totalFiles = filesToHash.length;
    debugPrint('Found $totalFiles PSP files to hash');
    
    // Process each file
    for (final filePath in filesToHash) {
      try {
        final ext = path.extension(filePath).toLowerCase();
        String? fileHash;
        
        // Choose the appropriate hashing method based on file extension
        if (ext == '.chd') {
          // Use the CHD processor for CHD files
          // This will automatically use the PSP-specific processor for PSP CHDs
          fileHash = await IsolatePspChdProcessor.processPspChd(filePath);
        
        } else {
          // For ISO and BIN files
          fileHash = await hashPspDisc(filePath);
        }
        
        // Add to results if hash was successful
        if (fileHash != null) {
          hashes[filePath] = fileHash;
          debugPrint('Hashed PSP file: $filePath -> $fileHash');
        }
      } catch (e) {
        debugPrint('Error hashing PSP file $filePath: $e');
      }
    }
    
    debugPrint('PSP hashing complete: ${hashes.length} files hashed');
    return hashes;
  }
  
  
  /// Hash a PSP disc (ISO or BIN)
  Future<String?> hashPspDisc(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        return null;
      }
      
      // Open file and prepare to read sectors
      final raf = await file.open(mode: FileMode.read);
      
      try {
        // First find the PARAM.SFO file
        final paramSfoData = await findAndReadParamSfo(raf);
        if (paramSfoData == null) {
          debugPrint('Could not find PARAM.SFO in $filePath');
          return null;
        }
        
        // Then find the EBOOT.BIN file
        final ebootBinData = await findAndReadEbootBin(raf);
        if (ebootBinData == null) {
          debugPrint('Could not find EBOOT.BIN in $filePath');
          return null;
        }
        
        // Hash both files together
        final bytes = [...paramSfoData, ...ebootBinData];
        final digest = md5.convert(bytes);
        return digest.toString();
      } finally {
        await raf.close();
      }
    } catch (e) {
      debugPrint('Error hashing PSP disc: $e');
      return null;
    }
  }
  
  /// Find and read the PARAM.SFO file from a PSP disc
  Future<Uint8List?> findAndReadParamSfo(RandomAccessFile raf) async {
    // Start by searching for the ISO9660 primary volume descriptor
    final pvdSector = await readSector(raf, 16);
    
    // Check for ISO9660 identifier
    if (!checkIso9660Identifier(pvdSector)) {
      return null;
    }
    
    // Get root directory record
    final rootDirEntry = getRootDirectoryEntry(pvdSector);
    if (rootDirEntry == null) {
      return null;
    }
    
    // Find PSP_GAME directory
    final pspGameDir = await findDirectoryEntry(raf, rootDirEntry, 'PSP_GAME');
    if (pspGameDir == null) {
      return null;
    }
    
    // Find PARAM.SFO file
    final paramSfoEntry = await findFileEntry(raf, pspGameDir, 'PARAM.SFO');
    if (paramSfoEntry == null) {
      return null;
    }
    
    // Read PARAM.SFO file
    return await readFile(raf, paramSfoEntry);
  }
  
  /// Find and read the EBOOT.BIN file from a PSP disc
  Future<Uint8List?> findAndReadEbootBin(RandomAccessFile raf) async {
    // Start by searching for the ISO9660 primary volume descriptor
    final pvdSector = await readSector(raf, 16);
    
    // Check for ISO9660 identifier
    if (!checkIso9660Identifier(pvdSector)) {
      return null;
    }
    
    // Get root directory record
    final rootDirEntry = getRootDirectoryEntry(pvdSector);
    if (rootDirEntry == null) {
      return null;
    }
    
    // Find PSP_GAME directory
    final pspGameDir = await findDirectoryEntry(raf, rootDirEntry, 'PSP_GAME');
    if (pspGameDir == null) {
      return null;
    }
    
    // Find SYSDIR directory
    final sysdirEntry = await findDirectoryEntry(raf, pspGameDir, 'SYSDIR');
    if (sysdirEntry == null) {
      return null;
    }
    
    // Find EBOOT.BIN file
    final ebootBinEntry = await findFileEntry(raf, sysdirEntry, 'EBOOT.BIN');
    if (ebootBinEntry == null) {
      return null;
    }
    
    // Read EBOOT.BIN file
    return await readFile(raf, ebootBinEntry);
  }
  
  /// Read a sector from a file at the given sector number
  Future<Uint8List> readSector(RandomAccessFile raf, int sector, [int sectorSize = 2048]) async {
    await raf.setPosition(sector * sectorSize);
    final buffer = Uint8List(sectorSize);
    final bytesRead = await raf.readInto(buffer);
    return buffer.sublist(0, bytesRead);
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
  
  /// Find a directory entry with the given name in a directory
  Future<Map<String, dynamic>?> findDirectoryEntry(
      RandomAccessFile raf, Map<String, dynamic> dirEntry, String name) async {
    final dirSector = dirEntry['lba'] as int;
    final dirSize = dirEntry['size'] as int;
    
    // Read the directory sector
    final dirData = await readSector(raf, dirSector);
    
    // Parse directory entries
    int offset = 0;
    while (offset < dirSize && offset < dirData.length) {
      final recordLength = dirData[offset];
      if (recordLength == 0) {
        offset++;
        continue;
      }
      
      // Get the name length
      final nameLength = dirData[offset + 32];
      if (nameLength == 0) {
        offset += recordLength;
        continue;
      }
      
      // Skip special entries (. and ..)
      if (nameLength == 1 && (dirData[offset + 33] == 0 || dirData[offset + 33] == 1)) {
        offset += recordLength;
        continue;
      }
      
      // Get the name
      String entryName = '';
      for (int i = 0; i < nameLength; i++) {
        // Handle semicolons which mark version numbers (;1)
        if (dirData[offset + 33 + i] == 0x3B) break;
        entryName += String.fromCharCode(dirData[offset + 33 + i]);
      }
      
      // Check if this is the entry we're looking for
      if (entryName.toUpperCase() == name.toUpperCase()) {
        final fileFlags = dirData[offset + 25];
        final isDirectory = (fileFlags & 0x02) != 0;
        
        if (isDirectory) {
          final lba = dirData[offset + 2] | 
                     (dirData[offset + 3] << 8) | 
                     (dirData[offset + 4] << 16) | 
                     (dirData[offset + 5] << 24);
                     
          final size = dirData[offset + 10] | 
                      (dirData[offset + 11] << 8) | 
                      (dirData[offset + 12] << 16) | 
                      (dirData[offset + 13] << 24);
                      
          return {
            'lba': lba,
            'size': size,
            'isDirectory': true,
          };
        }
      }
      
      offset += recordLength;
    }
    
    // If we didn't find it in the first sector, we might need to read more sectors
    // This is a simplified implementation; a complete one would handle directory entries
    // that span multiple sectors
    
    return null;
  }
  
  /// Find a file entry with the given name in a directory
  Future<Map<String, dynamic>?> findFileEntry(
      RandomAccessFile raf, Map<String, dynamic> dirEntry, String name) async {
    final dirSector = dirEntry['lba'] as int;
    final dirSize = dirEntry['size'] as int;
    
    // Calculate how many sectors to read
    final sectorsToRead = (dirSize + 2047) ~/ 2048; // Round up
    
    // Read all sectors that make up the directory
    for (int i = 0; i < sectorsToRead; i++) {
      final sectorData = await readSector(raf, dirSector + i);
      
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
          
          if (!isDirectory) {
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
              'isDirectory': false,
            };
          }
        }
        
        offset += recordLength;
      }
    }
    
    return null;
  }
  
  /// Read a file from the disc
  Future<Uint8List?> readFile(RandomAccessFile raf, Map<String, dynamic> fileEntry) async {
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
      final sectorData = await readSector(raf, lba + i);
      buffer.setRange(bytesRead, bytesRead + 2048, sectorData);
      bytesRead += 2048;
    }
    
    // Read the remainder
    if (remainder > 0) {
      final sectorData = await readSector(raf, lba + fullSectors);
      buffer.setRange(bytesRead, bytesRead + remainder, sectorData.sublist(0, remainder));
    }
    
    return buffer;
  }
}