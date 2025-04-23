// lib/services/hashing/utils/file_utils.dart
import 'dart:io';
import 'package:path/path.dart' as path;

class FileUtils {
  /// Get all files in a folder with specified extensions
  static Future<List<FileSystemEntity>> getFilesInFolder(
    String folderPath, {
    List<String> extensions = const [],
  }) async {
    final directory = Directory(folderPath);
    if (!await directory.exists()) {
      return [];
    }
    
    final List<FileSystemEntity> result = [];
    
    await for (final entity in directory.list(recursive: false, followLinks: false)) {
      if (entity is File) {
        final fileExtension = path.extension(entity.path).toLowerCase();
        
        if (extensions.isEmpty || extensions.any((ext) => 
            fileExtension.toLowerCase() == ext.toLowerCase() || 
            fileExtension.toLowerCase() == '.$ext'.toLowerCase())) {
          result.add(entity);
        }
      }
    }
    
    return result;
  }
  
  /// Get the file extension without the dot
  static String getFileExtension(String filePath) {
    final extension = path.extension(filePath);
    return extension.isEmpty ? '' : extension.substring(1).toLowerCase();
  }
  
  /// Get the first item from a playlist (M3U file)
  static Future<String?> getFirstItemFromPlaylist(String m3uPath) async {
    try {
      final file = File(m3uPath);
      if (!await file.exists()) {
        return null;
      }
      
      final lines = await file.readAsLines();
      
      for (var line in lines) {
        // Skip empty lines and comments
        line = line.trim();
        if (line.isEmpty || line.startsWith('#')) {
          continue;
        }
        
        // Check if the path is relative or absolute
        if (path.isAbsolute(line)) {
          return line;
        } else {
          // Resolve relative path
          return path.join(path.dirname(m3uPath), line);
        }
      }
      
      return null;
    } catch (e) {
      return null;
    }
  }
}