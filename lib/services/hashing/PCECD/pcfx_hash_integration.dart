import 'package:flutter/foundation.dart';
import 'package:retroachievements_organizer/services/hashing/PCECD/pce_pcfx_hashing.dart';

/// PC-FX hash integration
class PCFXHashIntegration {
  final _pcePcfxHashIntegration = PCEPCFXHashIntegration();
  
  /// Hash PC-FX files in the given folders
  Future<Map<String, String>> hashPCFXFilesInFolders(
    List<String> folders,
    {void Function(int current, int total)? progressCallback}
  ) async {
    debugPrint('Starting PC-FX hashing in ${folders.length} folders');
    
    return await _pcePcfxHashIntegration.hashFilesInFolders(
      folders, 
      true, // isPCFX = true for PC-FX
      progressCallback: progressCallback
    );
  }
}