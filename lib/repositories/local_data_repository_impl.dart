// lib/repositories/local_data_repository_impl.dart
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:retroachievements_organizer/models/consoles/all_console_model.dart';
import 'package:retroachievements_organizer/models/local/hash_model.dart';
import 'package:retroachievements_organizer/repositories/local_data_repository.dart';
import 'package:retroachievements_organizer/services/hashing/3DO/hash_3do_main.dart';
import 'package:retroachievements_organizer/services/hashing/psx/psx_hash_integration.dart';
import 'package:retroachievements_organizer/services/storage_service.dart';

class LocalDataRepositoryImpl implements LocalDataRepository {
  final StorageService _storageService;
  final PsxHashIntegration _psxHashIntegration = PsxHashIntegration();
  final ThreeDOHashIntegration _threeDOHashIntegration = ThreeDOHashIntegration();
  
  LocalDataRepositoryImpl(this._storageService);
  
@override
Future<void> saveConsoleTotals(int consoleId, int totalGames, int totalHashes) async {
  try {
    final totals = {
      'totalGames': totalGames,
      'totalHashes': totalHashes,
      'lastUpdated': DateTime.now().toIso8601String(),
    };
    
    await _storageService.saveJsonData(totals, 'console_totals', 'console_$consoleId');
    debugPrint('Console totals saved for console $consoleId: $totalGames games, $totalHashes hashes');
  } catch (e) {
    debugPrint('Error saving console totals: $e');
  }
}

@override
Future<Map<String, dynamic>?> getConsoleTotals(int consoleId) async {
  try {
    return await _storageService.readJsonData('console_totals', 'console_$consoleId');
  } catch (e) {
    debugPrint('Error reading console totals: $e');
    return null;
  }
}

  @override
  Future<List<Console>> getLocalConsolesFolders() async {
    try {
      // First try to load from cache
      final cachedData = await _storageService.readJsonData('local_data', 'consolesfolders');
      
      if (cachedData != null && cachedData['consolesfolder'] != null) {
        final folders = (cachedData['consolesfolder'] as List)
            .map((consoleJson) => Console.fromJson(consoleJson))
            .toList();
        return folders;
      }
      
      // If not in cache, load from assets
      final jsonString = await rootBundle.loadString('assets/data/consolesfolders.json');
      final jsonData = json.decode(jsonString) as Map<String, dynamic>;
      
      if (jsonData['consolesfolders'] != null) {
        final folders = (jsonData['consolesfolders'] as List)
            .map((consoleJson) => Console.fromJson(consoleJson))
            .toList();
        
        // Cache the data for future use
        await _storageService.saveJsonData({'consoles': jsonData['consoles']}, 'local_data', 'consoles');
        
        return folders;
      }
      
      return [];
    } catch (e) {
      // Return empty list on error
      return [];
    }
  }
  

  @override
  Future<Map<int, List<String>>> getConsoleFolders() async {
    try {
      // Try to load from cache
      final cachedData = await _storageService.readJsonData('local_data', 'console_folders');
      
      if (cachedData != null && cachedData['folders'] != null) {
        final Map<String, dynamic> foldersMap = cachedData['folders'];
        Map<int, List<String>> result = {};
        
        foldersMap.forEach((key, value) {
          final consoleId = int.tryParse(key);
          if (consoleId != null && value is List) {
            result[consoleId] = List<String>.from(value);
          }
        });
        
        return result;
      }
      
      // If not found, return empty map
      return {};
    } catch (e) {
      debugPrint('Error loading console folders: $e');
      return {};
    }
  }

@override
Future<void> saveConsoleFolders(int consoleId, List<String> folders) async {
  try {
    // Get existing folders
    final existingFolders = await getConsoleFolders();
    
    // Get the current folders for this console
    final currentFolders = existingFolders[consoleId] ?? [];
    
    // If folders have been removed, clean up associated hashes
    if (currentFolders.length > folders.length) {
      // Find removed folders
      final removedFolders = currentFolders.where((folder) => !folders.contains(folder)).toList();
      if (removedFolders.isNotEmpty) {
        await cleanHashesForRemovedFolders(consoleId, removedFolders);
      }
    }
    
    // Update the folders for this console
    existingFolders[consoleId] = folders;
    
    // Convert to format for saving
    Map<String, dynamic> foldersMap = {};
    existingFolders.forEach((key, value) {
      foldersMap[key.toString()] = value;
    });
    
    // Save to storage
    await _storageService.saveJsonData(
      {'folders': foldersMap}, 
      'local_data', 
      'console_folders'
    );
  } catch (e) {
    debugPrint('Error saving console folders: $e');
  }
}

// Add this new method to clean up hashes when folders are removed
Future<void> cleanHashesForRemovedFolders(int consoleId, List<String> removedFolders) async {
  try {
    // Get current hashes
    final currentHashes = await getLocalHashes(consoleId);
    if (currentHashes.isEmpty) return;
    
    // Create a new map without hashes from removed folders
    final updatedHashes = Map<String, String>.from(currentHashes);
    
    // Remove hashes associated with removed folders
    updatedHashes.removeWhere((filePath, hash) {
      // Check if the file path starts with any of the removed folders
      return removedFolders.any((folder) => filePath.startsWith(folder));
    });
    
    // Save the updated hashes
    await saveLocalHashes(consoleId, updatedHashes);
    
    // Calculate new stats
    int matchedHashesCount = updatedHashes.length;
    
    // Get the games list to calculate matchedGames
    final gamesList = await getGamesList(consoleId);
    int matchedGamesCount = 0;
    
    if (gamesList != null && gamesList.isNotEmpty) {
      // Convert local hashes to a set for faster lookups
      final localHashSet = updatedHashes.values.toSet();
      
      // Check each game for matches
      for (final game in gamesList) {
        final gameHashes = game['Hashes'] as List<dynamic>?;
        if (gameHashes != null && gameHashes.isNotEmpty) {
          // If any hash matches, count this game
          if (gameHashes.any((hash) => localHashSet.contains(hash.toString().toLowerCase()))) {
            matchedGamesCount++;
          }
        }
      }
    }
    
    // Update hash stats
    await saveHashStats(consoleId, matchedGamesCount, matchedHashesCount);
    
    debugPrint('Cleaned up ${currentHashes.length - updatedHashes.length} hashes from removed folders');
    debugPrint('Updated stats: $matchedGamesCount games, $matchedHashesCount hashes');
  } catch (e) {
    debugPrint('Error cleaning hashes for removed folders: $e');
  }
}

Future<List<dynamic>?> getGamesList(int consoleId) async {
  try {
    final cachedData = await _storageService.readJsonData('game_list', consoleId.toString());
    return cachedData != null ? cachedData['games'] as List<dynamic> : null;
  } catch (e) {
    debugPrint('Error reading games list: $e');
    return null;
  }
}

  @override
Future<void> saveHashStats(int consoleId, int matchedGames, int matchedHashes) async {
  try {
    // Create a data object with the stats
    final stats = {
      'consoleId': consoleId,
      'matchedGames': matchedGames,
      'matchedHashes': matchedHashes,
      'lastUpdated': DateTime.now().toIso8601String(),
    };
    
    // Save to storage
    await _storageService.saveJsonData(stats, 'hash_stats', 'console_$consoleId');
    debugPrint('Hash stats saved for console $consoleId: $matchedGames games, $matchedHashes hashes');
  } catch (e) {
    debugPrint('Error saving hash stats: $e');
  }
}

@override
Future<Map<String, dynamic>?> getHashStats(int consoleId) async {
  try {
    return await _storageService.readJsonData('hash_stats', 'console_$consoleId');
  } catch (e) {
    debugPrint('Error reading hash stats: $e');
    return null;
  }
}


  @override
  HashMethod getHashMethodForConsole(int consoleId) {
    return ConsoleHashMethods.getHashMethodForConsole(consoleId);
  }
  
  @override
  bool isConsoleSupported(int consoleId) {
    return ConsoleHashMethods.isConsoleSupported(consoleId);
  }
  
  @override
  List<int> getSupportedConsoleIds() {
    return ConsoleHashMethods.supportedConsoleIds;
  }

  @override
  List<String> getFileExtensionsForConsole(int consoleId) {
    return ConsoleHashMethods.getFileExtensionsForConsole(consoleId);
  }

  @override
Future<Map<String, String>> hashFilesInFolders(int consoleId, List<String> folders) async {
  final Map<String, String> hashes = {};
  final validExtensions = getFileExtensionsForConsole(consoleId);
  final hashMethod = getHashMethodForConsole(consoleId);
  
  // Check if folders list is empty
  if (folders.isEmpty) {
    return hashes;
  }

  try {
    // Special case for PlayStation - we handle this differently
    if (hashMethod == HashMethod.psx) {
      debugPrint('Starting PlayStation hashing, this might take some time...');
      
      // This will now handle UI updates internally
      final psxHashes = await _psxHashIntegration.hashPsxFilesInFolders(folders);
      
      // Save the PlayStation hashes
      await saveLocalHashes(consoleId, psxHashes);
      return psxHashes;
    }

if (hashMethod == HashMethod.threedo) {
  debugPrint('Starting 3DO hashing, this might take some time...');
  
  // This will handle UI updates internally
  final threedoHashes = await _threeDOHashIntegration.hash3DOFilesInFolders(folders);
  
  // Save the 3DO hashes
  await saveLocalHashes(consoleId, threedoHashes);
  return threedoHashes;
}
    
    // For other consoles, process files with proper UI updates
    final List<File> filesToProcess = [];
    
    // First collect all files to process
    for (final folderPath in folders) {
      final directory = Directory(folderPath);
      
      if (await directory.exists()) {
        await for (final entity in directory.list(recursive: true)) {
          if (entity is File) {
            final extension = path.extension(entity.path).toLowerCase();
            
            // Check if file has a valid extension for this console
            if (validExtensions.contains(extension)) {
              filesToProcess.add(entity);
            }
          }
        }
      }
    }
    
    // Allow UI to update before starting hash process
    await Future.microtask(() => null);
    
    // Process files with yields to UI thread
    for (int i = 0; i < filesToProcess.length; i++) {
      final file = filesToProcess[i];
      
      try {
        // Read file as bytes
        final bytes = await file.readAsBytes();
        
        // Hash the file based on console's hash method
        String fileHash;
          
        switch (hashMethod) {
          case HashMethod.md5:
            fileHash = md5.convert(bytes).toString();
            break;
          case HashMethod.sha1:
            fileHash = sha1.convert(bytes).toString();
            break;
          default:
            fileHash = md5.convert(bytes).toString();
        }
        
        // Store hash with file path
        hashes[file.path] = fileHash;
      } catch (e) {
        debugPrint('Error hashing file ${file.path}: $e');
      }
      
      // Yield to UI thread every few files
      if (i % 5 == 0) {
        await Future.microtask(() => null);
      }
    }
    
    // Save the hashes
    await saveLocalHashes(consoleId, hashes);
    
    return hashes;
  } catch (e) {
    debugPrint('Error hashing files: $e');
    return hashes;
  }
}


  @override
  Future<void> saveLocalHashes(int consoleId, Map<String, String> hashes) async {
    try {
      await _storageService.saveJsonData(
        {'hashes': hashes}, 
        'local_hashes', 
        'console_$consoleId'
      );
    } catch (e) {
      debugPrint('Error saving local hashes: $e');
    }
  }

  @override
  Future<Map<String, String>> getLocalHashes(int consoleId) async {
    try {
      final cachedData = await _storageService.readJsonData('local_hashes', 'console_$consoleId');
      
      if (cachedData != null && cachedData['hashes'] != null) {
        final Map<String, dynamic> hashesMap = cachedData['hashes'];
        return Map<String, String>.from(hashesMap);
      }
      
      return {};
    } catch (e) {
      debugPrint('Error loading local hashes: $e');
      return {};
    }
  }
}