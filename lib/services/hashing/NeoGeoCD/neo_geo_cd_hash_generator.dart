// lib/services/hashing/NeoGeoCD/neo_geo_cd_hash_generator.dart
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:retroachievements_organizer/services/hashing/CHD/chd_read_common.dart';
import 'package:retroachievements_organizer/services/hashing/NeoGeoCD/neo_geo_cd_track_reader.dart';

class NeoGeoCdHashGenerator {
  static const int MAX_PRG_SIZE_TO_HASH = 50 * 1024 * 1024; // Limit hashing size per PRG if needed

  /// Hash a Neo Geo CD from a CHD file
  Future<String?> hashFromChd(String filePath, ChdProcessResult chdResult) async {
    debugPrint("[HashGenerator] Hashing CHD: $filePath");
    final ChdReader reader;
    final NeoGeoCdTrackReader trackReader;
    try {
       reader = ChdReader();
       // Pass the processed tracks to the TrackReader constructor
       trackReader = NeoGeoCdTrackReader(filePath, reader, chdResult.tracks);
       debugPrint("[HashGenerator] TrackReader initialized for CHD.");
    } catch (e, s) {
       debugPrint("[HashGenerator] CRITICAL ERROR during CHD TrackReader Initialization: $e\nStack Trace:\n$s");
       return null;
    }

    try {
      debugPrint("[HashGenerator] Calling _hashNeoGeoCd for CHD...");
      return await _hashNeoGeoCd(trackReader); // Await the result here
    } catch (e, s) {
       debugPrint("[HashGenerator] Caught Exception during CHD Hashing (_hashNeoGeoCd call): $e\nStack Trace:\n$s");
       return null;
    } finally {
       debugPrint("[HashGenerator] Closing track reader for CHD: $filePath");
       await trackReader.close();
    }
  }

  /// Hash a Neo Geo CD from a CUE file
  Future<String?> hashFromCue(String filePath) async {
    debugPrint("[HashGenerator] Hashing CUE: $filePath");
     final NeoGeoCdTrackReader trackReader;
     try {
        trackReader = NeoGeoCdTrackReader.fromCueFile(filePath);
        debugPrint("[HashGenerator] TrackReader initialized for CUE.");
     } catch (e, s) {
        debugPrint("[HashGenerator] CRITICAL ERROR during CUE TrackReader Initialization: $e\nStack Trace:\n$s");
        return null;
     }

     try {
        debugPrint("[HashGenerator] Calling _hashNeoGeoCd for CUE...");
        return await _hashNeoGeoCd(trackReader); // Await the result here
     } catch(e, s) {
       debugPrint("[HashGenerator] Caught Exception during CUE Hashing (_hashNeoGeoCd call): $e\nStack Trace:\n$s");
       return null;
     }
     finally {
        debugPrint("[HashGenerator] Closing track reader for CUE: $filePath");
        await trackReader.close();
     }
  }

   // Common hashing logic used by both CHD and CUE paths
  Future<String?> _hashNeoGeoCd(NeoGeoCdTrackReader trackReader) async {
     debugPrint("[HashGenerator] == Starting _hashNeoGeoCd ==");
     try {
       debugPrint("[HashGenerator] Step 1: Getting data track...");
       final dataTrack = await trackReader.getDataTrack();
       if (dataTrack == null) {
         debugPrint('[HashGenerator] ABORT (Step 1): Could not determine data track.');
         return null;
       }
       debugPrint("[HashGenerator] Step 1 SUCCESS: Data track Number ${dataTrack.number}, Type ${dataTrack.type}");

       debugPrint("[HashGenerator] Step 2: Locating IPL.TXT...");
       final iplLocation = await trackReader.findFileSector("IPL.TXT");
       if (iplLocation == null) {
         debugPrint('[HashGenerator] ABORT (Step 2): Could not locate IPL.TXT.');
         return null;
       }
       debugPrint("[HashGenerator] Step 2 SUCCESS: Found IPL.TXT at sector ${iplLocation.sector}, size ${iplLocation.size}");

       if (iplLocation.size <= 0) {
           debugPrint("[HashGenerator] ABORT (Step 2b): IPL.TXT found but size is ${iplLocation.size}.");
           return null;
       }

       debugPrint("[HashGenerator] Step 3: Reading IPL.TXT content...");
       final iplContentBytes = await trackReader.readLogicalSector(iplLocation.sector);
       if (iplContentBytes == null) {
          debugPrint('[HashGenerator] ABORT (Step 3): Could not read IPL.TXT content from sector ${iplLocation.sector}');
          return null;
       }
       debugPrint("[HashGenerator] Step 3 SUCCESS: Read ${iplContentBytes.length} bytes for IPL.TXT sector.");

       final iplData = (iplLocation.size < iplContentBytes.length)
          ? Uint8List.sublistView(iplContentBytes, 0, iplLocation.size)
          : iplContentBytes;
       debugPrint("[HashGenerator] Effective IPL.TXT size for parsing: ${iplData.length}");


       debugPrint("[HashGenerator] Step 4: Parsing IPL.TXT content...");
       final prgFilesToHash = _parsePrgFilesFromIpl(iplData);
       if (prgFilesToHash.isEmpty) {
         debugPrint('[HashGenerator] ABORT (Step 4): No PRG files found listed in IPL.TXT');
         return null;
       }
       debugPrint("[HashGenerator] Step 4 SUCCESS: PRG files to hash: ${prgFilesToHash.join(', ')}");


       debugPrint("[HashGenerator] Step 5: Hashing PRG file contents...");
       final String? finalHash = await _hashPrgFileContents(trackReader, prgFilesToHash); // Await here

       if (finalHash == null) {
            debugPrint("[HashGenerator] ABORT (Step 5): _hashPrgFileContents returned null.");
            return null;
       }

       debugPrint("[HashGenerator] == _hashNeoGeoCd FINISHED SUCCESSFULLY ==");
       return finalHash;

     } catch (e, s) {
        // Catch any unexpected errors within _hashNeoGeoCd itself
        debugPrint("[HashGenerator] CRITICAL ERROR inside _hashNeoGeoCd: $e\nStack Trace:\n$s");
        return null;
     }
  } // End _hashNeoGeoCd


  // ... (_parsePrgFilesFromIpl remains the same as previous version with logging) ...
  List<String> _parsePrgFilesFromIpl(Uint8List iplContent) {
    debugPrint("[HashGenerator] _parsePrgFilesFromIpl: Starting parse...");
    final prgFiles = <String>[];
    int endMarker = iplContent.indexOf(0x1A);
    if (endMarker == -1) endMarker = iplContent.length;
    debugPrint("[HashGenerator] _parsePrgFilesFromIpl: Parsing content up to index $endMarker");

    String iplText;
    try { iplText = latin1.decode(iplContent.sublist(0, endMarker), allowInvalid: true); }
    catch(e) { debugPrint("[HashGenerator] _parsePrgFilesFromIpl: ERROR decoding IPL content as Latin-1: $e. Trying UTF-8.");
       try { iplText = utf8.decode(iplContent.sublist(0, endMarker), allowMalformed: true); }
       catch (e2) { debugPrint("[HashGenerator] _parsePrgFilesFromIpl: ERROR decoding IPL content as UTF-8: $e2. Aborting parse."); return []; }
    }
    final lines = iplText.split(RegExp(r'\r?\n'));
    debugPrint("[HashGenerator] _parsePrgFilesFromIpl: Split into ${lines.length} lines.");

    for (final line in lines) {
      final trimmedLine = line.trim();
      if (trimmedLine.isEmpty) continue;
      if (trimmedLine.toUpperCase().endsWith('.PRG')) {
        final filename = trimmedLine;
        // debugPrint("[HashGenerator] _parsePrgFilesFromIpl: Found potential PRG: '$filename'");
         if (!prgFiles.any((existing) => existing.toUpperCase() == filename.toUpperCase())) {
             prgFiles.add(filename);
             debugPrint("[HashGenerator] _parsePrgFilesFromIpl: Added PRG: '$filename'");
         } else { debugPrint("[HashGenerator] _parsePrgFilesFromIpl: Skipping duplicate PRG: '$filename'"); }
      }
    }
    debugPrint("[HashGenerator] _parsePrgFilesFromIpl: Finished parse. Found ${prgFiles.length} unique PRG files.");
    return prgFiles;
  }


  // ... (_hashPrgFileContents remains the same as previous version with logging) ...
  Future<String?> _hashPrgFileContents(
    NeoGeoCdTrackReader trackReader,
    List<String> prgFilenames) async {
    debugPrint("[HashGenerator] _hashPrgFileContents: Initializing MD5...");
    Digest? finalHash;
    final md5Converter = md5.startChunkedConversion( ChunkedConversionSink.withCallback((chunks) { if (chunks.isNotEmpty) { finalHash = chunks.single; } }), );
    bool hashedAnyFile = false;
    bool encounteredError = false;

    for (final prgFilename in prgFilenames) {
       if (encounteredError) break;
      debugPrint("[HashGenerator] _hashPrgFileContents: Processing PRG file: $prgFilename");
      debugPrint("[HashGenerator] _hashPrgFileContents: Locating '$prgFilename'...");
      final prgLocation = await trackReader.findFileSector(prgFilename); // Await here
      if (prgLocation == null) { debugPrint("[HashGenerator] _hashPrgFileContents: Could not locate PRG file: '$prgFilename'. Skipping."); continue; }
      debugPrint("[HashGenerator] _hashPrgFileContents: Found '$prgFilename' at sector ${prgLocation.sector}, size ${prgLocation.size}");
      if (prgLocation.size <= 0) { debugPrint("[HashGenerator] _hashPrgFileContents: PRG file '$prgFilename' has size ${prgLocation.size}. Skipping."); continue; }

      int currentSector = prgLocation.sector;
      int bytesRemaining = prgLocation.size;
      int bytesToHash = bytesRemaining;
      int originalBytesToHash = bytesToHash;
      debugPrint("[HashGenerator] _hashPrgFileContents: Hashing $bytesToHash bytes from '$prgFilename' starting at sector $currentSector...");
      int sectorsRead = 0;
      while (bytesToHash > 0) {
        final sectorData = await trackReader.readLogicalSector(currentSector); // Await here
        if (sectorData == null) { debugPrint("[HashGenerator] _hashPrgFileContents: CRITICAL ERROR: Failed to read sector $currentSector for PRG file '$prgFilename'. Aborting hash generation."); encounteredError = true; break; }
        sectorsRead++;
        int bytesToReadFromSector = (bytesToHash < sectorData.length) ? bytesToHash : sectorData.length;
        try { md5Converter.add(Uint8List.sublistView(sectorData, 0, bytesToReadFromSector).toList()); }
        catch (e) { debugPrint("[HashGenerator] _hashPrgFileContents: CRITICAL ERROR: Failed to add data chunk to MD5 converter for '$prgFilename': $e. Aborting."); encounteredError = true; break; }
        bytesToHash -= bytesToReadFromSector;
        currentSector++;
      } // End while
      if (encounteredError) { debugPrint("[HashGenerator] _hashPrgFileContents: Hashing aborted for '$prgFilename' due to read/hash error."); break; }
      else if (bytesToHash == 0) { debugPrint("[HashGenerator] _hashPrgFileContents: Finished hashing $originalBytesToHash bytes ($sectorsRead sectors read) for '$prgFilename'."); hashedAnyFile = true; }
      else { debugPrint("[HashGenerator] _hashPrgFileContents: Warning: Exited hashing loop for '$prgFilename' with $bytesToHash bytes still remaining (original $originalBytesToHash)."); }
    } // End for loop

    debugPrint("[HashGenerator] _hashPrgFileContents: Closing MD5 converter.");
    md5Converter.close(); // Finalize

    if (encounteredError) { debugPrint("[HashGenerator] _hashPrgFileContents: Hashing failed due to critical error during PRG file processing."); return null; }
    if (!hashedAnyFile) { debugPrint("[HashGenerator] _hashPrgFileContents: No PRG files could be located AND hashed successfully."); return null; }
    if (finalHash == null) { debugPrint("[HashGenerator] _hashPrgFileContents: MD5 final hash is null after processing. Hashing likely failed."); return null; }

    final hashString = finalHash.toString();
    debugPrint('[HashGenerator] FINAL HASH: $hashString');
    return hashString;
  } // End _hashPrgFileContents

} // End NeoGeoCdHashGenerator class

// ... (NeoGeoPrgFile class remains the same) ...
class NeoGeoPrgFile {
  final String filename;
  final int sector;
  final int size;
  NeoGeoPrgFile({ required this.filename, required this.sector, required this.size, });
}