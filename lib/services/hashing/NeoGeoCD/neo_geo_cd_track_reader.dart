// lib/services/hashing/NeoGeoCD/neo_geo_cd_track_reader.dart
import 'dart:convert'; // Added for ascii decoding
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:retroachievements_organizer/services/hashing/CHD/chd_read_common.dart';

class NeoGeoCdTrackReader {
  final String filePath;
  final ChdReader? chdReader;
  RandomAccessFile? binFile;
  List<TrackInfo>? _initialChdTracks; // Store pre-processed CHD tracks
  Map<String, CueTrackInfo>? cueTrackMap;
  TrackInfo? _dataTrack; // Cache the data track

  // Modified constructor to accept optional initial CHD tracks
  NeoGeoCdTrackReader(this.filePath, this.chdReader, [this._initialChdTracks]) {
     debugPrint("[TrackReader] Initialized for path: $filePath, CHD: ${chdReader != null}, InitialTracks: ${_initialChdTracks?.length ?? 'N/A'}");
  }

  // Factory constructor remains the same
  factory NeoGeoCdTrackReader.fromCueFile(String cuePath) {
    debugPrint("[TrackReader] Initializing from CUE file: $cuePath");
    return NeoGeoCdTrackReader(cuePath, null); // No initial tracks for CUE
  }

  /// Get the data track from the CD
  Future<TrackInfo?> getDataTrack() async {
    debugPrint("[TrackReader] getDataTrack called.");
    if (_dataTrack != null) {
       debugPrint("[TrackReader] Returning cached data track: Number ${_dataTrack!.number}");
       return _dataTrack;
    }

    List<TrackInfo>? currentTracks; // Local variable for tracks

    if (chdReader != null) {
       debugPrint("[TrackReader] CHD Mode: Using initial tracks or processing CHD...");
      if (_initialChdTracks != null && _initialChdTracks!.isNotEmpty) {
         debugPrint("[TrackReader] Using provided initial CHD tracks (${_initialChdTracks!.length}).");
         currentTracks = _initialChdTracks;
      } else {
         debugPrint("[TrackReader] No initial CHD tracks provided, processing CHD file...");
         final ChdProcessResult chdResult;
         try {
             chdResult = await chdReader!.processChdFile(filePath);
         } catch (e, s) {
             debugPrint("[TrackReader] CRITICAL ERROR processing CHD file in getDataTrack: $e\n$s");
             return null;
         }

         if (!chdResult.isSuccess || chdResult.tracks.isEmpty) {
           debugPrint('[TrackReader] CHD processing failed or returned no tracks in getDataTrack: ${chdResult.error ?? "Unknown error"}');
           return null;
         }
         debugPrint("[TrackReader] CHD processing successful in getDataTrack, found ${chdResult.tracks.length} tracks.");
         currentTracks = chdResult.tracks;
         _initialChdTracks = currentTracks; // Cache them
      }

      // --- Logic to find data track from currentTracks (CHD) ---
      if (currentTracks == null || currentTracks.isEmpty) {
          debugPrint("[TrackReader] CRITICAL ERROR: No tracks available for CHD.");
          return null;
      }

      TrackInfo? foundTrack;
      foundTrack = currentTracks.firstWhere((track) => track.number == 1, orElse: () => null as TrackInfo);
     

        
         
      

    
      _dataTrack = foundTrack;
      // --- End CHD track finding ---

    } else {
      // --- CUE file processing ---
      debugPrint("[TrackReader] CUE Mode: Processing CUE file for tracks...");
      try {
        // ... (keep CUE parsing logic from previous version) ...
        final cueFile = File(filePath);
        if (!await cueFile.exists()) {
          debugPrint('[TrackReader] CRITICAL ERROR: CUE file does not exist: $filePath');
          return null;
        }
        debugPrint("[TrackReader] Reading CUE file content...");
        final cueContent = await cueFile.readAsString();
        debugPrint("[TrackReader] Parsing CUE file content...");
        final cueParser = CueParser();
        final parsedTracks = cueParser.parse(cueContent, path.dirname(filePath));

        if (parsedTracks.isEmpty) {
          debugPrint('[TrackReader] CRITICAL ERROR: No tracks found after parsing CUE file.');
          return null;
        }
        debugPrint("[TrackReader] CUE parsing successful, found ${parsedTracks.length} tracks.");
        currentTracks = []; // We'll build TrackInfo list from CueTrackInfo

        cueTrackMap = {};
        CueTrackInfo? dataCueTrack;
        for (final track in parsedTracks) {
          cueTrackMap![track.number.toString()] = track;
           // debugPrint("[TrackReader] CUE Track ${track.number}: Type=${track.type}, File=${track.file}, Start=${track.startFrame}, Frames=${track.frames}, Pregap=${track.pregap}");
          // Find track 1 or first data track
          if (dataCueTrack == null && // Only find the first match
              (track.number == 1 ||
              track.type == 'MODE1/2048' ||
              track.type == 'MODE1/2352' ||
              track.type == 'MODE2/2352' ||
              track.type == 'MODE2/2048' ||
              track.type == 'DATA') )
           {
            dataCueTrack = track;
             debugPrint("[TrackReader] Found potential CUE data track (Num ${track.number}, Type ${track.type}).");
          }
        }

        if (dataCueTrack == null && parsedTracks.isNotEmpty) {
            dataCueTrack = parsedTracks.first;
            debugPrint("[TrackReader] No specific data track found in CUE, falling back to first track (Num ${dataCueTrack.number}).");
        } else if (dataCueTrack == null) {
           debugPrint('[TrackReader] CRITICAL ERROR: Could not determine data track from CUE file.');
           return null;
        }

        debugPrint('[TrackReader] Using CUE Track ${dataCueTrack.number} (${dataCueTrack.type}) as data track.');

        int sectorSize = dataCueTrack.type.contains('2352') ? 2352 : 2048;
        int dataOffset = (dataCueTrack.type == 'MODE1/2352') ? 16 : 0;
        int dataSize = (sectorSize == 2352 && dataOffset == 16) ? 2048 : 2048;
        if (sectorSize == 2048) dataSize = 2048;

        debugPrint("[TrackReader] Calculated TrackInfo params: sectorSize=$sectorSize, dataOffset=$dataOffset, dataSize=$dataSize");

        _dataTrack = TrackInfo(
          number: dataCueTrack.number,
          type: dataCueTrack.type,
          sectorSize: sectorSize,
          pregap: dataCueTrack.pregap ?? 0,
          startFrame: dataCueTrack.startFrame,
          totalFrames: dataCueTrack.frames,
          dataOffset: dataOffset,
          dataSize: dataSize,
        );
        // Although we parsed all tracks, we only create the TrackInfo for the data track for now
        currentTracks.add(_dataTrack!);


      } catch (e, s) {
        debugPrint('[TrackReader] CRITICAL ERROR processing CUE file in getDataTrack: $e\n$s');
        return null;
      }
      // --- End CUE file processing ---
    } // End else (CUE mode)


    // --- Final check and return ---
    if (_dataTrack != null) {
       debugPrint('[TrackReader] Determined Data Track: Number ${_dataTrack!.number} (${_dataTrack!.type})');
    } else {
       debugPrint('[TrackReader] CRITICAL ERROR: Could not determine data track.');
    }
    return _dataTrack; // Return found track or null

  } // End getDataTrack


  /// Read a logical data sector (usually 2048 bytes) from a track.
  Future<Uint8List?> readLogicalSector(int sector) async {
     // Get data track info - necessary for readSector parameters
     final track = await getDataTrack();
     if (track == null) {
       debugPrint("[TrackReader] Cannot read logical sector $sector: Data track info unavailable.");
       return null;
     }
     // debugPrint("[TrackReader] Reading logical sector $sector using track ${track.number}...");
     return readSector(track, sector);
  }


  /// Read a sector from a track, handling physical vs logical reads.
  Future<Uint8List?> readSector(TrackInfo track, int sector) async {
     // debugPrint("[TrackReader] readSector called for track ${track.number}, sector $sector."); // Noisy
    if (sector < 0) {
      debugPrint('[TrackReader] Invalid negative sector requested: $sector');
      return null;
    }

    // Add extra check: if track is null somehow, abort.
    // This should ideally be caught by getDataTrack failing earlier.
    // if (track == null) {
    //    debugPrint('[TrackReader] readSector: ERROR - TrackInfo object is null.');
    //    return null;
    // }

    try {
      if (chdReader != null) {
        // debugPrint("[TrackReader] Reading sector $sector from CHD for track ${track.number}...");
        final data = await chdReader!.readSector(filePath, track, sector);
         if (data == null) {
             debugPrint('[TrackReader] CHD Read returned null for track ${track.number}, sector $sector');
         } else if (data.length != track.dataSize && data.isNotEmpty) { // Allow empty if EOF
             debugPrint('[TrackReader] CHD Read warning: sector $sector size mismatch. Expected ${track.dataSize}, got ${data.length}');
         }
         return data; // Return data or null

      } else { // CUE/BIN mode
        // debugPrint("[TrackReader] Reading sector $sector from BIN via CUE for track ${track.number}...");
        if (binFile == null) {
           // ... (keep file opening logic from previous version) ...
           final cueTrack = cueTrackMap?[track.number.toString()];
           if (cueTrack == null || cueTrack.file == null) {
             debugPrint('[TrackReader] CRITICAL ERROR: No CUE file/track info found for track ${track.number} when trying to open BIN.');
             return null;
           }
           final binFilePath = path.isAbsolute(cueTrack.file!)
               ? cueTrack.file!
               : path.join(path.dirname(filePath), cueTrack.file!);
           debugPrint("[TrackReader] Constructing BIN file path: $binFilePath");

           if (!await File(binFilePath).exists()) {
              debugPrint('[TrackReader] CRITICAL ERROR: BIN file does not exist: $binFilePath');
              return null;
           }
           debugPrint('[TrackReader] Opening BIN file: $binFilePath');
           try {
             binFile = await File(binFilePath).open(mode: FileMode.read);
             debugPrint("[TrackReader] BIN file opened successfully.");
           } catch (e, s) {
              debugPrint('[TrackReader] CRITICAL ERROR opening BIN file $binFilePath: $e\n$s');
              return null;
           }
        }

        int physicalSectorSize = track.sectorSize;
        int dataOffsetInSector = track.dataOffset;
        int logicalDataSize = track.dataSize;

        // *** Offset Calculation Refinement ***
        // physicalOffset = logical_sector_number * physical_sector_size
        // This assumes the BIN file *starts* at logical sector 0 (INDEX 01 of the track).
        // Let's stick with this assumption as it's the most common case for single-BIN CUEs.
        int physicalOffset = sector * physicalSectorSize;
        debugPrint("[TrackReader] Calculated physical offset for logical sector $sector: $physicalOffset (physicalSectorSize=$physicalSectorSize)");


        final fileLength = await binFile!.length();
        if (physicalOffset >= fileLength) {
           debugPrint('[TrackReader] Read offset ($physicalOffset) is at or beyond EOF ($fileLength) for sector $sector. Returning null.');
           return null;
        }

        int bytesToRead = physicalSectorSize;
        if (physicalOffset + physicalSectorSize > fileLength) {
            bytesToRead = fileLength - physicalOffset;
            debugPrint('[TrackReader] Adjusting read size near EOF for sector $sector: reading $bytesToRead bytes');
        }
        if (bytesToRead <= 0) {
            debugPrint('[TrackReader] Calculated bytesToRead is $bytesToRead for sector $sector. Returning null.');
            return null; // Nothing to read
        }


        await binFile!.setPosition(physicalOffset);
        // debugPrint("[TrackReader] Reading $bytesToRead bytes from BIN file at offset $physicalOffset...");
        final rawSectorData = await binFile!.read(bytesToRead);


        if (rawSectorData.length != bytesToRead) { // Check if read returned expected bytes
           debugPrint('[TrackReader] Short read for sector $sector: expected $bytesToRead, got ${rawSectorData.length}. Returning null.');
           return null;
        }
        // debugPrint("[TrackReader] Read ${rawSectorData.length} raw bytes for sector $sector.");


        // Extract logical data if necessary (e.g., MODE1/2352 -> 2048)
        if (logicalDataSize < physicalSectorSize || dataOffsetInSector > 0) {
           // debugPrint("[TrackReader] Extracting logical data (offset=$dataOffsetInSector, size=$logicalDataSize) from raw sector $sector.");
           if (dataOffsetInSector + logicalDataSize > rawSectorData.length) {
             debugPrint('[TrackReader] ERROR: Cannot extract logical data: offset+size ($dataOffsetInSector + $logicalDataSize) exceeds raw data length ${rawSectorData.length} for sector $sector. Returning null.');
             return null;
           }
           final logicalData = Uint8List.sublistView(rawSectorData, dataOffsetInSector, dataOffsetInSector + logicalDataSize);
           // debugPrint("[TrackReader] Extracted ${logicalData.length} bytes of logical data for sector $sector.");
           return logicalData;
        } else {
           // Raw sector data is the logical data
           // debugPrint("[TrackReader] Raw sector data is logical data for sector $sector (${rawSectorData.length} bytes).");
           // Ensure it's not longer than expected logical size if physical size was smaller
           if(rawSectorData.length > logicalDataSize) {
              debugPrint("[TrackReader] Trimming raw data (${rawSectorData.length}) to logical size ($logicalDataSize) for sector $sector.");
             return Uint8List.sublistView(rawSectorData, 0, logicalDataSize);
           }
           return rawSectorData;
        }
      }
    } catch (e, s) {
      debugPrint('[TrackReader] CRITICAL ERROR during readSector for track ${track.number}, sector $sector: $e\n$s');
      return null; // Return null on failure
    }
  } // End readSector

  // --- findFileSector and helpers ---

  Future<FileLocation?> findFileSector(String targetPath) async {
    debugPrint("[TrackReader] findFileSector called for target: '$targetPath'");
    final track = await getDataTrack(); // Ensure track info is available
    if (track == null) {
       debugPrint("[TrackReader] findFileSector: Cannot proceed, getDataTrack failed.");
       return null;
    }
    // ... (rest of findFileSector implementation from previous version remains the same) ...
    debugPrint("[TrackReader] findFileSector: Using data track ${track.number}.");
    String normalizedTargetPath = targetPath.replaceAll('\\', '/').replaceAll('//', '/');
    if (normalizedTargetPath.startsWith('/')) normalizedTargetPath = normalizedTargetPath.substring(1);
    if (normalizedTargetPath.endsWith('/')) normalizedTargetPath = normalizedTargetPath.substring(0, normalizedTargetPath.length - 1);
    normalizedTargetPath = normalizedTargetPath.toUpperCase();
    debugPrint("[TrackReader] findFileSector: Normalized target path: '$normalizedTargetPath'");

    if (normalizedTargetPath.isEmpty) {
       debugPrint("[TrackReader] findFileSector: Target path is root directory.");
       DirectoryRecord? rootDirRecord = await _findRootDirectoryRecord(track); // Pass track here
       if (rootDirRecord == null) {
           debugPrint("[TrackReader] findFileSector: Failed to find root directory record for root path target.");
           return null;
       }
       debugPrint("[TrackReader] findFileSector: Found root directory record at sector ${rootDirRecord.sector}.");
       return FileLocation(sector: rootDirRecord.sector, size: rootDirRecord.size);
    }

    final pathParts = normalizedTargetPath.split('/');
    debugPrint("[TrackReader] findFileSector: Path parts: $pathParts");

    debugPrint("[TrackReader] findFileSector: Finding root directory record...");
    DirectoryRecord? rootDirRecord = await _findRootDirectoryRecord(track); // Pass track here
    if (rootDirRecord == null) {
      debugPrint("[TrackReader] findFileSector: CRITICAL ERROR: Could not find root directory record.");
      return null;
    }
    debugPrint("[TrackReader] findFileSector: Root directory found at sector ${rootDirRecord.sector}, size ${rootDirRecord.size}.");

    DirectoryRecord currentDirRecord = rootDirRecord;

    for (int i = 0; i < pathParts.length; i++) {
      String part = pathParts[i];
      bool isLastPart = (i == pathParts.length - 1);
      debugPrint("[TrackReader] findFileSector: Traversing part ${i+1}/${pathParts.length}: '$part' (Is last: $isLastPart)");
      debugPrint("[TrackReader] findFileSector: Searching in directory sector ${currentDirRecord.sector} ('${currentDirRecord.filename}')");

      DirectoryRecord? foundRecord = await _findRecordInDirectory(track, currentDirRecord, part); // Pass track here

      if (foundRecord == null) {
        debugPrint("[TrackReader] findFileSector: Path component '$part' not found in directory at sector ${currentDirRecord.sector}. Search failed.");
        return null;
      }
      debugPrint("[TrackReader] findFileSector: Found record for '$part': Sector=${foundRecord.sector}, Size=${foundRecord.size}, IsDir=${foundRecord.isDirectory}");

      if (isLastPart) {
        debugPrint("[TrackReader] findFileSector: Successfully found target '$part' (FullPath: '$targetPath').");
        return FileLocation(sector: foundRecord.sector, size: foundRecord.size);
      } else {
        if (!foundRecord.isDirectory) {
          debugPrint("[TrackReader] findFileSector: CRITICAL ERROR: Path component '$part' is a file, but expected a directory for further traversal. Path: '$targetPath'");
          return null;
        }
        currentDirRecord = foundRecord;
        debugPrint("[TrackReader] findFileSector: Moving to next directory '${foundRecord.filename}' (Sector ${foundRecord.sector}).");
      }
    }
    debugPrint("[TrackReader] findFileSector: Logic error, should have returned or failed earlier.");
    return null;
  }

  // Pass TrackInfo to helpers that need to read sectors
  Future<DirectoryRecord?> _findRootDirectoryRecord(TrackInfo track) async {
      debugPrint("[TrackReader] _findRootDirectoryRecord: Reading PVD (sector 16)...");
      const pvdSector = 16;
      // *** Add logging before the readSector call ***
      debugPrint("[TrackReader] _findRootDirectoryRecord: Attempting to read sector $pvdSector using track ${track.number} info...");
      final Uint8List? pvdData;
      try {
         pvdData = await readSector(track, pvdSector);
      } catch (e, s) {
         debugPrint("[TrackReader] _findRootDirectoryRecord: CRITICAL ERROR exception during readSector($pvdSector): $e\n$s");
         return null;
      }

      // *** Add logging after the readSector call ***
      if (pvdData == null) {
           debugPrint("[TrackReader] _findRootDirectoryRecord: readSector($pvdSector) returned null.");
      } else {
           debugPrint("[TrackReader] _findRootDirectoryRecord: readSector($pvdSector) returned ${pvdData.length} bytes.");
      }


      if (pvdData == null || pvdData.length < 156 + 34) {
          debugPrint("[TrackReader] _findRootDirectoryRecord: CRITICAL ERROR: PVD data is null or too short (${pvdData?.length} bytes).");
          return null;
      }

      // ... (rest of _findRootDirectoryRecord remains the same) ...
       if (pvdData[0] != 1 || latin1.decode(pvdData.sublist(1, 6)) != 'CD001') {
           debugPrint("[TrackReader] _findRootDirectoryRecord: CRITICAL ERROR: Invalid PVD identifier found at sector $pvdSector. Header: ${pvdData.sublist(0,10)}");
           return null;
       }
       debugPrint("[TrackReader] _findRootDirectoryRecord: PVD identifier 'CD001' confirmed.");
       debugPrint("[TrackReader] _findRootDirectoryRecord: Parsing root directory record from PVD offset 156...");
       final rootRecord = _parseDirectoryRecord(pvdData.sublist(156), pvdSector);
       if (rootRecord == null) {
          debugPrint("[TrackReader] _findRootDirectoryRecord: Failed to parse root directory record from PVD.");
       } else {
          debugPrint("[TrackReader] _findRootDirectoryRecord: Parsed root record: Name='${rootRecord.filename}', Sector=${rootRecord.sector}, Size=${rootRecord.size}, IsDir=${rootRecord.isDirectory}");
       }
       return rootRecord;
  }

  // Pass TrackInfo to helpers that need to read sectors
  Future<DirectoryRecord?> _findRecordInDirectory(TrackInfo track, DirectoryRecord dirRecord, String targetName) async {
    // ... (keep implementation from previous version with logging) ...
    // Ensure all internal calls to readSector pass the `track` object
    debugPrint("[TrackReader] _findRecordInDirectory: Searching for '$targetName' in directory starting at sector ${dirRecord.sector} (Size: ${dirRecord.size} bytes).");
    int currentSector = dirRecord.sector;
    int bytesRemainingInDirectory = dirRecord.size;
// Assume logical sector size for directory data

    while (bytesRemainingInDirectory > 0) {
       debugPrint("[TrackReader] _findRecordInDirectory: Reading directory sector $currentSector ($bytesRemainingInDirectory bytes remaining in dir)...");
       final sectorData = await readSector(track, currentSector); // Pass track here
       if (sectorData == null) {
         debugPrint("[TrackReader] _findRecordInDirectory: CRITICAL ERROR: Failed to read directory sector $currentSector. Aborting search in this directory.");
         return null; // Error reading directory sector
       }
       debugPrint("[TrackReader] _findRecordInDirectory: Read ${sectorData.length} bytes for directory sector $currentSector.");


       int bytesToProcessInSector = (bytesRemainingInDirectory < sectorData.length) ? bytesRemainingInDirectory : sectorData.length;
       int offset = 0;
       debugPrint("[TrackReader] _findRecordInDirectory: Processing $bytesToProcessInSector bytes from sector $currentSector.");


       while(offset < bytesToProcessInSector) {
           if (offset >= sectorData.length) {
               debugPrint("[TrackReader] _findRecordInDirectory: Error: Offset $offset reached end of sector data $currentSector unexpectedly.");
               break;
           }

           final recordLength = sectorData[offset];
           if (recordLength == 0) {
               int remainingInSector = bytesToProcessInSector - offset;
               debugPrint("[TrackReader] _findRecordInDirectory: Found padding ($remainingInSector bytes) at offset $offset. Moving to next sector.");
               offset += remainingInSector;
               continue;
           }

           if (offset + recordLength > sectorData.length) {
               debugPrint("[TrackReader] _findRecordInDirectory: CRITICAL ERROR: Record at offset $offset in sector $currentSector claims length $recordLength, exceeding sector data bounds (${sectorData.length}). Directory possibly corrupt. Aborting search.");
               return null;
           }
           if (offset + recordLength > bytesToProcessInSector) {
              debugPrint("[TrackReader] _findRecordInDirectory: Warning: Record at offset $offset in sector $currentSector claims length $recordLength, exceeding remaining directory bytes ($bytesToProcessInSector). Processing anyway.");
           }

           final recordData = sectorData.sublist(offset, offset + recordLength);
           final parsedRecord = _parseDirectoryRecord(recordData, currentSector);

           if (parsedRecord != null) {
               String recordFilename = parsedRecord.filename;
               final versionSeparator = recordFilename.indexOf(';');
               if (versionSeparator != -1) {
                   recordFilename = recordFilename.substring(0, versionSeparator);
               }
               recordFilename = recordFilename.trim();

               if (recordFilename.toUpperCase() == targetName.toUpperCase()) {
                    debugPrint("[TrackReader] _findRecordInDirectory: Matched '$targetName' with record '${parsedRecord.filename}'. Found at sector ${parsedRecord.sector}.");
                   return parsedRecord;
               }
           }

           offset += recordLength;
       } // End while offset < bytesToProcessInSector


       bytesRemainingInDirectory -= bytesToProcessInSector;
       currentSector++;
       if(bytesRemainingInDirectory > 0) {
         debugPrint("[TrackReader] _findRecordInDirectory: End of sector $currentSector reached, $bytesRemainingInDirectory bytes remaining in directory. Moving to next sector $currentSector.");
       }

     } // End while bytesRemainingInDirectory > 0

     debugPrint("[TrackReader] _findRecordInDirectory: Target '$targetName' not found after scanning directory starting at sector ${dirRecord.sector}.");
     return null;
  }


  DirectoryRecord? _parseDirectoryRecord(Uint8List recordData, int containingSector) {
    // ... (keep implementation from previous version with logging) ...
     try {
         if (recordData.isEmpty) return null;
         final recordLength = recordData[0];
         if (recordLength == 0) return null;
         if (recordData.length < 33) {
            debugPrint("[TrackReader] _parseDirectoryRecord: Record too short (${recordData.length} bytes) at sector $containingSector. Need 33 bytes minimum.");
            return null;
         }

         final sectorLE = ByteData.view(recordData.buffer, recordData.offsetInBytes + 2, 4).getUint32(0, Endian.little);
         final sector = sectorLE;

         final sizeLE = ByteData.view(recordData.buffer, recordData.offsetInBytes + 10, 4).getUint32(0, Endian.little);
         final size = sizeLE;

         final flags = recordData[25];
         final filenameLength = recordData[32];

         if (recordData.length < 33 + filenameLength) {
           debugPrint("[TrackReader] _parseDirectoryRecord: ERROR: Record length mismatch: record claims ${33+filenameLength} bytes for filename, but total data length is only ${recordData.length}. Record likely corrupt.");
           return null;
         }

         if (filenameLength == 1 && (recordData[33] == 0x00 || recordData[33] == 0x01)) {
           return null;
         }

         String filename;
         try {
            filename = latin1.decode(recordData.sublist(33, 33 + filenameLength));
         } catch (e) {
            debugPrint("[TrackReader] _parseDirectoryRecord: Warning: Failed to decode filename bytes as Latin-1: $e. Using lossy conversion.");
            filename = utf8.decode(recordData.sublist(33, 33 + filenameLength), allowMalformed: true);
         }

         return DirectoryRecord(
             sector: sector,
             size: size,
             isDirectory: (flags & 0x02) != 0,
             filename: filename,
             containingSector: containingSector,
         );
     } catch (e,s) {
         debugPrint("[TrackReader] _parseDirectoryRecord: CRITICAL ERROR parsing directory record: $e\n$s");
         return null;
     }
  }

  // --- End of findFileSector logic ---

  // ... (close method remains the same) ...
  Future<void> close() async {
    debugPrint("[TrackReader] close called.");
    if (binFile != null) {
       debugPrint("[TrackReader] Closing open BIN file...");
      try {
         await binFile!.close();
         debugPrint('[TrackReader] Closed bin file.');
      } catch (e) {
         debugPrint('[TrackReader] Error closing bin file: $e');
      } finally {
         binFile = null;
      }
    } else {
       debugPrint("[TrackReader] No open BIN file to close.");
    }
    _dataTrack = null; // Clear cached track
    cueTrackMap = null;
    debugPrint("[TrackReader] Cleared cached track info.");
  }

} // End NeoGeoCdTrackReader class


// --- Helper Classes (FileLocation, DirectoryRecord, CueTrackInfo, CueParser) ---
// Keep implementations from the previous version (with logging)

/// Represents a located file or directory on the disc.
class FileLocation {
    final int sector;
    final int size;
    FileLocation({required this.sector, required this.size});
    @override String toString() => 'FileLocation(sector: $sector, size: $size)';
}

/// Represents an ISO9660 Directory Record.
class DirectoryRecord {
    final int sector; // Starting sector of the file/directory data
    final int size; // Size of the file/directory data in bytes
    final bool isDirectory;
    final String filename; // Filename as read from record (might include version ";1")
    final int containingSector; // Sector where this directory record was found
    DirectoryRecord({ required this.sector, required this.size, required this.isDirectory, required this.filename, required this.containingSector, });
     @override String toString() => 'DirectoryRecord(filename: $filename, sector: $sector, size: $size, isDirectory: $isDirectory, foundInSector: $containingSector)';
}

/// Class to represent a track in a CUE file
class CueTrackInfo {
  final int number;
  final String type;
  final String? file;
  final int startFrame; // Start frame (LBA) relative to disc start (INDEX 01)
  final int frames; // Estimated total data frames (LBA count) for the track
  final int? pregap; // Pregap *duration* in frames (LBA) before INDEX 01
  CueTrackInfo({ required this.number, required this.type, this.file, required this.startFrame, required this.frames, this.pregap, });
   @override String toString() => 'CueTrackInfo(number: $number, type: $type, file: $file, startFrame(INDEX 01): $startFrame, frames: $frames, pregap: $pregap)';
}

/// Class to parse CUE files
class CueParser {
  List<CueTrackInfo> parse(String cueContent, String basePath) {
    // **(Keep implementation from previous version with logging)**
    debugPrint("[CueParser] Starting CUE parse for base path: $basePath");
    final List<CueTrackInfo> tracks = [];
    String? currentFile;
    int currentTrackNumber = 0;
    String currentTrackType = '';
    final lines = cueContent.split('\n');
    final trackStarts = <int, Map<String, dynamic>>{};

    for (final line in lines) {
      final trimmedLine = line.trim();
      if (trimmedLine.startsWith('FILE ')) {
        final match = RegExp(r'FILE\s+"([^"]+)"').firstMatch(trimmedLine);
        if (match != null) {
          currentFile = match.group(1)!;
          debugPrint('[CueParser] Found file: $currentFile');
        }
      } else if (trimmedLine.startsWith('TRACK ')) {
        final match = RegExp(r'TRACK\s+(\d+)\s+([\w/]+)').firstMatch(trimmedLine);
        if (match != null) {
          currentTrackNumber = int.parse(match.group(1)!);
          currentTrackType = match.group(2)!.toUpperCase();
           debugPrint('[CueParser] Found track: $currentTrackNumber, type: $currentTrackType');
          if(trackStarts.containsKey(currentTrackNumber)) {
             debugPrint("[CueParser] Warning: Track number $currentTrackNumber encountered again. Overwriting previous info.");
          }
          trackStarts[currentTrackNumber] = { 'file': currentFile, 'type': currentTrackType, 'index01Frame': -1, 'pregap': null, 'number': currentTrackNumber, };
        }
      } else if (trimmedLine.startsWith('INDEX ')) {
         if (currentTrackNumber > 0 && trackStarts.containsKey(currentTrackNumber)) {
            final indexMatch = RegExp(r'INDEX\s+(\d+)\s+(\d+):(\d+):(\d+)').firstMatch(trimmedLine);
             if (indexMatch != null) {
                final indexNumber = int.parse(indexMatch.group(1)!);
                final minutes = int.parse(indexMatch.group(2)!);
                final seconds = int.parse(indexMatch.group(3)!);
                final frames = int.parse(indexMatch.group(4)!);
                final frameOffset = minutes * 60 * 75 + seconds * 75 + frames;
                 debugPrint('[CueParser] Track $currentTrackNumber INDEX $indexNumber at frame $frameOffset');
                if (indexNumber == 1) {
                   if(trackStarts[currentTrackNumber]!['index01Frame'] == -1) {
                      trackStarts[currentTrackNumber]!['index01Frame'] = frameOffset;
                       debugPrint('[CueParser] Set Track $currentTrackNumber INDEX 01 frame to $frameOffset');
                   } else {
                      debugPrint('[CueParser] Warning: Track $currentTrackNumber encountered INDEX 01 again at frame $frameOffset. Previous was ${trackStarts[currentTrackNumber]!['index01Frame']}. Keeping first.');
                   }
                }
             } else { debugPrint("[CueParser] Warning: Could not parse INDEX line: $trimmedLine"); }
         } else { debugPrint("[CueParser] Warning: Encountered INDEX line before valid TRACK: $trimmedLine"); }
      } else if (trimmedLine.startsWith('PREGAP ')) {
         if (currentTrackNumber > 0 && trackStarts.containsKey(currentTrackNumber)) {
            final pregapMatch = RegExp(r'PREGAP\s+(\d+):(\d+):(\d+)').firstMatch(trimmedLine);
             if (pregapMatch != null) {
                final minutes = int.parse(pregapMatch.group(1)!);
                final seconds = int.parse(pregapMatch.group(2)!);
                final frames = int.parse(pregapMatch.group(3)!);
                int currentTrackPregap = minutes * 60 * 75 + seconds * 75 + frames;
                trackStarts[currentTrackNumber]!['pregap'] = currentTrackPregap;
                debugPrint('[CueParser] Set Track $currentTrackNumber PREGAP to $currentTrackPregap frames');
             } else { debugPrint("[CueParser] Warning: Could not parse PREGAP line: $trimmedLine"); }
         } else { debugPrint("[CueParser] Warning: Encountered PREGAP line before valid TRACK: $trimmedLine"); }
      }
    } // End line loop

    debugPrint("[CueParser] Finished first pass. Track starts info: ${trackStarts.values.map((v) => v['number']).join(', ')}");
    List<int> sortedTrackNumbers = trackStarts.keys.toList()..sort();
    int currentDiscFrame = 0;

    for (int i = 0; i < sortedTrackNumbers.length; i++) {
        int trackNum = sortedTrackNumbers[i];
        var trackData = trackStarts[trackNum]!;
        int index01Frame = trackData['index01Frame'];
        int? pregapFrames = trackData['pregap'];
        int trackStartFrameAbs;
         debugPrint("[CueParser] Processing Track $trackNum (${trackData['type']}): Index01=$index01Frame, Pregap=$pregapFrames");

        if (index01Frame != -1) {
           trackStartFrameAbs = index01Frame - (pregapFrames ?? 0);
           if (trackStartFrameAbs < currentDiscFrame) {
              debugPrint("[CueParser] Warning: Track $trackNum calculated absolute start frame ($trackStartFrameAbs) is before previous track's end frame ($currentDiscFrame). Adjusting start to $currentDiscFrame.");
              trackStartFrameAbs = currentDiscFrame;
              index01Frame = trackStartFrameAbs + (pregapFrames ?? 0);
              trackData['index01Frame'] = index01Frame;
              debugPrint("[CueParser] Adjusted Track $trackNum INDEX 01 frame to $index01Frame");
           }
        } else {
            trackStartFrameAbs = currentDiscFrame;
            debugPrint("[CueParser] Warning: INDEX 01 not found for track $trackNum. Assuming absolute start at $trackStartFrameAbs.");
            index01Frame = trackStartFrameAbs + (pregapFrames ?? 0);
            trackData['index01Frame'] = index01Frame;
            debugPrint("[CueParser] Guessed Track $trackNum INDEX 01 frame: $index01Frame");
        }

        int nextTrackStartFrameAbs;
        if (i + 1 < sortedTrackNumbers.length) {
            int nextTrackNum = sortedTrackNumbers[i+1];
            var nextTrackData = trackStarts[nextTrackNum]!;
            int nextIndex01 = nextTrackData['index01Frame'];
            int? nextPregap = nextTrackData['pregap'];
             debugPrint("[CueParser] Next track $nextTrackNum: Index01=$nextIndex01, Pregap=$nextPregap");
            if (nextIndex01 != -1) {
               nextTrackStartFrameAbs = nextIndex01 - (nextPregap ?? 0);
                debugPrint("[CueParser] Calculated next track absolute start (from Index01): $nextTrackStartFrameAbs");
            } else {
                debugPrint("[CueParser] Next track $nextTrackNum INDEX 01 unknown. Estimating current track ($trackNum) length from file size.");
                 int estimatedFrames = _estimateFramesForFile(trackData['file'], trackData['type'], basePath);
                 nextTrackStartFrameAbs = (index01Frame + estimatedFrames).toInt();
                  debugPrint("[CueParser] Estimated end of current track data / start of next track at $nextTrackStartFrameAbs");
            }
        } else {
            debugPrint("[CueParser] Last track ($trackNum). Estimating its length from file size.");
            int estimatedFrames = _estimateFramesForFile(trackData['file'], trackData['type'], basePath);
            nextTrackStartFrameAbs = (index01Frame + estimatedFrames).toInt();
             debugPrint("[CueParser] Estimated end of last track data at $nextTrackStartFrameAbs");
        }

         if (nextTrackStartFrameAbs < index01Frame) {
            debugPrint("[CueParser] Warning: Calculated next track start frame ($nextTrackStartFrameAbs) is before current track's INDEX 01 ($index01Frame). Setting next start = index01.");
            nextTrackStartFrameAbs = index01Frame;
         }

        int trackDataFrames = nextTrackStartFrameAbs - index01Frame;
        if (trackDataFrames < 0) {
            debugPrint("[CueParser] Warning: Track $trackNum calculated negative data frames ($trackDataFrames). Setting to 0.");
            trackDataFrames = 0;
        }

         tracks.add(CueTrackInfo( number: trackNum, type: trackData['type'], file: trackData['file'], startFrame: index01Frame, frames: trackDataFrames, pregap: pregapFrames, ));
          debugPrint('[CueParser] Added Track $trackNum -> ${tracks.last}');
          currentDiscFrame = nextTrackStartFrameAbs;
          debugPrint("[CueParser] Updating current absolute disc frame to: $currentDiscFrame");
    } // End track loop

   debugPrint("[CueParser] Finished CUE parsing. Total tracks parsed: ${tracks.length}");
   return tracks;
 } // End parse

  int _estimateFramesForFile(String? filename, String trackType, String basePath) {
    // **(Keep implementation from previous version with logging)**
     if (filename == null) {
         debugPrint("[CueParser] _estimateFrames: No filename provided.");
         return 0;
     }
     try {
          final filePath = path.isAbsolute(filename) ? filename : path.join(basePath, filename);
         final file = File(filePath);
         if (file.existsSync()) {
             final fileSize = file.lengthSync();
             int bytesPerFrame;
              if (trackType.contains('MODE1/2352') || trackType.contains('MODE2/2352')) { bytesPerFrame = 2352; }
              else if (trackType.contains('MODE1/2048') || trackType.contains('MODE2/2048') || trackType == 'DATA') { bytesPerFrame = 2048; }
              else if (trackType == 'AUDIO') { bytesPerFrame = 2352; }
              else { bytesPerFrame = 2048; debugPrint("[CueParser] _estimateFrames: Warning: Unknown track type '$trackType' for file '$filename', assuming 2048 bytes/frame for estimation."); }
             if (bytesPerFrame <= 0) { debugPrint("[CueParser] _estimateFrames: Error: Invalid bytesPerFrame ($bytesPerFrame)."); return 0; }
             int estimatedFrames = fileSize ~/ bytesPerFrame;
              debugPrint('[CueParser] _estimateFrames: Estimated $estimatedFrames frames for file $filename (size $fileSize, bytes/frame $bytesPerFrame)');
             return estimatedFrames;
         } else { debugPrint('[CueParser] _estimateFrames: Cannot estimate frames: File does not exist: $filePath'); return 0; }
     } catch (e) { debugPrint('[CueParser] _estimateFrames: Error estimating frames for file $filename: $e'); return 0; }
  } // End _estimateFramesForFile
} // End CueParser