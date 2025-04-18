
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'ps2_hash.dart';

class Ps2HashIntegration {
  final Ps2HashCalculator _hashCalculator = Ps2HashCalculator();
  
  /// Hash PS2 files in the provided folders
  Future<Map<String, String>> hashPs2FilesInFolders(
    List<String> folders, {
    Function(int current, int total)? progressCallback
  }) async {
    debugPrint('Starting PlayStation 2 hashing for ${folders.length} folders');
    
    try {
      return await _hashCalculator.hashPs2FilesInFolders(folders);
    } catch (e, stackTrace) {
      debugPrint('Error in PS2 hash integration: $e');
      debugPrint('Stack trace: $stackTrace');
      return {};
    }
  }
}