import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:retroachievements_organizer/services/hashing/CHD/chd_read_common.dart';

// Message to send to the isolate
class PCEPCFXProcessRequest {
  final String filePath;
  final SendPort sendPort;
  final bool isPCFX; // To differentiate between PCE and PCFX

  PCEPCFXProcessRequest(this.filePath, this.sendPort, this.isPCFX);
}

// Response from the isolate
class PCEPCFXProcessResponse {
  final String? hash;
  final String? error;
  final String filePath;
  final double progress; // 0.0 to 1.0

  PCEPCFXProcessResponse({
    this.hash,
    this.error,
    required this.filePath,
    this.progress = 1.0,
  });
}

/// Class to handle PC Engine CD and PC-FX filesystem operations
class PCEPCFXReader {
  // Constants for identifiers
  static final List<int> PCE_IDENTIFIER = utf8.encode("PC Engine CD-ROM SYSTEM");
  static final List<int> PCFX_IDENTIFIER = utf8.encode("PC-FX:Hu_CD-ROM");
  
  // Constants for CD001 (ISO9660 marker)
  static final List<int> CD001_MARKER = [0x43, 0x44, 0x30, 0x30, 0x31]; // "CD001"
  
  static const int PCE_HEADER_SECTOR = 1; // PCE system info is in second sector
  static const int PCFX_HEADER_SECTOR = 0; // PCFX header is in first sector
  static const int PCFX_PROGRAM_SECTOR_OFFSET = 1; // Program info in next sector
  
  static const int SECTOR_SIZE = 2048; // Size of data portion of a sector
  
  final String filePath;
  final bool isPCFX;
  
  // For CHD files
  final ChdReader? chdReader;
  List<TrackInfo>? tracks;
  
  PCEPCFXReader(this.filePath, this.isPCFX, {this.chdReader, this.tracks});

  /// Read sectors from a file, handling different sector formats
  Future<Uint8List?> _readSectors(
  RandomAccessFile file, 
  int startSector, 
  int numSectors,
  int sectorSize,
  int dataOffset
) async {
  try {
    debugPrint('Reading $numSectors sectors starting at sector $startSector (sectorSize: $sectorSize, offset: $dataOffset)');
    
    // Create a buffer for the data (2048 bytes per sector)
    final buffer = Uint8List(numSectors * SECTOR_SIZE);
    int totalRead = 0;
    
    for (int i = 0; i < numSectors; i++) {
      // Calculate the exact byte position in the file
      final position = (startSector + i) * sectorSize + dataOffset;
      
      // Seek to the start of the sector
      await file.setPosition(position);
      
      // Read 2048 bytes of data (standard sector data size)
      final sectorData = Uint8List(SECTOR_SIZE);
      final bytesRead = await file.readInto(sectorData);
      
      if (bytesRead < SECTOR_SIZE) {
        debugPrint('Warning: Failed to read complete sector ${startSector + i}, only read $bytesRead bytes');
        
        // Use what we got if it's better than nothing
        if (bytesRead > 0) {
          buffer.setRange(totalRead, totalRead + bytesRead, sectorData.sublist(0, bytesRead));
          totalRead += bytesRead;
        }
        
        if (totalRead == 0) {
          return null; // No data read at all
        }
        break;
      }
      
      // Copy to the buffer
      buffer.setRange(totalRead, totalRead + SECTOR_SIZE, sectorData);
      totalRead += SECTOR_SIZE;
    }
    
    // Return what we were able to read
    return buffer.sublist(0, totalRead);
  } catch (e, stack) {
    debugPrint('Error reading sectors: $e');
    debugPrint('Stack trace: $stack');
    return null;
  }
}

Future<Uint8List?> _readRawSector(
  RandomAccessFile file,
  int sector,
  int sectorSize,
  [int dataOffset = 0]
) async {
  try {
    // Calculate absolute position
    final position = sector * sectorSize + dataOffset;
    
    // Check if position is valid
    final fileSize = await file.length();
    if (position >= fileSize) {
      debugPrint('Warning: Sector position $position exceeds file size $fileSize');
      return null;
    }
    
    // Seek to sector
    await file.setPosition(position);
    
    // Read entire sector
    final sectorData = Uint8List(sectorSize < 2048 ? sectorSize : 2048);
    final bytesRead = await file.readInto(sectorData);
    
    if (bytesRead < sectorData.length) {
      debugPrint('Warning: Only read $bytesRead of ${sectorData.length} bytes');
      // Return what we got
      return sectorData.sublist(0, bytesRead);
    }
    
    return sectorData;
  } catch (e) {
    debugPrint('Error reading raw sector: $e');
    return null;
  }
}


  /// Main function to read data from BIN/ISO files
  Future<Map<String, dynamic>?> readDataFromBinIso() async {
  try {
    final file = File(filePath);
    if (!await file.exists()) {
      debugPrint('File does not exist: $filePath');
      return null;
    }
    
    final randomAccessFile = await file.open(mode: FileMode.read);
    try {
      final result = <String, dynamic>{};
      
      // Detect file format
      final fileSize = await file.length();
      debugPrint('File size: $fileSize bytes');
      
      // Determine likely sector size based on file size
      bool isValidSectorSize = false;
      int likelySectorSize = 2048; // Default ISO
      int likelyDataOffset = 0;
      
      // Check if size is multiple of 2352 (CDDA format)
      if (fileSize % 2352 == 0) {
        likelySectorSize = 2352;
        likelyDataOffset = 16; // Standard data offset for CDDA
        isValidSectorSize = true;
        debugPrint('File likely uses 2352-byte sectors (CDDA format)');
      } 
      // Check if size is multiple of 2048 (ISO format)
      else if (fileSize % 2048 == 0) {
        likelySectorSize = 2048;
        likelyDataOffset = 0;
        isValidSectorSize = true;
        debugPrint('File likely uses 2048-byte sectors (ISO format)');
      }
      // Some dumps might have odd sizes - try to handle them
      else if (fileSize > 2352) {
        debugPrint('File has non-standard size, will try multiple sector formats');
      }
      
      // Define all formats to try - we'll be extremely thorough
      List<Map<String, dynamic>> formatOptions = [
        // For CDDA (2352 byte sectors)
        {'sectorSize': 2352, 'dataOffset': 16, 'name': 'CDDA with 16-byte header'}, // Standard CDDA
        {'sectorSize': 2352, 'dataOffset': 0, 'name': 'CDDA raw'}, // Raw CDDA
        {'sectorSize': 2352, 'dataOffset': 24, 'name': 'CDDA with 24-byte header'}, // Mode 2 XA
        
        // For ISO (2048 byte sectors)
        {'sectorSize': 2048, 'dataOffset': 0, 'name': 'ISO standard'}, // Standard ISO
        
        // For other weird formats
        {'sectorSize': 2336, 'dataOffset': 0, 'name': 'MODE2 2336-byte'}, // MODE2 without header
        {'sectorSize': 2448, 'dataOffset': 0, 'name': 'CDDA with subcode'}, // CDDA with subchannel data
      ];
      
      // If we detected a likely format, prioritize it
      if (isValidSectorSize) {
        formatOptions.insert(0, {'sectorSize': likelySectorSize, 'dataOffset': likelyDataOffset, 'name': 'Detected format'});
      }
      
      bool formatDetected = false;
      Map<String, dynamic>? detectedFormat;
      
      // Function to check the sector for system identifiers
      Future<bool> checkSectorForIdentifiers(int sectorNum, Map<String, dynamic> format) async {
        final sectorSize = format['sectorSize'] as int;
        final dataOffset = format['dataOffset'] as int;
        
        // Read the raw sector
        final sectorData = await _readRawSector(randomAccessFile, sectorNum, sectorSize, dataOffset);
        if (sectorData == null) return false;
        
        // For PC-FX, check sector 0 primarily
        if (isPCFX) {
          // Try multiple offsets to find the PC-FX identifier
          for (int offset = 0; offset < 32; offset++) {
            if (_hasPCFXIdentifierAt(sectorData, offset)) {
              debugPrint('Found PC-FX identifier at offset $offset in sector $sectorNum');
              result['system_data'] = sectorData;
              
              // Read sector 1 for program info
              final nextSectorData = await _readRawSector(randomAccessFile, sectorNum + 1, sectorSize, dataOffset);
              if (nextSectorData != null) {
                result['program_info'] = nextSectorData;
                
                // Extract program sector and size (little-endian)
                if (nextSectorData.length >= 40) {
                  int programSector = nextSectorData[32] | 
                                     (nextSectorData[33] << 8) | 
                                     (nextSectorData[34] << 16) | 
                                     (nextSectorData[35] << 24);
                  
                  int numSectors = nextSectorData[36] | 
                                  (nextSectorData[37] << 8) | 
                                  (nextSectorData[38] << 16) | 
                                  (nextSectorData[39] << 24);
                  
                  debugPrint('PC-FX program sector: $programSector, num sectors: $numSectors');
                  
                  result['program_sector'] = programSector;
                  result['num_sectors'] = numSectors;
                  
                  // Read program data if possible
                  if (programSector > 0 && numSectors > 0 && numSectors < 1024) {
                    final programData = await _readSectors(
                      randomAccessFile, 
                      programSector, 
                      numSectors,
                      sectorSize,
                      dataOffset
                    );
                    
                    if (programData != null) {
                      result['program_data'] = programData;
                    }
                  }
                }
              }
              
              return true;
            }
          }
        } 
        // For PCE, check sector 1 primarily
        else {
          // Check wider range of offsets - PCE identifier can be at different positions
          for (int offset = 0; offset < 64; offset++) {
            if (_hasPCEIdentifierAt(sectorData, offset)) {
              debugPrint('Found PCE identifier at offset $offset in sector $sectorNum');
              result['system_data'] = sectorData;
              
              // Extract title (last 22 bytes from offset 106)
              if (sectorData.length >= 128) {
                // For title, we always take 22 bytes from end of standard sector data area
                // This matches the C code behavior
                final titleOffset = 106;
                if (sectorData.length >= titleOffset + 22) {
                  final titleBytes = sectorData.sublist(titleOffset, titleOffset + 22);
                  result['title'] = utf8.decode(titleBytes, allowMalformed: true).trim();
                  debugPrint('Extracted title: ${result['title']}');
                }
              }
              
              // Extract program sector and number of sectors
              if (sectorData.length >= 4) {
                // PCE uses first 3 bytes as sector and 4th byte as count
                int programSector = sectorData[0] | (sectorData[1] << 8) | (sectorData[2] << 16);
                int numSectors = sectorData[3];
                
                debugPrint('PCE program sector: $programSector, num sectors: $numSectors');
                
                result['program_sector'] = programSector;
                result['num_sectors'] = numSectors;
                
                // Read program data
                if (programSector > 0 && numSectors > 0) {
                  final programData = await _readSectors(
                    randomAccessFile, 
                    programSector, 
                    numSectors,
                    sectorSize,
                    dataOffset
                  );
                  
                  if (programData != null) {
                    result['program_data'] = programData;
                  }
                }
              }
              
              return true;
            }
          }
          
          // Check for GameExpress CD format (ISO-9660)
          for (int offset = 0; offset < sectorData.length - 5; offset++) {
            if (_compareBytes(sectorData, offset, CD001_MARKER, 0, CD001_MARKER.length)) {
              debugPrint('Found CD001 marker at offset $offset in sector $sectorNum - likely GameExpress CD');
              
              // TODO: Implement GameExpress CD handling (locate and hash BOOT.BIN)
              // This is a special case and would require ISO-9660 filesystem parsing
              
              return false; // Not fully implemented yet
            }
          }
        }
        
        return false;
      }
      
      // Check multiple sectors in each format
      for (var format in formatOptions) {
        debugPrint('Trying format: ${format['name']} (${format['sectorSize']} bytes, offset: ${format['dataOffset']})');
        
        // For PC-FX, check sector 0 first, then other sectors
        List<int> sectorsToCheck = isPCFX 
            ? [0, 1, 16] // PC-FX primary sectors
            : [1, 0, 16]; // PCE primary sectors (sector 1 is main sector for PCE)
        
        for (int sectorNum in sectorsToCheck) {
          if (await checkSectorForIdentifiers(sectorNum, format)) {
            detectedFormat = format;
            formatDetected = true;
            break;
          }
        }
        
        if (formatDetected) break;
      }
      
      if (!formatDetected) {
        debugPrint('Could not detect disc format or find system identifier');
        return null;
      }
      
      debugPrint('Successfully detected format: ${detectedFormat!['name']}');
      return result;
    } finally {
      await randomAccessFile.close();
    }
  } catch (e, stack) {
    debugPrint('Error reading disc data: $e');
    debugPrint('Stack trace: $stack');
    return null;
  }
}


/// Check for PC Engine identifier at a specific offset
bool _hasPCEIdentifierAt(Uint8List data, int offset) {
  if (data.length < offset + PCE_IDENTIFIER.length) {
    return false;
  }
  
  // Direct byte comparison
  for (int i = 0; i < PCE_IDENTIFIER.length; i++) {
    if (data[offset + i] != PCE_IDENTIFIER[i]) {
      return false;
    }
  }
  
  return true;
}

/// Check for PC-FX identifier at a specific offset
bool _hasPCFXIdentifierAt(Uint8List data, int offset) {
  if (data.length < offset + PCFX_IDENTIFIER.length) {
    return false;
  }
  
  // Direct byte comparison
  for (int i = 0; i < PCFX_IDENTIFIER.length; i++) {
    if (data[offset + i] != PCFX_IDENTIFIER[i]) {
      return false;
    }
  }
  
  return true;
}

  /// Helper for getting a little-endian 32-bit integer from a buffer
  int _getLittleEndianInt(Uint8List data, int offset) {
    if (data.length < offset + 4) return 0;
    return data[offset] | 
           (data[offset + 1] << 8) | 
           (data[offset + 2] << 16) | 
           (data[offset + 3] << 24);
  }

  /// Check for PC Engine identifier at any potential location
  bool _hasValidPCEIdentifier(Uint8List data) {
    // The PC Engine identifier is expected at offset 32
    if (data.length < 32 + PCE_IDENTIFIER.length) return false;
    
    // First check the standard location (offset 32)
    if (_compareBytes(data, 32, PCE_IDENTIFIER, 0, PCE_IDENTIFIER.length)) {
      debugPrint('Found PCE identifier at standard offset 32');
      return true;
    }
    
    // Try other offsets in case the data is misaligned
    // In some dumps, the alignment might be off
    for (int offset = 0; offset < 64; offset++) {
      if (offset + PCE_IDENTIFIER.length <= data.length &&
          _compareBytes(data, offset, PCE_IDENTIFIER, 0, PCE_IDENTIFIER.length)) {
        debugPrint('Found PCE identifier at offset $offset');
        return true;
      }
    }
    
    return false;
  }

  /// Check for PC-FX identifier
  bool _hasValidPCFXIdentifier(Uint8List data) {
    // PC-FX identifier should be at the beginning of the data
    if (data.length < PCFX_IDENTIFIER.length) return false;
    
    // First check standard location (beginning of data)
    if (_compareBytes(data, 0, PCFX_IDENTIFIER, 0, PCFX_IDENTIFIER.length)) {
      debugPrint('Found PC-FX identifier at beginning of data');
      return true;
    }
    
    // Try other offsets in case the data is misaligned
    for (int offset = 0; offset < 32; offset++) {
      if (offset + PCFX_IDENTIFIER.length <= data.length &&
          _compareBytes(data, offset, PCFX_IDENTIFIER, 0, PCFX_IDENTIFIER.length)) {
        debugPrint('Found PC-FX identifier at offset $offset');
        return true;
      }
    }
    
    return false;
  }

  /// Read data from a CHD file
  Future<Map<String, dynamic>?> readDataFromChd() async {
    if (chdReader == null || tracks == null || tracks!.isEmpty) {
      debugPrint('CHD reader or track info is null or empty');
      return null;
    }
    
    try {
      final result = <String, dynamic>{};
      
      // Sort data tracks first for more efficient processing
      List<TrackInfo> dataTracksFirst = [...tracks!];
      dataTracksFirst.sort((a, b) {
        // Sort data tracks first
        bool aIsData = a.type.contains('MODE1') || a.type.contains('MODE2');
        bool bIsData = b.type.contains('MODE1') || b.type.contains('MODE2');
        
        if (aIsData && !bIsData) return -1;
        if (!aIsData && bIsData) return 1;
        
        // Then sort by track number
        return a.number - b.number;
      });
      
      debugPrint('Examining ${dataTracksFirst.length} tracks in CHD (sorted data tracks first)');
      
      // Find a valid track with system data
      bool foundValidData = false;
      TrackInfo? validTrack;
      Uint8List? validSectorData;
      int validSector = -1;
      
      for (final track in dataTracksFirst) {
        if (track.type.contains('MODE1') || track.type.contains('MODE2')) {
          debugPrint('Checking track ${track.number} (${track.type})');
          
          // Try specific sectors based on system
          final sectorsToTry = isPCFX 
              ? [0, 1, 16, 32] // Try multiple sectors for PC-FX
              : [1, 0, 16, 32]; // Try multiple sectors for PCE
          
          for (final sectorToCheck in sectorsToTry) {
            final sectorData = await chdReader!.readSector(filePath, track, sectorToCheck);
            if (sectorData == null) {
              continue;
            }
            
            // For MODE1/MODE2 tracks, try with and without offset
            List<Uint8List> dataVariants = [sectorData];
            
            if (track.dataOffset > 0 && sectorData.length >= track.dataOffset + 128) {
              dataVariants.add(sectorData.sublist(track.dataOffset, track.dataOffset + 128));
            }
            
            for (final dataToCheck in dataVariants) {
              bool isValid = isPCFX 
                  ? _hasValidPCFXIdentifier(dataToCheck)
                  : _hasValidPCEIdentifier(dataToCheck);
              
              if (isValid) {
                foundValidData = true;
                validTrack = track;
                validSectorData = dataToCheck;
                validSector = sectorToCheck;
                debugPrint('Found valid identifier in track ${track.number}, sector $sectorToCheck');
                break;
              }
            }
            
            if (foundValidData) break;
          }
        }
        
        if (foundValidData) break;
      }
      
      if (!foundValidData || validTrack == null || validSectorData == null) {
        debugPrint('No valid identifier found in any track or sector');
        return null;
      }
      
      result['system_data'] = validSectorData;
      
      // Get track's first sector - using startFrame from TrackInfo
      int firstTrackSector = validTrack.startFrame;
      
      // Processing specific to the system type
      if (isPCFX) {
        // For PC-FX: Read the program info from the next sector
        int nextSector = validSector + 1;
        final programInfoData = await chdReader!.readSector(
          filePath, 
          validTrack, 
          nextSector
        );
        
        if (programInfoData == null) {
          debugPrint('Failed to read program info for PCFX from CHD');
          return null;
        }
        
        // Process program info data
        Uint8List programInfo = programInfoData;
        if (validTrack.dataOffset > 0 && programInfoData.length >= validTrack.dataOffset + 128) {
          programInfo = programInfoData.sublist(validTrack.dataOffset, validTrack.dataOffset + 128);
        }
        
        // Ensure we have at least 128 bytes
        programInfo = programInfo.length > 128 
            ? programInfo.sublist(0, 128) 
            : programInfo;
            
        result['program_info'] = programInfo;
        
        // Read program sector and num sectors (little-endian)
        if (programInfo.length >= 40) {
          int programSector = _getLittleEndianInt(programInfo, 32);
          int numSectors = _getLittleEndianInt(programInfo, 36);
          
          // Add the first track sector to get absolute sector
          int absoluteProgramSector = programSector + firstTrackSector;
                      
          debugPrint('PCFX program sector: $programSector (absolute: $absoluteProgramSector), num sectors: $numSectors');
          
          result['program_sector'] = absoluteProgramSector;
          result['num_sectors'] = numSectors;
          
          // Read program data
          if (programSector > 0 && numSectors > 0 && numSectors < 1024) {
            final programData = await _readProgramDataFromChd(validTrack, absoluteProgramSector, numSectors);
            if (programData != null) {
              result['program_data'] = programData;
            }
          }
        }
      } else {
        // For PCE: Extract title and program data location
        if (validSectorData.length >= 128) {
          // Title is the last 22 bytes of the header at offset 106
          if (validSectorData.length >= 128) {
            final titleBytes = validSectorData.sublist(106, 128);
            result['title'] = utf8.decode(titleBytes, allowMalformed: true).trim();
            debugPrint('Extracted title: ${result['title']}');
          }
          
          // Get program sector and number of sectors
          int programSector = validSectorData[0] | (validSectorData[1] << 8) | (validSectorData[2] << 16);
          int numSectors = validSectorData[3];
          
          // Add the first track sector to get absolute sector
          int absoluteProgramSector = programSector + firstTrackSector;
          
          debugPrint('PCE program sector: $programSector (absolute: $absoluteProgramSector), num sectors: $numSectors');
          
          result['program_sector'] = absoluteProgramSector;
          result['num_sectors'] = numSectors;
          
          // Read program data
          if (programSector > 0 && numSectors > 0) {
            final programData = await _readProgramDataFromChd(validTrack, absoluteProgramSector, numSectors);
            if (programData != null) {
              result['program_data'] = programData;
            }
          }
        }
      }
      
      return result;
    } catch (e) {
      debugPrint('Error reading data from CHD: $e');
      return null;
    }
  }

  /// Read program data from CHD sectors
  Future<Uint8List?> _readProgramDataFromChd(TrackInfo track, int startSector, int numSectors) async {
    try {
      // Read up to a reasonable maximum (security check)
      const maxSectors = 1024; // Limit to 1024 sectors max
      final sectorsToRead = numSectors > 0 && numSectors < maxSectors ? numSectors : maxSectors;
      
      debugPrint('Reading $sectorsToRead sectors starting at sector $startSector from CHD');
      
      // Create a buffer for all sectors
      final buffer = Uint8List(sectorsToRead * SECTOR_SIZE);
      int totalRead = 0;
      
      // Read each sector
      for (int i = 0; i < sectorsToRead; i++) {
        final sectorData = await chdReader!.readSector(filePath, track, startSector + i);
        
        if (sectorData == null) {
          debugPrint('Failed to read sector ${startSector + i}');
          break;
        }
        
        // Process the data portion
        Uint8List dataToAdd;
        if (track.dataOffset > 0 && sectorData.length >= track.dataOffset + SECTOR_SIZE) {
          // If the track has a header offset, skip it
          dataToAdd = sectorData.sublist(track.dataOffset, track.dataOffset + SECTOR_SIZE);
        } else {
          // Otherwise use as much of the sector as we can
          dataToAdd = sectorData.length > SECTOR_SIZE 
              ? sectorData.sublist(0, SECTOR_SIZE) 
              : sectorData;
        }
        
        // Add this sector's data to our buffer
        final bytesToCopy = dataToAdd.length > SECTOR_SIZE ? SECTOR_SIZE : dataToAdd.length;
        buffer.setRange(totalRead, totalRead + bytesToCopy, dataToAdd);
        totalRead += bytesToCopy;
      }
      
      if (totalRead == 0) {
        return null;
      }
      
      // Return only the portion we actually read
      return buffer.sublist(0, totalRead);
    } catch (e) {
      debugPrint('Error reading program data from CHD: $e');
      return null;
    }
  }

  /// Generate hash from the data based on RetroAchievements standards
 String generateHash(Map<String, dynamic> data) {
  if (!isPCFX) {
    // PC Engine CD
    final buffer = <int>[];
    
    // Start with the title (22 bytes from offset 106 of system data)
    if (data.containsKey('system_data')) {
      final systemData = data['system_data'] as Uint8List;
      if (systemData.length >= 128) {
        // Extract and add the title (raw bytes) - this is critical for matching C code
        final titleBytes = systemData.sublist(106, 128);
        buffer.addAll(titleBytes);
        debugPrint('Added title bytes to hash buffer: ${titleBytes.length} bytes');
      }
    }
    
    // Then add the program data
    if (data.containsKey('program_data')) {
      final programData = data['program_data'] as Uint8List;
      buffer.addAll(programData);
      debugPrint('Added ${programData.length} bytes of program data to hash buffer');
    }
    
    // Hash the combined buffer
    if (buffer.isNotEmpty) {
      final result = md5.convert(buffer).toString();
      debugPrint('Generated PCE CD hash with combined buffer of ${buffer.length} bytes');
      return result;
    }
  } else {
    // PC-FX
    final buffer = <int>[];
    
    // First add program info (128 bytes from sector 1)
    if (data.containsKey('program_info')) {
      final programInfo = data['program_info'] as Uint8List;
      // Ensure we take no more than 128 bytes for program info
      final bytesToAdd = programInfo.length > 128 ? 128 : programInfo.length;
      buffer.addAll(programInfo.sublist(0, bytesToAdd));
      debugPrint('Added $bytesToAdd bytes of program info to hash buffer');
    }
    
    // Then add the program data
    if (data.containsKey('program_data')) {
      final programData = data['program_data'] as Uint8List;
      buffer.addAll(programData);
      debugPrint('Added ${programData.length} bytes of program data to hash buffer');
    }
    
    // Hash the combined buffer
    if (buffer.isNotEmpty) {
      final result = md5.convert(buffer).toString();
      debugPrint('Generated PC-FX hash with combined buffer of ${buffer.length} bytes');
      return result;
    }
  }
  
  debugPrint('ERROR: Could not generate hash - missing required data');
  return '';
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
}

/// Class to process PC Engine CD and PC-FX files in a separate isolate
class IsolatePCEPCFXProcessor {
  /// Process a PC Engine CD/PC-FX file in an isolate and return the hash
  static Future<String?> processFile(String filePath, bool isPCFX) async {
    final receivePort = ReceivePort();
    final completer = Completer<String?>();
    
    // Create and spawn the isolate
    final isolate = await Isolate.spawn(
      _processFileInIsolate,
      PCEPCFXProcessRequest(filePath, receivePort.sendPort, isPCFX),
      debugName: isPCFX ? 'PC-FX Processor' : 'PC Engine CD Processor',
    );
    
    // Listen for messages from the isolate
    receivePort.listen((message) {
      if (message is PCEPCFXProcessResponse) {
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
  static void _processFileInIsolate(PCEPCFXProcessRequest request) async {
    final sendPort = request.sendPort;
    final filePath = request.filePath;
    final isPCFX = request.isPCFX;
    final fileExt = filePath.toLowerCase();
    
    try {
      Map<String, dynamic>? discData;
      
      debugPrint('Processing ${isPCFX ? "PC-FX" : "PC Engine CD"} file: $filePath');
      
      // Skip M3U files
      if (fileExt.endsWith('.m3u')) {
        sendPort.send(PCEPCFXProcessResponse(
          filePath: filePath,
          error: 'M3U files are ignored',
        ));
        return;
      }
      
      // Handle different file types
      if (fileExt.endsWith('.chd')) {
        // Handle CHD files
        final chdReader = ChdReader();
        
        if (!chdReader.isInitialized) {
          sendPort.send(PCEPCFXProcessResponse(
            filePath: filePath,
            error: 'Failed to initialize CHD library',
          ));
          return;
        }
        
        // Process the CHD file
        final result = await chdReader.processChdFile(filePath);
        
        if (!result.isSuccess) {
          sendPort.send(PCEPCFXProcessResponse(
            filePath: filePath,
            error: 'Error processing CHD file: ${result.error}',
          ));
          return;
        }
        
        // Check if it has tracks
        if (result.tracks.isEmpty) {
          sendPort.send(PCEPCFXProcessResponse(
            filePath: filePath,
            error: 'No tracks found in CHD file',
          ));
          return;
        }
        
        debugPrint('CHD processed, found ${result.tracks.length} tracks');
        
        // Create the reader
        final reader = PCEPCFXReader(
          filePath, 
          isPCFX,
          chdReader: chdReader,
          tracks: result.tracks,
        );
        
        // Read the data
        discData = await reader.readDataFromChd();
      } else if (fileExt.endsWith('.cue')) {
        // For CUE files, find and open the associated BIN file
        final cueFile = File(filePath);
        if (!await cueFile.exists()) {
          sendPort.send(PCEPCFXProcessResponse(
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
                
                // Create reader for BIN file
                final reader = PCEPCFXReader(binPath, isPCFX);
                discData = await reader.readDataFromBinIso();
                
                if (discData == null) {
                  sendPort.send(PCEPCFXProcessResponse(
                    filePath: filePath,
                    error: 'Could not extract disc data from associated BIN file',
                  ));
                  return;
                }
              } else {
                sendPort.send(PCEPCFXProcessResponse(
                  filePath: filePath,
                  error: 'Associated BIN file not found: $binPath',
                ));
                return;
              }
            }
          } else {
            sendPort.send(PCEPCFXProcessResponse(
              filePath: filePath,
              error: 'Could not find FILE statement in CUE file',
            ));
            return;
          }
        } catch (e) {
          sendPort.send(PCEPCFXProcessResponse(
            filePath: filePath,
            error: 'Error processing CUE file: $e',
          ));
          return;
        }
      } else if (fileExt.endsWith('.iso') || fileExt.endsWith('.bin') || fileExt.endsWith('.img')) {
        // Handle BIN/ISO files directly
        final reader = PCEPCFXReader(filePath, isPCFX);
        discData = await reader.readDataFromBinIso();
      } else {
        sendPort.send(PCEPCFXProcessResponse(
          filePath: filePath,
          error: 'Unsupported file format',
        ));
        return;
      }
      
      if (discData == null) {
        sendPort.send(PCEPCFXProcessResponse(
          filePath: filePath,
          error: 'Failed to read disc data',
        ));
        return;
      }
      
      // Generate hash
      final reader = PCEPCFXReader(filePath, isPCFX);
      final hash = reader.generateHash(discData);
      
      if (hash.isEmpty) {
        sendPort.send(PCEPCFXProcessResponse(
          filePath: filePath,
          error: 'Failed to generate hash',
        ));
        return;
      }
      
      debugPrint('Generated hash: $hash');
      
      // Send the final result
      sendPort.send(PCEPCFXProcessResponse(
        filePath: filePath,
        hash: hash,
      ));
    } catch (e, stackTrace) {
      debugPrint('Error in isolate: $e');
      debugPrint('Stack trace: $stackTrace');
      
      sendPort.send(PCEPCFXProcessResponse(
        filePath: filePath,
        error: 'Exception: $e',
      ));
    }
  }
}

/// Main integration class for PC Engine CD/PC-FX hashing
class PCEPCFXHashIntegration {
  /// Hash files in the given folders
  Future<Map<String, String>> hashFilesInFolders(
    List<String> folders, 
    bool isPCFX, 
    {void Function(int current, int total)? progressCallback}
  ) async {
    final Map<String, String> hashes = {};
    final validExtensions = ['.iso', '.bin', '.img', '.chd', '.cue'];
    
    try {
      // Get all files with valid extensions
      final allFiles = await _findFilesWithExtensions(folders, validExtensions);
      final total = allFiles.length;
      
      debugPrint('Found ${allFiles.length} files to process');
      
      // Process each file
      for (int i = 0; i < allFiles.length; i++) {
        final filePath = allFiles[i];
        
        try {
          if (filePath.toLowerCase().endsWith('.m3u')) {
            debugPrint('Skipping M3U file: $filePath');
            continue;
          }
          
          // Process the file
          final hash = await IsolatePCEPCFXProcessor.processFile(filePath, isPCFX);
          
          if (hash != null && hash.isNotEmpty) {
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