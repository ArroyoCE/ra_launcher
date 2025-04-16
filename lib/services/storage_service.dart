// lib/services/storage_service.dart

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Provider for the storage service
final storageServiceProvider = Provider<StorageService>((ref) {
  return StorageService();
});

/// Provider for getting centralized application directory paths
final appDirectoriesProvider = FutureProvider<Map<String, String>>((ref) async {
  final storageService = ref.watch(storageServiceProvider);
  final baseDir = await storageService._baseDir;
  
  // Create common subdirectories
  final userImages = await storageService.getOrCreateSubdirectory('user_images');
  final gameImages = await storageService.getOrCreateSubdirectory('game_images');
  final gameData = await storageService.getOrCreateSubdirectory('game_data');
  final cache = await storageService.getOrCreateSubdirectory('cache');
  
  return {
    'baseDir': baseDir.path,
    'userImages': userImages.path,
    'gameImages': gameImages.path,
    'gameData': gameData.path,
    'cache': cache.path,
  };
});

/// Service for handling file storage operations
class StorageService {
  /// Get the base directory for app storage
Future<Directory> get _baseDir async {
  // Get the documents directory
  final documentsDir = await getApplicationDocumentsDirectory();
  
  // Create a custom folder inside Documents
  final customDir = Directory('${documentsDir.path}/RALauncher');
  
  // Create the directory if it doesn't exist yet
  if (!await customDir.exists()) {
    await customDir.create(recursive: true);
  }
  
  return customDir;
}

  /// Create a subdirectory if it doesn't exist
  Future<Directory> getOrCreateSubdirectory(String subDirName) async {
    final base = await _baseDir;
    final dir = Directory('${base.path}/$subDirName');
    
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    
    return dir;
  }

  /// Save an image from a URL to the local storage
  /// Returns the path to the saved image
  Future<String?> saveImageFromUrl(String imageUrl, String subDir, [String? customFileName]) async {
    try {
      // Ensure URL has proper host if it's just a path
      final fullUrl = imageUrl.startsWith('http') 
          ? imageUrl 
          : 'https://retroachievements.org$imageUrl';
          
      final response = await http.get(Uri.parse(fullUrl));
      
      if (response.statusCode == 200) {
        final dir = await getOrCreateSubdirectory(subDir);
        final fileName = customFileName ?? imageUrl.split('/').last;
        final filePath = '${dir.path}/$fileName';
        
        // Write file
        final file = File(filePath);
        await file.writeAsBytes(response.bodyBytes);
        
        return filePath;
      }
    } catch (e) {
      debugPrint('Error saving image: $e');
    }
    return null;
  }

  /// Save user profile picture
  Future<String?> saveUserProfilePicture(String imageUrl, String username) async {
    final extension = imageUrl.contains('.') ? imageUrl.split('.').last : 'jpg';
    final fileName = 'profile_$username.$extension';
    return saveImageFromUrl(imageUrl, 'user_images', fileName);
  }

  /// Save game image
  Future<String?> saveGameImage(String imageUrl, int gameId) async {
    final fileName = 'game_$gameId.${imageUrl.split('.').last}';
    return saveImageFromUrl(imageUrl, 'game_images', fileName);
  }

  /// Save JSON data to a file
  Future<String?> saveJsonData(Map<String, dynamic> data, String subDir, String fileName) async {
    try {
      final dir = await getOrCreateSubdirectory(subDir);
      final filePath = '${dir.path}/$fileName.json';
      
      final file = File(filePath);
      await file.writeAsString(jsonEncode(data));
      
      return filePath;
    } catch (e) {
      debugPrint('Error saving JSON data: $e');
      return null;
    }
  }

  /// Save cache data (for API responses, etc.)
  Future<String?> saveCacheData(String key, Map<String, dynamic> data) async {
    return saveJsonData(data, 'cache', key);
  }
  
  /// Save user profile data to cache
  Future<String?> saveUserProfileCache(String username, Map<String, dynamic> profileData) async {
    return saveJsonData(profileData, 'user_data', username);
  }

  /// Read JSON data from a file
  Future<Map<String, dynamic>?> readJsonData(String subDir, String fileName) async {
    try {
      final dir = await getOrCreateSubdirectory(subDir);
      final filePath = '${dir.path}/$fileName.json';
      
      final file = File(filePath);
      if (await file.exists()) {
        final jsonString = await file.readAsString();
        return jsonDecode(jsonString) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('Error reading JSON data: $e');
    }
    return null;
  }

  /// Read cache data
  Future<Map<String, dynamic>?> readCacheData(String key) async {
    return readJsonData('cache', key);
  }

  /// Check if a file exists
  Future<bool> fileExists(String path) async {
    final file = File(path);
    return await file.exists();
  }

  /// Delete a file
  Future<bool> deleteFile(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
        return true;
      }
    } catch (e) {
      debugPrint('Error deleting file: $e');
    }
    return false;
  }

  /// Clear cache
  Future<void> clearCache() async {
    try {
      final dir = await getOrCreateSubdirectory('cache');
      await dir.delete(recursive: true);
    } catch (e) {
      debugPrint('Error clearing cache: $e');
    }
  }
}