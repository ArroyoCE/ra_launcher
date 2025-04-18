import 'package:flutter/foundation.dart';
import 'package:retroachievements_organizer/services/hashing/PCECD/pce_pcfx_hashing.dart';

/// PC Engine CD hash integration
class PCECDHashIntegration {
  final _pcePcfxHashIntegration = PCEPCFXHashIntegration();
  
  /// Hash PC Engine CD files in the given folders
  Future<Map<String, String>> hashPCECDFilesInFolders(
    List<String> folders,
    {void Function(int current, int total)? progressCallback}
  ) async {
    debugPrint('Starting PC Engine CD hashing in ${folders.length} folders');
    
    return await _pcePcfxHashIntegration.hashFilesInFolders(
      folders, 
      false, // isPCFX = false for PC Engine CD
      progressCallback: progressCallback
    );
  }
}