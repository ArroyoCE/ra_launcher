import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;
import 'package:retroachievements_organizer/services/hashing/CHD/chd_read_common.dart';

import 'pce_cd_chd_handler.dart';

class PCECDHashIntegration {
  late final ChdReader _chdReader;
  late final PCECDChdHandler _chdHandler;
  
  PCECDHashIntegration() {
    _chdReader = ChdReader();
    _chdHandler = PCECDChdHandler(_chdReader);
  }
  
  Future<Map<String, String>> hashPCECDFilesInFolders(List<String> folders) async {
    final Map<String, String> hashes = {};
    
    for (final folder in folders) {
      final directory = Directory(folder);
      if (!await directory.exists()) continue;
      
      print('Scanning directory: $folder for PC Engine CD games');
      
      await for (final fileEntity in directory.list(recursive: true)) {
        if (fileEntity is File) {
          final String filePath = fileEntity.path;
          final String ext = path.extension(filePath).toLowerCase();
          
          if (ext == '.cue') {
            try {
              print('Processing cue file: $filePath');
              final hash = await hashPCECDFromCue(filePath);
              if (hash != null && hash.isNotEmpty) {
                hashes[filePath] = hash;
                print('Successfully hashed PC Engine CD: $filePath => $hash');
              } else {
                print('Failed to hash PC Engine CD: $filePath');
              }
            } catch (e) {
              print('Error processing $filePath: $e');
            }
          } else if (ext == '.chd') {
            try {
              // Check if CHD reader is initialized
              if (!_chdReader.isInitialized) {
                print('CHD reader not initialized, skipping CHD file: $filePath');
                continue;
              }
              
              print('Processing CHD file: $filePath');
              
              // First try hashing normally
              final hash = await _chdHandler.hashPCECDFromChd(filePath);
              if (hash != null && hash.isNotEmpty) {
                hashes[filePath] = hash;
                print('Successfully hashed PC Engine CD (CHD): $filePath => $hash');
              } else {
                print('Failed to hash PC Engine CD (CHD): $filePath');
                
                // If normal hashing fails, try debug mode for this file
                print('Running debug mode for CHD file...');
                await _chdHandler.debugChdFile(filePath);
              }
            } catch (e) {
              print('Error processing CHD file $filePath: $e');
            }
          }
        }
      }
    }
    
    return hashes;
  }

  Future<Map<String, dynamic>?> parseCueFile(String cuePath) async {
    final cueFile = File(cuePath);
    if (!await cueFile.exists()) return null;
    
    final lines = await cueFile.readAsLines();
    final cueDir = path.dirname(cuePath);
    
    String? binFile;
    int trackNumber = 0;
    String trackType = '';
    int indexOffset = 0;
    
    // Process cue file line by line
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      
      // Extract FILE directive
      if (line.startsWith('FILE ')) {
        // Parse quoted filename
        final quoteStart = line.indexOf('"');
        final quoteEnd = line.lastIndexOf('"');
        
        if (quoteStart >= 0 && quoteEnd > quoteStart) {
          binFile = line.substring(quoteStart + 1, quoteEnd);
        } else {
          // Handle unquoted filenames
          final parts = line.split(' ');
          if (parts.length >= 2) {
            binFile = parts[1];
          }
        }
      }
      
      // Extract TRACK directive
      if (line.startsWith('TRACK ')) {
        final parts = line.split(' ');
        if (parts.length >= 3) {
          trackNumber = int.tryParse(parts[1]) ?? 0;
          trackType = parts[2];
          
          // For data tracks, we need to know the format for sector size calculation
          if (trackType == 'MODE1/2352' || trackType == 'MODE1/2048') {
            // If we've found a data track, look for INDEX directive
            for (int j = i + 1; j < lines.length && j < i + 10; j++) {
              final indexLine = lines[j].trim();
              if (indexLine.startsWith('INDEX 01 ')) {
                final timeParts = indexLine.split(' ').last.split(':');
                if (timeParts.length == 3) {
                  final minutes = int.tryParse(timeParts[0]) ?? 0;
                  final seconds = int.tryParse(timeParts[1]) ?? 0;
                  final frames = int.tryParse(timeParts[2]) ?? 0;
                  
                  // Convert to sector offset (75 frames per second)
                  indexOffset = (minutes * 60 * 75) + (seconds * 75) + frames;
                  
                  // If we've found a data track and its index, return the info
                  if (binFile != null) {
                    final binPath = path.isAbsolute(binFile) ? binFile : path.join(cueDir, binFile);
                    
                    print('Found data track $trackNumber ($trackType) in $binFile');
                    print('Index offset: $indexOffset sectors');
                    
                    return {
                      'binPath': binPath,
                      'trackNumber': trackNumber,
                      'trackType': trackType,
                      'indexOffset': indexOffset
                    };
                  }
                }
              }
            }
          }
        }
      }
    }
    
    // If no specific data track found, use the first file as a fallback
    if (binFile != null) {
      final binPath = path.isAbsolute(binFile) ? binFile : path.join(cueDir, binFile);
      print('No data track found, using first file: $binFile');
      return {
        'binPath': binPath,
        'trackNumber': 1,
        'trackType': 'MODE1/2352', // Assume default
        'indexOffset': 0
      };
    }
    
    return null;
  }

  Future<String?> hashPCECDFromCue(String cuePath) async {
    try {
      final trackInfo = await parseCueFile(cuePath);
      if (trackInfo == null) {
        print('Could not parse cue file: $cuePath');
        return null;
      }
      
      final binPath = trackInfo['binPath'] as String;
      final trackType = trackInfo['trackType'] as String;
      final indexOffset = trackInfo['indexOffset'] as int;
      
      // Determine sector size based on track type
      final sectorSize = trackType == 'MODE1/2048' ? 2048 : 2352;
      final dataOffset = trackType == 'MODE1/2048' ? 0 : 16; // Raw has 16-byte header
      
      print('Opening bin file: $binPath with sector size: $sectorSize');
      
      // Now hash from the bin file
      return await hashPCECDFromBin(binPath, sectorSize, dataOffset, indexOffset, trackType);
    } catch (e) {
      print('Error in hashPCECDFromCue: $e');
      return null;
    }
  }
  
  // Debug a CHD file to help diagnose issues
  Future<void> debugChdFile(String chdPath) async {
    if (!_chdReader.isInitialized) {
      print('CHD reader not initialized, cannot debug CHD file.');
      return;
    }
    
    await _chdHandler.debugChdFile(chdPath);
  }
  
  Future<String?> hashPCECDFromBin(String binPath, int sectorSize, int dataOffset, int indexOffset, String trackType) async {
    final binFile = File(binPath);
    if (!await binFile.exists()) {
      print('Bin file does not exist: $binPath');
      return null;
    }
    
    final file = await binFile.open(mode: FileMode.read);
    try {
      // Calculate first track sector
      final firstTrackSector = indexOffset;
      
      // In PC Engine CD, we need to check sector 1 (relative to first track sector)
      final sectorToCheck = firstTrackSector + 1;
      final sectorPosition = sectorToCheck * sectorSize;
      
      // Seek to the sector position
      await file.setPosition(sectorPosition);
      
      // Read the whole sector for inspection
      final sectorBuffer = Uint8List(sectorSize);
      final bytesRead = await file.readInto(sectorBuffer);
      
      if (bytesRead < sectorSize) {
        print('Not enough data read for sector check');
        return null;
      }
      
      // Extract the data portion of the sector
      final dataBuffer = sectorBuffer.sublist(dataOffset);
      
      // Debug print a larger portion around where the marker should be
      print('Checking for PC Engine CD marker in sector data:');
      final debugRange = dataBuffer.sublist(0, 100);
      print('First 100 bytes in hex: ${debugRange.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');
      
      // Check for PC Engine CD marker
      final marker = "PC Engine CD-ROM SYSTEM";
      bool isPCECD = false;
      int markerPos = -1;
      
      // More flexible search for the marker
      for (int offset = 0; offset <= 40; offset++) {
        if (offset + marker.length <= dataBuffer.length) {
          bool match = true;
          for (int i = 0; i < marker.length; i++) {
            if (dataBuffer[offset + i] != marker.codeUnitAt(i)) {
              match = false;
              break;
            }
          }
          
          if (match) {
            isPCECD = true;
            markerPos = offset;
            break;
          }
        }
      }
      
      if (isPCECD) {
        print('Found PC Engine CD marker at offset $markerPos!');
        
        // Extract title (22 bytes) at offset 106 from the beginning of the data
        int titleOffset = 106;
        
        // If marker position is not at standard position (32), adjust title offset
        if (markerPos != 32 && markerPos > 0) {
          titleOffset = markerPos + marker.length + (106 - (32 + marker.length));
        }
        
        // Ensure titleOffset is within bounds
        if (titleOffset + 22 > dataBuffer.length) {
          titleOffset = dataBuffer.length - 22;
        }
        
        final titleBytes = dataBuffer.sublist(titleOffset, titleOffset + 22);
        
        // Title in ASCII
        final title = String.fromCharCodes(titleBytes.where((b) => b >= 32 && b <= 126)).trim();
        print('PC Engine CD title: "$title"');
        print('Title bytes: ${titleBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');
        
        // Determine program sector and size (always at beginning of data)
        final programSector = (dataBuffer[0] << 16) + 
                            (dataBuffer[1] << 8) + 
                            dataBuffer[2];
                            
        final numSectors = dataBuffer[3];
        
        print('Program starts at sector $programSector, size: $numSectors sectors');
        
        // Calculate absolute sector position
        final absoluteProgramSector = firstTrackSector + programSector;
        
        // Create MD5 context for hashing
        final dataToHash = <int>[];
        
        // First add title bytes exactly as in C implementation
        dataToHash.addAll(titleBytes);
        
        // Now read and hash the program sectors
        for (int i = 0; i < numSectors; i++) {
          // Calculate the sector position
          final sectorPosition = (absoluteProgramSector + i) * sectorSize;
          
          // Seek to that position
          await file.setPosition(sectorPosition);
          
          // Read the whole sector
          final programSectorBuffer = Uint8List(sectorSize);
          final bytesRead = await file.readInto(programSectorBuffer);
          if (bytesRead < sectorSize) {
            print('Warning: Incomplete read at sector ${absoluteProgramSector + i}');
            break;
          }
          
          // Extract the data portion (always 2048 bytes)
          final programData = programSectorBuffer.sublist(dataOffset, dataOffset + 2048);
          
          // Add to hash data
          dataToHash.addAll(programData);
        }
        
        // Compute final MD5 hash - use Dart's native implementation
        final digest = md5.convert(dataToHash);
        final hash = digest.toString();
        
        return hash;
      } 
      else {
        print('PC Engine CD marker not found, checking for GameExpress CD...');
        // TO DO:
        // Similar code for GameExpress CDs would go here
        // This would involve parsing ISO9660 to find BOOT.BIN
        
        print('Not a PC Engine CD or GameExpress CD');
        return null;
      }
    } finally {
      await file.close();
    }
  }
}