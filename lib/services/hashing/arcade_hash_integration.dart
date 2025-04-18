// lib/services/hashing/arcade/arcade_hash_integration.dart
import 'dart:io';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

/// Class to handle arcade ROM hashing
class ArcadeHashIntegration {
  /// Hashes arcade ROM files found in the provided folders.
  /// 
  /// For arcade ROMs, we hash only the filename without extension.
  /// This matches RetroAchievements' hashing method for arcade.
  /// 
  /// [folders] - List of folder paths to search for files
  /// [progressCallback] - Optional callback to report progress
  /// 
  /// Returns a map where keys are file paths and values are the calculated hash strings.
  Future<Map<String, String>> hashArcadeFilesInFolders(
    List<String> folders,
    {Function(int current, int total)? progressCallback}
  ) async {
    final Map<String, String> arcadeHashes = {};
    final List<FileSystemEntity> filesToProcess = [];
    
    // First pass: collect all files to process
    for (final folderPath in folders) {
      final directory = Directory(folderPath);
      
      if (await directory.exists()) {
        await for (final entity in directory.list(recursive: true)) {
          if (entity is File) {
            final extension = path.extension(entity.path).toLowerCase();
            
            // Only process zip and 7z files for arcade
            if (extension == '.zip' || extension == '.7z') {
              filesToProcess.add(entity);
            }
          }
        }
      }
    }
    
    debugPrint('Found ${filesToProcess.length} arcade ROM files to hash');
    
    // Second pass: process all files
    int processedCount = 0;
    final int totalFiles = filesToProcess.length;
    
    for (final entity in filesToProcess) {
      if (entity is File) {
        // Get just the filename without extension
        final filename = path.basenameWithoutExtension(entity.path);
        
        // Hash just the filename
        final hashBytes = md5.convert(utf8.encode(filename)).bytes;
        final hash = hashBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
        
        arcadeHashes[entity.path] = hash;
        
        // Log progress
        processedCount++;
        if (processedCount % 10 == 0 || processedCount == totalFiles) {
          debugPrint('Processed $processedCount/$totalFiles arcade ROMs');
        }
        
        // Report progress if callback is provided
        if (progressCallback != null) {
          progressCallback(processedCount, totalFiles);
        }
        
        // Occasionally log details for debugging
        if (processedCount % 50 == 0 || processedCount < 5) {
          debugPrint('Hashed arcade file: ${entity.path} -> $hash (from filename: $filename)');
        }
      }
    }
    
    debugPrint('Completed arcade ROM hashing with ${arcadeHashes.length} hashes');
    return arcadeHashes;
  }
  
  /// Hashes a single arcade ROM file.
  /// Returns the hash value or null if an error occurs.
  static Future<String?> hashSingleFile(String filePath) async {
    try {
      final extension = path.extension(filePath).toLowerCase();
      
      if (extension != '.zip' && extension != '.7z') {
        debugPrint('File is not a supported arcade ROM format: $filePath');
        return null;
      }
      
      // Get just the filename without extension
      final filename = path.basenameWithoutExtension(filePath);
      
      // Hash the filename
      final hashBytes = md5.convert(utf8.encode(filename)).bytes;
      final hash = hashBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      
      return hash;
    } catch (e) {
      debugPrint('Error hashing arcade file $filePath: $e');
      return null;
    }
  }
}