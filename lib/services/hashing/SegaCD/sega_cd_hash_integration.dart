import 'package:flutter/foundation.dart';
import 'package:retroachievements_organizer/services/hashing/SegaCD/sega_cd_hashing.dart';

/// Sega CD hash integration
class SegaCDHashIntegration {
  final _segaCDSaturnHashIntegration = SegaCDSaturnHashIntegration();
  
  /// Hash Sega CD files in the given folders
  Future<Map<String, String>> hashSegaCDFilesInFolders(
    List<String> folders,
    {void Function(int current, int total)? progressCallback}
  ) async {
    debugPrint('Starting Sega CD hashing in ${folders.length} folders');
    
    return await _segaCDSaturnHashIntegration.hashFilesInFolders(
      folders, 
      false, // isSaturn = false for Sega CD
      progressCallback: progressCallback
    );
  }
}