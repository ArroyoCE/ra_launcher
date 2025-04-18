// lib/services/hashing/nds/nds_hash_integration.dart
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

class NdsHashIntegration {
  static const bool _debug = true; // Enable for debugging

  // NDS ROM header offsets and sizes - match RetroAchievements hashing
  static const int _headerSize = 0x160; // First 0x160 bytes, not 0x200
  static const int _arm9RomOffsetAddr = 0x20; // ARM9 code location in header
  static const int _arm9RomSizeAddr = 0x2C;   // ARM9 code size in header
  static const int _arm7RomOffsetAddr = 0x30; // ARM7 code location in header
  static const int _arm7RomSizeAddr = 0x3C;   // ARM7 code size in header
  static const int _iconOffsetAddr = 0x68;    // Icon/title offset in header
  static const int _iconSize = 0xA00;         // Icon/title data size

  // Max sizes to prevent excessive memory usage
  static const int _maxCodeSize = 8 * 1024 * 1024; // 8MB max per processor code

  // Valid NDS ROM extensions
  static final List<String> _validExtensions = ['.nds', '.ids', '.dsi'];

  /// Hash NDS files in the provided folders
  Future<Map<String, String>> hashNdsFilesInFolders(
    List<String> folders, {
    Function(int current, int total)? progressCallback,
  }) async {
    final Map<String, String> hashes = {};
    final List<FileSystemEntity> allFiles = [];

    // First, collect all files from folders
    for (final folder in folders) {
      try {
        final directory = Directory(folder);
        if (!await directory.exists()) {
          debugPrint('Directory does not exist: $folder');
          continue;
        }

        final files = await directory
            .list(recursive: true)
            .where((entity) => entity is File && _isValidNdsFile(entity.path))
            .toList();

        allFiles.addAll(files);
      } catch (e) {
        debugPrint('Error scanning directory $folder: $e');
      }
    }

    // Process all files
    final int totalFiles = allFiles.length;
    debugPrint('Found $totalFiles NDS files to hash');
    
    int processedFiles = 0;
    for (final file in allFiles) {
      try {
        final String filePath = file.path;
        final String hash = await _hashNdsFile(filePath);
        
        if (hash.isNotEmpty) {
          hashes[filePath] = hash;
        }
        
        // Update progress
        processedFiles++;
        if (progressCallback != null) {
          progressCallback(processedFiles, totalFiles);
        } else if (processedFiles % 10 == 0 || processedFiles == totalFiles) {
          debugPrint('Processed $processedFiles/$totalFiles NDS files');
        }
      } catch (e) {
        debugPrint('Error hashing file ${file.path}: $e');
      }
    }

    debugPrint('Successfully hashed ${hashes.length} NDS files');
    return hashes;
  }

  /// Check if the file has a valid NDS extension
  bool _isValidNdsFile(String filePath) {
    final extension = path.extension(filePath).toLowerCase();
    return _validExtensions.contains(extension);
  }

  /// Hash a single NDS file according to RetroAchievements standard
  Future<String> _hashNdsFile(String filePath) async {
    try {
      final file = File(filePath);
      final fileSize = await file.length();
      
      // File is too small to be a valid NDS ROM (at least header + some data)
      if (fileSize < 0x4000) {
        debugPrint('File too small to be a valid NDS ROM: $filePath');
        return '';
      }

      final RandomAccessFile raf = await file.open(mode: FileMode.read);
      
      try {
        // Read the header (first 0x160 bytes)
        await raf.setPosition(0);
        final Uint8List header = await raf.read(_headerSize);
        if (_debug) debugPrint('Reading header (0x${_headerSize.toRadixString(16)} bytes)');
        
        // Create MD5 hasher
        const md5Hasher = md5;
        final buffer = BytesBuilder();
        
        // 1. Add the header (first 0x160 bytes)
        if (_debug) debugPrint('Adding header (0x${_headerSize.toRadixString(16)} bytes)');
        buffer.add(header);
        
        // 2. Get ARM9 boot code location and size
        final arm9Offset = _readInt32(header, _arm9RomOffsetAddr);
        var arm9Size = _readInt32(header, _arm9RomSizeAddr);
        
        // Sanity check ARM9 size
        if (arm9Size <= 0 || arm9Size > _maxCodeSize || arm9Offset + arm9Size > fileSize) {
          if (_debug) debugPrint('Invalid ARM9 data: offset=0x${arm9Offset.toRadixString(16)}, size=0x${arm9Size.toRadixString(16)}');
          arm9Size = 0;
        } else {
          // Read and add ARM9 code
          await raf.setPosition(arm9Offset);
          final arm9Data = await raf.read(arm9Size);
          if (_debug) debugPrint('Adding ARM9 code: offset=0x${arm9Offset.toRadixString(16)}, size=0x${arm9Size.toRadixString(16)}');
          buffer.add(arm9Data);
        }
        
        // 3. Get ARM7 boot code location and size
        final arm7Offset = _readInt32(header, _arm7RomOffsetAddr);
        var arm7Size = _readInt32(header, _arm7RomSizeAddr);
        
        // Sanity check ARM7 size
        if (arm7Size <= 0 || arm7Size > _maxCodeSize || arm7Offset + arm7Size > fileSize) {
          if (_debug) debugPrint('Invalid ARM7 data: offset=0x${arm7Offset.toRadixString(16)}, size=0x${arm7Size.toRadixString(16)}');
          arm7Size = 0;
        } else {
          // Read and add ARM7 code
          await raf.setPosition(arm7Offset);
          final arm7Data = await raf.read(arm7Size);
          if (_debug) debugPrint('Adding ARM7 code: offset=0x${arm7Offset.toRadixString(16)}, size=0x${arm7Size.toRadixString(16)}');
          buffer.add(arm7Data);
        }
        
        // 4. Get icon/title data
        final iconOffset = _readInt32(header, _iconOffsetAddr);
        if (iconOffset > 0 && iconOffset < fileSize && iconOffset + _iconSize <= fileSize) {
          await raf.setPosition(iconOffset);
          final iconData = await raf.read(_iconSize);
          if (_debug) debugPrint('Adding icon data: offset=0x${iconOffset.toRadixString(16)}, size=0x${_iconSize.toRadixString(16)}');
          buffer.add(iconData);
        } else {
          if (_debug) debugPrint('Invalid icon offset: 0x${iconOffset.toRadixString(16)}');
        }
        
        // Calculate MD5 hash
        final digest = md5Hasher.convert(buffer.toBytes());
        final hashString = digest.toString();
        if (_debug) debugPrint('Final hash: $hashString');
        return hashString;
      } finally {
        await raf.close();
      }
    } catch (e) {
      debugPrint('Error processing NDS file $filePath: $e');
      return '';
    }
  }
  
  /// Read a 32-bit little-endian integer from byte array at specified offset
  int _readInt32(Uint8List data, int offset) {
    if (offset + 3 >= data.length) {
      return 0;
    }
    return data[offset] | 
           (data[offset + 1] << 8) | 
           (data[offset + 2] << 16) | 
           (data[offset + 3] << 24);
  }
}