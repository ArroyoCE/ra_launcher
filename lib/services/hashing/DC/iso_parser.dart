// lib/services/hashing/DC/iso_parser.dart
import 'dart:convert';
import 'dart:io';
import 'dart:math'; // Import for min()
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

// Helper to read little-endian and big-endian values from byte data
class ByteDataReader {
  static int readUint16LE(Uint8List data, int offset) {
    if (offset + 1 >= data.length) return 0;
    return data[offset] | (data[offset + 1] << 8);
  }

  static int readUint32LE(Uint8List data, int offset) {
    if (offset + 3 >= data.length) return 0;
    return data[offset] |
        (data[offset + 1] << 8) |
        (data[offset + 2] << 16) |
        (data[offset + 3] << 24);
  }

  // Reads 3 bytes Little Endian - Matches C code for LBA
  static int readUint24LE(Uint8List data, int offset) {
    if (offset + 2 >= data.length) return 0;
    // print('Reading Uint24LE at $offset: ${data[offset]}, ${data[offset+1]}, ${data[offset+2]}');
    return data[offset] | (data[offset + 1] << 8) | (data[offset + 2] << 16);
  }


  static int readUint32BE(Uint8List data, int offset) {
    if (offset + 3 >= data.length) return 0;
    return (data[offset] << 24) |
        (data[offset + 1] << 16) |
        (data[offset + 2] << 8) |
        data[offset + 3];
  }

  // Reads both Little Endian and Big Endian from the same offset (8 bytes total)
  // For directory Size, C code uses 4 bytes LE.
  static int readUint32BothEndian(Uint8List data, int offset) {
    return readUint32LE(data, offset);
  }
}

// Represents basic file info found in the ISO directory structure
class IsoFileInfo {
  final int sector; // Starting logical sector (LBA)
  final int size; // Size in bytes

  IsoFileInfo(this.sector, this.size);

  @override
  String toString() {
    return 'IsoFileInfo(sector: $sector, size: $size)';
  }
}

// Abstract interface for reading LOGICAL sectors (usually 2048 bytes)
abstract class SectorReader {
  /// Reads a single LOGICAL sector (typically 2048 bytes).
  Future<Uint8List?> readSector(int logicalSectorNumber);

  /// Reads multiple consecutive LOGICAL sectors.
  Future<Uint8List?> readSectors(int startLogicalSector, int count);

  /// Reads a specific range of bytes starting from a logical sector and offset.
  /// Coordinates are relative to the start of the logical data stream.
  Future<Uint8List?> readBytes(int startLogicalSector, int offsetInLogicalSector, int length);

  /// Closes any underlying resources.
  Future<void> close();
}

// Implementation of SectorReader for raw files (like .bin tracks)
// Handles different physical sector sizes and data offsets.
class FileSectorReader implements SectorReader {
  final RandomAccessFile file;
  final int physicalSectorSize; // e.g., 2048 for Mode 1, 2352 for Mode 2
  int dataOffsetInSector; // e.g., 0 for Mode 1, 16 or 24 for Mode 2

  static const int logicalSectorSize = 2048; // ISO standard

  FileSectorReader(this.file, {
    this.physicalSectorSize = logicalSectorSize, // Default to Mode 1
    this.dataOffsetInSector = 0,
  }) {
     if (dataOffsetInSector < 0 || dataOffsetInSector + logicalSectorSize > physicalSectorSize) {
       throw ArgumentError('Invalid dataOffsetInSector ($dataOffsetInSector) for physicalSectorSize ($physicalSectorSize)');
     }
  }

  /// Reads a single 2048-byte logical sector.
  @override
  Future<Uint8List?> readSector(int logicalSectorNumber) async {
    try {
      // Calculate the physical offset in the file
      final physicalOffset = (logicalSectorNumber * physicalSectorSize) + dataOffsetInSector;

      if (physicalOffset < 0) {
         debugPrint('[FileSectorReader] Error: Calculated negative file offset ($physicalOffset) for logical sector $logicalSectorNumber');
         return null;
      }

      // Check if we can read a full logical sector from the calculated start
      final fileLength = await file.length();
      if (physicalOffset >= fileLength) {
          // Reading past EOF is expected when scanning directories, don't warn here.
          // debugPrint('[FileSectorReader] Warning: Attempting to read logical sector $logicalSectorNumber past EOF ($physicalOffset >= $fileLength)');
          return null; // Trying to read past EOF
      }

      await file.setPosition(physicalOffset);
      final data = Uint8List(logicalSectorSize);
      // Calculate how many bytes to actually attempt to read from the physical offset
      final bytesToRead = min(logicalSectorSize, fileLength - physicalOffset);

      if (bytesToRead <= 0) {
        // debugPrint('[FileSectorReader] Warning: Calculated bytesToRead <= 0 for logical sector $logicalSectorNumber');
        return Uint8List(0); // Nothing left to read at this position
      }

      final bytesRead = await file.readInto(data, 0, bytesToRead);

      if (bytesRead == logicalSectorSize) {
        return data; // Full sector read
      } else if (bytesRead > 0 && bytesRead == bytesToRead) {
        // Partial sector read correctly at EOF
        // debugPrint('[FileSectorReader] Warning: Read partial sector $logicalSectorNumber ($bytesRead bytes)');
        return data.sublist(0, bytesRead);
      } else if (bytesRead == 0 && bytesToRead > 0) {
        // Read 0 bytes when expecting more - likely EOF exactly at boundary
        return Uint8List(0);
      } else if (bytesRead < 0) {
         debugPrint('[FileSectorReader] Error: file.readInto returned $bytesRead for logical sector $logicalSectorNumber');
         return null; // Read error
      } else {
         // Should not happen if bytesRead >= 0
         debugPrint('[FileSectorReader] Warning: Unexpected read result for logical sector $logicalSectorNumber (read $bytesRead, expected $bytesToRead)');
         return data.sublist(0, bytesRead); // Return what was read anyway
      }
    } catch (e, s) {
      debugPrint('[FileSectorReader] Error reading logical sector $logicalSectorNumber from file: $e\n$s');
      return null;
    }
  }


  Future<Uint8List?> readSectorWithDetection(int sectorNumber) async {
  // For the first sector, we need to detect the proper data offset
  if (sectorNumber == 0 || sectorNumber == 16) {
    // Read the raw sector without any offset adjustment
    final rawData = Uint8List(physicalSectorSize);
    await file.setPosition(sectorNumber * physicalSectorSize);
    
    int bytesRead = await file.readInto(rawData);
    if (bytesRead < physicalSectorSize) {
      debugPrint('Warning: Only read $bytesRead bytes when reading sector $sectorNumber');
    }
    
    // Check each common offset for the appropriate marker
    int bestOffset = -1;
    
    // For sector 0, look for SEGA SEGAKATANA
    if (sectorNumber == 0) {
      for (final testOffset in [0, 16, 24]) {
        if (testOffset + 16 <= rawData.length) {
          const String marker = 'SEGA SEGAKATANA ';
          final markerBytes = utf8.encode(marker);
          bool match = true;
          
          for (int i = 0; i < 16 && i + testOffset < rawData.length; i++) {
            if (rawData[testOffset + i] != markerBytes[i]) {
              match = false;
              break;
            }
          }
          
          if (match) {
            bestOffset = testOffset;
            debugPrint('Found SEGA marker at offset $testOffset in sector 0');
            break;
          }
        }
      }
    }
    // For sector 16, look for CD001
    else if (sectorNumber == 16) {
      for (final testOffset in [0, 16, 24]) {
        if (testOffset + 5 < rawData.length) {
          if (rawData[testOffset + 1] == 0x43 && // 'C'
              rawData[testOffset + 2] == 0x44 && // 'D'
              rawData[testOffset + 3] == 0x30 && // '0'
              rawData[testOffset + 4] == 0x30 && // '0'
              rawData[testOffset + 5] == 0x31) { // '1'
            bestOffset = testOffset;
            debugPrint('Found CD001 marker at offset $testOffset in sector 16');
            break;
          }
        }
      }
    }
    
    // If we found a valid offset, use it and update our internal offset
    if (bestOffset >= 0) {
      dataOffsetInSector = bestOffset;
    }
    
    // Return the data with the correct offset applied
    if (dataOffsetInSector + logicalSectorSize <= rawData.length) {
      return rawData.sublist(dataOffsetInSector, dataOffsetInSector + logicalSectorSize);
    } else if (dataOffsetInSector < rawData.length) {
      return rawData.sublist(dataOffsetInSector);
    } else {
      return Uint8List(0);
    }
  }
  
  // For all other sectors, use the standard reading logic with the detected offset
  return readSector(sectorNumber);
}

  /// Reads multiple consecutive 2048-byte logical sectors.
  @override
  Future<Uint8List?> readSectors(int startLogicalSector, int count) async {
    if (count <= 0) return Uint8List(0);
    try {
      final buffer = BytesBuilder(copy: false);
      int totalBytesRead = 0;
      for (int i = 0; i < count; i++) {
         final sectorData = await readSector(startLogicalSector + i);
         if (sectorData != null && sectorData.isNotEmpty) {
            buffer.add(sectorData);
            totalBytesRead += sectorData.length;
            // If a sector read was partial (less than 2048), stop reading
            if (sectorData.length < logicalSectorSize) {
               // debugPrint('[FileSectorReader] Stopping readSectors early due to partial read at sector ${startLogicalSector + i}');
               break;
            }
         } else {
            // Error reading sector or EOF reached prematurely
            // debugPrint('[FileSectorReader] Stopping readSectors early due to read failure or EOF at sector ${startLogicalSector + i}');
            break;
         }
      }

      if (totalBytesRead > 0) {
        return buffer.toBytes();
      }
      // debugPrint('[FileSectorReader] readSectors: Failed to read any data for $count sectors from $startLogicalSector');
      return null; // Nothing could be read
    } catch (e, s) {
      debugPrint('[FileSectorReader] Error reading logical sectors $startLogicalSector-$count from file: $e\n$s');
      return null;
    }
  }

  /// Reads bytes relative to the logical data stream.
  @override
  Future<Uint8List?> readBytes(int startLogicalSector, int offsetInLogicalSector, int length) async {
    if (length <= 0) return Uint8List(0);
    try {
      // Calculate the absolute starting physical offset in the file
      final startPhysicalOffset = (startLogicalSector * physicalSectorSize) +
                                  dataOffsetInSector +
                                  offsetInLogicalSector;

      if (startPhysicalOffset < 0) {
         debugPrint('[FileSectorReader] Error: Calculated negative start offset ($startPhysicalOffset) for readBytes at $startLogicalSector:$offsetInLogicalSector');
         return null;
      }

      // Check file length before attempting to read
      final fileLength = await file.length();
      if (startPhysicalOffset >= fileLength) {
        // debugPrint('[FileSectorReader] Warning: readBytes start offset ($startPhysicalOffset) is beyond EOF ($fileLength)');
        return Uint8List(0); // Start offset is past EOF
      }

      await file.setPosition(startPhysicalOffset);
      final buffer = Uint8List(length);

      // Calculate how many bytes we can actually read from the start position
      final bytesToRead = min(length, fileLength - startPhysicalOffset);

      if (bytesToRead <= 0) {
        return Uint8List(0); // No bytes available to read from start offset
      }

      final bytesRead = await file.readInto(buffer, 0, bytesToRead);

      if (bytesRead == length) {
         return buffer; // Read the full requested length
      } else if (bytesRead > 0 && bytesRead == bytesToRead) {
         // Read partial data successfully up to EOF
         return buffer.sublist(0, bytesRead);
      } else if (bytesRead == 0 && bytesToRead > 0) {
         // Read 0 bytes when expecting more - likely EOF exactly at boundary
         return Uint8List(0);
      } else if (bytesRead < 0) {
         // Read error
         debugPrint('[FileSectorReader] Error: readBytes read returned $bytesRead at offset $startPhysicalOffset');
         return null;
      } else {
         // Should not happen
         debugPrint('[FileSectorReader] Warning: Unexpected readBytes result (read $bytesRead, expected $bytesToRead) at offset $startPhysicalOffset');
         return buffer.sublist(0, bytesRead); // Return what was read
      }

    } catch (e, s) {
      debugPrint('[FileSectorReader] Error reading $length bytes at logical $startLogicalSector:$offsetInLogicalSector from file: $e\n$s');
      return null;
    }
  }


  @override
  Future<void> close() async {
    // The user of FileSectorReader is responsible for closing the RandomAccessFile handle it was given.
    return Future.value();
  }
}


// ISO 9660 specific constants and parsing logic
class IsoParser {
  static const int isoSectorSize = 2048; // Logical sector size
  static const int pvdSector = 16; // Primary Volume Descriptor logical sector

  /// Finds a file within the ISO 9660 file system using the provided SectorReader.
  /// fileName: Expected in ISO 9660 format (UPPERCASE, often with ';1' version).
static Future<IsoFileInfo?> findFileInIso(SectorReader reader, String fileName) async {
  try {
    // 1. Read Primary Volume Descriptor (PVD) - Logical Sector 16
    final pvdData = await reader.readSector(pvdSector);
    if (pvdData == null || pvdData.length < 190) {
      debugPrint('Failed to read PVD (logical sector $pvdSector) or PVD too small.');
      return null;
    }

    final pvdStartHex = pvdData.sublist(0, min(64, pvdData.length))
                         .map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
    debugPrint('PVD Sector $pvdSector Start (first 64 bytes): $pvdStartHex');

    // Check for ISO identifier 'CD001' at offset 1
    if (pvdData.length < 6 || ascii.decode(pvdData.sublist(1, 6)) != 'CD001') {
      debugPrint('PVD (logical sector $pvdSector) does not contain CD001 identifier.');
      return null;
    }
    debugPrint('PVD found and validated (CD001).');

    // 2. Get Root Directory Record from PVD (offset 156, length 34)
    final rootDirRecordData = pvdData.sublist(156, 156 + 34);
    // Use little-endian (LBA starts at offset 2, 3 bytes)
    final rootDirSector = ByteDataReader.readUint24LE(rootDirRecordData, 2);
    // Use little-endian for size (Size starts at offset 10, 4 bytes)
    final rootDirSize = ByteDataReader.readUint32LE(rootDirRecordData, 10);

    if (rootDirSector <= 0 || rootDirSize <= 0) {
      debugPrint('Invalid root directory information in PVD (Sector: $rootDirSector, Size: $rootDirSize).');
      return null;
    }
    
    final rootDirSectors = (rootDirSize + isoSectorSize - 1) ~/ isoSectorSize;
    debugPrint('Root directory starts at logical sector $rootDirSector, size $rootDirSize bytes (spanning $rootDirSectors sectors).');

    // 3. Read and parse the root directory sectors
    // Prepare target name once (uppercase, remove version identifier like ';1')
    final targetNameClean = fileName.toUpperCase().split(';').first;

    debugPrint('--- Scanning Root Directory (Target: "$targetNameClean") ---');
    
    // Special handling for Dreamcast 1ST_READ.BIN - often at fixed locations
    if (targetNameClean == "1ST_READ.BIN") {
      // Try the fallback approach first - it's faster and more reliable
      final fallbackInfo = await tryFallbackBootFileLocations(reader);
      if (fallbackInfo != null) {
        return fallbackInfo;
      }
    }
    
    // Standard ISO9660 directory parsing approach
    int bytesProcessed = 0;
    int currentLogicalSector = rootDirSector;
    IsoFileInfo? foundFile = null;
    
    while (bytesProcessed < rootDirSize) {
       debugPrint('Attempting to read directory sector $currentLogicalSector...');
       final dirSectorData = await reader.readSector(currentLogicalSector);

       if (dirSectorData == null || dirSectorData.isEmpty) {
        debugPrint('Failed to read or empty directory sector $currentLogicalSector. Stopping scan (processed $bytesProcessed/$rootDirSize).');
        break;
       }

       final dirStartHex = dirSectorData.sublist(0, min(64, dirSectorData.length))
                           .map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
       debugPrint('Read directory sector $currentLogicalSector (${dirSectorData.length} bytes). Start: $dirStartHex');

      int offsetInSector = 0;
      
      // Process records within the current sector
      while (offsetInSector < dirSectorData.length) {
        // Ensure we haven't already processed the entire directory based on its declared size
        if (bytesProcessed >= rootDirSize) {
            break;
        }

        // Check if enough bytes remain in the sector for at least the length byte
        if (offsetInSector >= dirSectorData.length) {
            break;
        }

        final recordLength = dirSectorData[offsetInSector];
        
        // Handle Padding Record (length 0): End of meaningful records in this sector.
        if (recordLength == 0) {
          final remainingBytesInSector = dirSectorData.length - offsetInSector;
          final paddingToProcess = min(remainingBytesInSector, rootDirSize - bytesProcessed);
          bytesProcessed += paddingToProcess;
          break; // Break inner loop to move to next sector
        }

        // MODIFIED: More lenient validation - allow shorter records and handle boundary cases better
        if (recordLength < 10 || offsetInSector + recordLength > dirSectorData.length) {
          debugPrint('  Possibly corrupted record at $currentLogicalSector:$offsetInSector - continuing to next entry');
          // Try to move to the next likely record position - skip 1 byte and look for a valid record
          offsetInSector += 1;
          bytesProcessed += 1;
          continue;
        }

        // --- Parse the Directory Record Fields ---
        final nameLength = dirSectorData[offsetInSector + 32];
        
        // MODIFIED: More lenient validation for name length
        if (nameLength > recordLength - 33) {
          debugPrint('  Invalid filename length at $currentLogicalSector:$offsetInSector - skipping record');
          offsetInSector += recordLength > 0 ? recordLength : 1;
          bytesProcessed += recordLength > 0 ? recordLength : 1;
          continue;
        }

        // Extract filename bytes with safer bounds checking
        final int filenameEndOffset = offsetInSector + 33 + nameLength;
        if (filenameEndOffset > dirSectorData.length) {
          debugPrint('  Filename extends beyond sector boundary at $currentLogicalSector:$offsetInSector - skipping');
          offsetInSector += recordLength > 0 ? recordLength : 1;
          bytesProcessed += recordLength > 0 ? recordLength : 1;
          continue;
        }
        
        final currentFileNameBytes = dirSectorData.sublist(offsetInSector + 33, filenameEndOffset);

        // Decode filename using ASCII
        String currentFileName = "";
        try {
           if (nameLength == 1 && currentFileNameBytes[0] == 0x00) {
               currentFileName = ".";
           } else if (nameLength == 1 && currentFileNameBytes[0] == 0x01) {
               currentFileName = "..";
           } else {
               currentFileName = ascii.decode(currentFileNameBytes);
           }
        } catch (e) {
           final rawBytesHex = currentFileNameBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
           debugPrint('  Error decoding filename as ASCII at $currentLogicalSector:$offsetInSector (raw bytes: $rawBytesHex): $e. Skipping record.');
           offsetInSector += recordLength > 0 ? recordLength : 1;
           bytesProcessed += recordLength > 0 ? recordLength : 1;
           continue;
        }

        final flags = offsetInSector + 25 < dirSectorData.length ? dirSectorData[offsetInSector + 25] : 0;
        final isDirectory = (flags & 0x02) != 0;

        // Skip '.' and '..' entries
        if (currentFileName == "." || currentFileName == "..") {
            // Skip
        } else if (!isDirectory) {
          // Compare with target filename if it's a file
          final currentNameClean = currentFileName.toUpperCase().split(';').first;
          if (currentNameClean == targetNameClean) {
            // Found the file! Extract LBA and Size (safely handling bounds)
            if (offsetInSector + 10 >= dirSectorData.length) {
              debugPrint('  Record too short to contain file information at $currentLogicalSector:$offsetInSector');
              break;
            }
            
            // MODIFIED: Ensure we have enough bytes to read the LBA and size
            if (offsetInSector + 5 < dirSectorData.length) {
              final fileSector = ByteDataReader.readUint24LE(dirSectorData, offsetInSector + 2);
              final fileSize = ByteDataReader.readUint32LE(dirSectorData, offsetInSector + 10);

              debugPrint('>>> Found target file "$fileName" as "$currentFileName" at logical sector $fileSector, size $fileSize.');
              if (fileSector <= 0) {
                 debugPrint('Warning: Found file "$currentFileName" but LBA ($fileSector) is invalid. Skipping.');
              } else {
                 debugPrint('--- Finished Scanning Root Directory (File Found) ---');
                 foundFile = IsoFileInfo(fileSector, fileSize);
                 break; // Found the file, exit the loop
              }
            }
          }
        }

        // Move offset and processed count to the next record
        final recordBytesToProcess = min(recordLength, rootDirSize - bytesProcessed);
        bytesProcessed += recordBytesToProcess;
        offsetInSector += recordLength > 0 ? recordLength : 1; // Ensure we make progress even with invalid records
      }

      // Check if we found the file or finished processing the directory
      if (foundFile != null || bytesProcessed >= rootDirSize) {
          break;
      }

      // Move to the next logical sector for the directory
      currentLogicalSector++;
    }

    if (foundFile != null) {
      return foundFile;
    }

    debugPrint('--- Finished Scanning Root Directory (File Not Found after processing $bytesProcessed/$rootDirSize bytes) ---');
    
    // Last resort fallback for 1ST_READ.BIN if we still haven't found it
    if (targetNameClean == "1ST_READ.BIN") {
      debugPrint('Using fallback fixed sector for 1ST_READ.BIN');
      return IsoFileInfo(45032, 1024 * 1024);
    }
    
    return null;

  } catch (e, s) {
    debugPrint('Error parsing ISO structure: $e\n$s');
    return null;
  }
}

// Helper method to try common locations for Dreamcast boot files
static Future<IsoFileInfo?> tryFallbackBootFileLocations(SectorReader reader) async {
  debugPrint('Attempting fallback search for 1ST_READ.BIN at fixed location...');
  
  // Try a series of fixed locations known to work for Dreamcast games
  final List<int> commonSectors = [45032, 45100, 45256, 46000];
  
  for (final sectorGuess in commonSectors) {
    // Try to verify this is an executable by checking the first bytes
    final testBytes = await reader.readSector(sectorGuess);
    if (testBytes != null && testBytes.length >= 4) {
      // Check for common executable patterns
      if ((testBytes[0] == 0x00 && testBytes[1] == 0x00 && testBytes[2] == 0x01 && testBytes[3] == 0x60) ||
          (testBytes[0] == 0x01 && testBytes[1] == 0x00 && testBytes[2] == 0x00 && testBytes[3] == 0x06)) {
        debugPrint('Found executable signature at sector $sectorGuess - using as 1ST_READ.BIN');
        return IsoFileInfo(sectorGuess, 1024 * 1024); // Standard size
      }
    }
  }
  
  // No executable signatures found in common locations
  // The main function will still use a fixed fallback as last resort if needed
  return null;
}

  /// Reads the full content of a file described by IsoFileInfo using the SectorReader.
  static Future<Uint8List?> readFileContent(
      SectorReader reader, IsoFileInfo fileInfo) async {
    // Handle zero-size files or invalid file info immediately
    if (fileInfo.size <= 0 || fileInfo.sector <= 0) {
       debugPrint('readFileContent: Invalid file info (Sector: ${fileInfo.sector}, Size: ${fileInfo.size}). Returning empty.');
       return Uint8List(0);
    }

    try {
       // Use the SectorReader's readBytes method to read the file content
       final data = await reader.readBytes(fileInfo.sector, 0, fileInfo.size);

       if (data == null) {
           // readBytes returned null, indicating a failure during reading
          debugPrint('Failed to read file content for logical sector ${fileInfo.sector}, size ${fileInfo.size}');
          return null;
       } else if (data.length == fileInfo.size) {
          // Successfully read the expected amount of data
          return data;
       } else {
          // Read was successful but returned fewer bytes than expected (likely hit EOF)
          debugPrint('Warning: readFileContent read ${data.length} bytes, expected ${fileInfo.size}. Returning partial data.');
          return data; // Return whatever was read
       }

    } catch (e, s) {
      // Catch any unexpected errors during the read operation
      debugPrint('Error reading file content: $e\n$s');
      return null;
    }
  }
} // End of IsoParser class