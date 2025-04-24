// lib/services/hashing/ps2/ps2_filesystem.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Helper class to store file information within the PS2 filesystem
class Ps2FileInfo {
  final int lba; // Logical Block Address (Sector)
  final int size; // Size in bytes

  Ps2FileInfo({required this.lba, required this.size});
}

/// Helper class to store directory entry information within the PS2 filesystem
class Ps2DirectoryEntry {
  final String name;
  final int lba;
  final int size;
  final bool isDirectory;

  Ps2DirectoryEntry({
    required this.name,
    required this.lba,
    required this.size,
    required this.isDirectory,
  });
}

/// Class to handle reading the PS2 ISO9660 filesystem from ISO/BIN files
class Ps2FilesystemReader {
  final File _isoFile;
  static const int _sectorSize = 2048; // Standard ISO sector size

  Ps2FilesystemReader(this._isoFile);

  /// Find and read a file from the ISO filesystem by its path.
  ///
  /// Returns the file content as Uint8List, or null if not found or error occurs.
  Future<Uint8List?> findAndReadFile(String filePath) async {
    try {
      // Find the root directory sector first
      final rootDirSector = await _findRootDirectorySector();
      if (rootDirSector == null) {
        debugPrint('Could not find root directory sector in ${_isoFile.path}');
        return null;
      }

      // Find the file entry within the directory structure
      final fileInfo = await _findFileInDirectory(rootDirSector, filePath);
      if (fileInfo == null) {
        debugPrint('Could not find file entry for $filePath in ${_isoFile.path}');
        return null;
      }

      // Read the actual file data based on its LBA and size
      return await _readSectors(fileInfo.lba, fileInfo.size);
    } catch (e, stackTrace) {
      debugPrint('Error finding/reading file $filePath in ${_isoFile.path}: $e');
      debugPrint('Stack trace: $stackTrace');
      return null;
    }
  }

  /// Finds the starting sector (LBA) of the root directory in the ISO file.
  ///
  /// Returns the LBA as an integer, or null if not found or error occurs.
  Future<int?> _findRootDirectorySector() async {
    try {
      // In ISO9660, the Primary Volume Descriptor (PVD) starts at sector 16
      final pvdData = await _readSector(16);
      if (pvdData == null) {
        debugPrint('Failed to read PVD sector (16) from ${_isoFile.path}');
        return null;
      }
       if (pvdData.length < 170) { // Need at least up to root dir size
         debugPrint('PVD data too short in ${_isoFile.path}');
         return null;
       }


      // Check for the standard ISO9660 identifier "CD001" at byte offset 1
      if (pvdData[1] != 0x43 || // C
          pvdData[2] != 0x44 || // D
          pvdData[3] != 0x30 || // 0
          pvdData[4] != 0x30 || // 0
          pvdData[5] != 0x31) { // 1
        debugPrint('ISO9660 identifier "CD001" not found in PVD of ${_isoFile.path}');
        return null; // Not a standard ISO9660 filesystem
      }

      // Extract the root directory's LBA (stored as 32-bit little-endian at offset 158 in PVD)
      // Directory entry structure starts at byte 156, LBA is at offset +2
      final rootDirLba = ByteData.view(pvdData.buffer).getUint32(156 + 2, Endian.little);

      return rootDirLba;
    } catch (e, stackTrace) {
      debugPrint('Error finding root directory sector in ${_isoFile.path}: $e');
      debugPrint('Stack trace: $stackTrace');
      return null;
    }
  }

  /// Recursively finds a file or directory entry within a given directory sector.
  ///
  /// [sectorLba]: The starting LBA of the directory to search.
  /// [targetPath]: The relative path (using '/') of the file/directory to find.
  /// Returns a [Ps2FileInfo] containing LBA and size, or null if not found.
  Future<Ps2FileInfo?> _findFileInDirectory(int sectorLba, String targetPath) async {
    try {
      // Normalize the target path: Convert to uppercase and standardize separators
      targetPath = targetPath.toUpperCase().replaceAll('\\', '/');
      final pathParts = targetPath.split('/');
      final targetName = pathParts.last;
      final parentPathParts = pathParts.sublist(0, pathParts.length - 1);

      int currentDirLba = sectorLba;

      // Navigate to the target's parent directory first
      for (final dirName in parentPathParts) {
        if (dirName.isEmpty) continue; // Skip empty parts (e.g., leading '/')
        final dirEntry = await _findDirectoryEntry(currentDirLba, dirName, true);
        if (dirEntry == null || !dirEntry.isDirectory) {
          debugPrint('Could not find directory part "$dirName" in path "$targetPath"');
          return null; // Directory part not found
        }
        currentDirLba = dirEntry.lba;
      }

      // Now search for the final file/directory name in the current directory
      final fileEntry = await _findDirectoryEntry(currentDirLba, targetName, false); // Look for a file
      if (fileEntry == null || fileEntry.isDirectory) {
         debugPrint('Could not find file part "$targetName" in path "$targetPath"');
        return null; // File not found or it's a directory
      }

      return Ps2FileInfo(lba: fileEntry.lba, size: fileEntry.size);
    } catch (e, stackTrace) {
      debugPrint('Error finding file "$targetPath" starting from LBA $sectorLba: $e');
       debugPrint('Stack trace: $stackTrace');
      return null;
    }
  }

  /// Finds a specific directory entry (file or subdirectory) within a single directory sector extent.
  ///
  /// [sectorLba]: The starting LBA of the directory extent.
  /// [targetName]: The uppercase name of the entry to find (without version ";1").
  /// [isDirectory]: Set to true if searching for a directory, false for a file.
  /// Returns a [Ps2DirectoryEntry] or null if not found.
  Future<Ps2DirectoryEntry?> _findDirectoryEntry(
      int sectorLba, String targetName, bool isDirectory) async {
    int currentSectorIndex = sectorLba;
    // Directories can span multiple sectors. We need to read the size from the parent.
    // For simplicity here, we'll assume small directories first, but a robust implementation
    // would read the directory size and loop through all its sectors.
    // Let's read a few sectors to cover common cases.
    const maxSectorsToRead = 5; // Read up to 5 sectors for the directory

    for (int i = 0; i < maxSectorsToRead; i++) {
      final sectorData = await _readSector(currentSectorIndex + i);
      if (sectorData == null) {
         debugPrint('Failed to read directory sector ${currentSectorIndex + i}');
        break; // Stop if we can't read a sector
      }

      int offset = 0;
      while (offset < _sectorSize) {
        // Directory Record Length is the first byte
        final recordLength = sectorData[offset];
        if (recordLength == 0) {
          // Padding record or end of directory entries in this sector. Move to the next sector.
          break; // Exit inner loop to potentially read next sector
        }

        // Basic validation
        if (offset + recordLength > _sectorSize || offset + 33 > _sectorSize) {
           debugPrint('Invalid directory record length ($recordLength) or offset ($offset) at sector ${currentSectorIndex + i}');
          offset += recordLength; // Try to skip to the next record
          continue;
        }

        // File Flags are at offset 25
        final fileFlags = sectorData[offset + 25];
        final entryIsDirectory = (fileFlags & 0x02) != 0;

        // Check if the entry type matches what we're looking for
        if (isDirectory == entryIsDirectory) {
          // Identifier Length is at offset 32
          final nameLength = sectorData[offset + 32];
          if (nameLength > 0 && offset + 33 + nameLength <= _sectorSize) {
            // Extract the Identifier (Filename)
            String name = '';
            try {
              // Use latin1 which is common for ISO9660 filenames
              name = latin1.decode(sectorData.sublist(offset + 33, offset + 33 + nameLength));
            } catch (_) {
               debugPrint('Error decoding filename at sector ${currentSectorIndex + i}, offset $offset');
               name = ''; // Fallback to empty name
            }


            // Normalize name: Uppercase and remove version ";1"
            final semicolonPos = name.indexOf(';');
            if (semicolonPos >= 0) {
              name = name.substring(0, semicolonPos);
            }
            name = name.toUpperCase(); // Compare uppercase

            // Compare with the target name
            if (name == targetName) {
              // Found the entry! Extract LBA and Size.
              final entryLba = ByteData.view(sectorData.buffer).getUint32(offset + 2, Endian.little);
              final entrySize = ByteData.view(sectorData.buffer).getUint32(offset + 10, Endian.little);

              return Ps2DirectoryEntry(
                name: name, // Return the normalized name
                lba: entryLba,
                size: entrySize,
                isDirectory: entryIsDirectory,
              );
            }
          }
        }

        // Move to the next directory record within the sector
        offset += recordLength;
      }
    } // End loop through sectors

    debugPrint('Entry "$targetName" (isDirectory: $isDirectory) not found starting at LBA $sectorLba');
    return null; // Entry not found after checking sectors
  }

  /// Reads a single sector (2048 bytes) from the ISO file.
  ///
  /// Returns the sector data as Uint8List, or null on error.
  Future<Uint8List?> _readSector(int sector) async {
    return await _readSectors(sector, _sectorSize);
  }

  /// Reads a specified number of bytes starting from a given sector.
  ///
  /// [startSector]: The LBA of the first sector to read.
  /// [size]: The total number of bytes to read.
  /// Returns the data as Uint8List, or null on error.
  Future<Uint8List?> _readSectors(int startSector, int size) async {
    RandomAccessFile? raf;
    try {
      final position = startSector * _sectorSize;
      if (position < 0) {
         debugPrint('Invalid start position ($position) calculated for sector $startSector');
         return null;
      }


      raf = await _isoFile.open(mode: FileMode.read);
      final fileSize = await raf.length();

       // Check if the read goes beyond the file size
       if (position + size > fileSize) {
         debugPrint('Read attempt beyond file size. Position: $position, Size: $size, FileSize: $fileSize');
         // Adjust size if possible, or return null if position is already out of bounds
         if (position >= fileSize) return null;
         size = fileSize - position;
         if (size <= 0) return null;
       }


      await raf.setPosition(position);
      final data = await raf.read(size);
       if (data.length != size) {
         debugPrint('Read fewer bytes (${data.length}) than requested ($size) starting sector $startSector');
         // This might be okay if it's the end of the file, but could indicate an issue.
       }
      return data;
    } catch (e, stackTrace) {
      debugPrint('Error reading $size bytes from sector $startSector in ${_isoFile.path}: $e');
      debugPrint('Stack trace: $stackTrace');
      return null;
    } finally {
      await raf?.close();
    }
  }
}
