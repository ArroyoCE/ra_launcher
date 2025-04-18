import 'package:flutter/foundation.dart';
import 'package:retroachievements_organizer/services/hashing/SegaCD/sega_cd_hashing.dart';

/// Sega Saturn hash integration
class SegaSaturnHashIntegration {
  final _segaCDSaturnHashIntegration = SegaCDSaturnHashIntegration();
  
  /// Hash Sega Saturn files in the given folders
  Future<Map<String, String>> hashSegaSaturnFilesInFolders(
    List<String> folders,
    {void Function(int current, int total)? progressCallback}
  ) async {
    debugPrint('Starting Sega Saturn hashing in ${folders.length} folders');
    
    return await _segaCDSaturnHashIntegration.hashFilesInFolders(
      folders, 
      true, // isSaturn = true for Saturn
      progressCallback: progressCallback
    );
  }
}