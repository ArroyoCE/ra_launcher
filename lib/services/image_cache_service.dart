// lib/services/image_cache_service.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retroachievements_organizer/services/storage_service.dart';

// Provider for the image cache service
final imageCacheServiceProvider = Provider<ImageCacheService>((ref) {
  final storageService = ref.watch(storageServiceProvider);
  return ImageCacheService(storageService);
});

class ImageCacheService {
  final StorageService _storageService;
  
  ImageCacheService(this._storageService);
  
  // Get a widget for a cached user profile image
  Future<Widget> getUserProfileImage(String username, {double width = 50, double height = 50}) async {
    try {
      final userImagesDir = await _storageService.getOrCreateSubdirectory('user_images');
      
      // Look for the profile image
      final dir = Directory(userImagesDir.path);
      final List<FileSystemEntity> entities = await dir.list().toList();
      
      for (var entity in entities) {
        if (entity is File && entity.path.contains('profile_$username')) {
          return Image.file(
            File(entity.path),
            width: width,
            height: height,
            fit: BoxFit.cover,
          );
        }
      }
      
      // If not found, return a placeholder
      return CircleAvatar(
        radius: width / 2,
        backgroundColor: Colors.grey,
        child: Text(
          username.substring(0, 1).toUpperCase(),
          style: TextStyle(
            color: Colors.white,
            fontSize: width / 2,
          ),
        ),
      );
    } catch (e) {
      // Return a placeholder on error
      return CircleAvatar(
        radius: width / 2,
        backgroundColor: Colors.grey,
        child: Text(
          username.substring(0, 1).toUpperCase(),
          style: TextStyle(
            color: Colors.white,
            fontSize: width / 2,
          ),
        ),
      );
    }
  }
  
  // Get a widget for a cached game icon
  Future<Widget> getGameIconImage(int gameId, {double width = 50, double height = 50}) async {
    try {
      final gameImagesDir = await _storageService.getOrCreateSubdirectory('game_images');
      final iconPath = '${gameImagesDir.path}/game_${gameId}_icon.png';
      
      if (await File(iconPath).exists()) {
        return Image.file(
          File(iconPath),
          width: width,
          height: height,
          fit: BoxFit.cover,
        );
      }
      
      // If not found, return a placeholder
      return Container(
        width: width,
        height: height,
        color: Colors.grey.shade800,
        child: Center(
          child: Icon(
            Icons.videogame_asset,
            color: Colors.grey.shade400,
            size: width / 2,
          ),
        ),
      );
    } catch (e) {
      // Return a placeholder on error
      return Container(
        width: width,
        height: height,
        color: Colors.grey.shade800,
        child: Center(
          child: Icon(
            Icons.videogame_asset,
            color: Colors.grey.shade400,
            size: width / 2,
          ),
        ),
      );
    }
  }
  
  // Get a widget for a cached game box art
  Future<Widget> getGameBoxArtImage(int gameId, {double width = 100, double height = 150}) async {
    try {
      final gameImagesDir = await _storageService.getOrCreateSubdirectory('game_images');
      final boxArtPath = '${gameImagesDir.path}/game_${gameId}_boxart.png';
      
      if (await File(boxArtPath).exists()) {
        return Image.file(
          File(boxArtPath),
          width: width,
          height: height,
          fit: BoxFit.cover,
        );
      }
      
      // If not found, return a placeholder
      return Container(
        width: width,
        height: height,
        color: Colors.grey.shade800,
        child: Center(
          child: Icon(
            Icons.image,
            color: Colors.grey.shade400,
            size: width / 2,
          ),
        ),
      );
    } catch (e) {
      // Return a placeholder on error
      return Container(
        width: width,
        height: height,
        color: Colors.grey.shade800,
        child: Center(
          child: Icon(
            Icons.image,
            color: Colors.grey.shade400,
            size: width / 2,
          ),
        ),
      );
    }
  }
  
  // Get a widget for a cached achievement badge
  Future<Widget> getAchievementBadgeImage(String badgeName, {double size = 64}) async {
    try {
      final badgesDir = await _storageService.getOrCreateSubdirectory('badge_images');
      final badgePath = '${badgesDir.path}/$badgeName';
      
      if (await File(badgePath).exists()) {
        return Image.file(
          File(badgePath),
          width: size,
          height: size,
          fit: BoxFit.cover,
        );
      } else {
        // If badge doesn't exist locally, download it
        final badgeUrl = 'https://retroachievements.org/Badge/$badgeName';
        final savedPath = await _storageService.saveImageFromUrl(
          badgeUrl,
          'badge_images',
          badgeName,
        );
        
        if (savedPath != null && await File(savedPath).exists()) {
          return Image.file(
            File(savedPath),
            width: size,
            height: size,
            fit: BoxFit.cover,
          );
        }
      }
      
      // If still not found, return a placeholder
      return Container(
        width: size,
        height: size,
        color: Colors.grey.shade800,
        child: Center(
          child: Icon(
            Icons.emoji_events,
            color: Colors.grey.shade400,
            size: size / 2,
          ),
        ),
      );
    } catch (e) {
      // Return a placeholder on error
      return Container(
        width: size,
        height: size,
        color: Colors.grey.shade800,
        child: Center(
          child: Icon(
            Icons.emoji_events,
            color: Colors.grey.shade400,
            size: size / 2,
          ),
        ),
      );
    }
  }
}