// lib/services/hashing/native/rc_hash_dll.dart
import 'dart:collection';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

class RCHashDLL {
  late DynamicLibrary _lib;
  
  // Function typedefs
  late Pointer<NativeFunction<Int32 Function(Pointer<Utf8>, Pointer<Utf8>, Uint32)>> _generateHashFromFile;
  late Pointer<NativeFunction<Uint32 Function(Pointer<Utf8>)>> _getConsoleIdFromName;
  late Pointer<NativeFunction<Void Function()>> _initHashLibrary;
  
  // Function pointers
  late int Function(Pointer<Utf8>, Pointer<Utf8>, int) generateHashFromFile;
  late int Function(Pointer<Utf8>) getConsoleIdFromName;
  late void Function() initHashLibrary;
  
  // Memory management for reuse
  final _hashBufferCache = _HashBufferCache();
  
  // Initialization flag
  static bool _initialized = false;
  static final Finalizer<DynamicLibrary> _finalizer = Finalizer((library) {
    // Clean up code if needed when library is garbage collected
    debugPrint('RCHashDLL library finalized');
  });
  
  // Singleton pattern with lazy initialization
  static final RCHashDLL _instance = RCHashDLL._internal();
  
  factory RCHashDLL() {
    return _instance;
  }
  
  RCHashDLL._internal() {
    if (!_initialized) {
      _initializeLib();
      _initialized = true;
    }
  }
  
  void _initializeLib() {
    try {
      final libraryPath = _getLibraryPath();
      debugPrint('Loading RC Hash DLL from: $libraryPath');
      
      try {
        _lib = DynamicLibrary.open(libraryPath);
        _finalizer.attach(this, _lib); // Register for cleanup
        debugPrint('Successfully loaded RC Hash DLL');
      } catch (e) {
        debugPrint('Failed to load RC Hash DLL: $e');
        throw Exception('Failed to load RC Hash DLL: $e');
      }
      
      // Initialize function pointers with error handling
      try {
        _generateHashFromFile = _lib.lookup<NativeFunction<Int32 Function(Pointer<Utf8>, Pointer<Utf8>, Uint32)>>('generate_hash_from_file');
        _getConsoleIdFromName = _lib.lookup<NativeFunction<Uint32 Function(Pointer<Utf8>)>>('get_console_id_from_name');
        _initHashLibrary = _lib.lookup<NativeFunction<Void Function()>>('init_hash_library');
        
        // Create Dart functions
        generateHashFromFile = _generateHashFromFile.asFunction();
        getConsoleIdFromName = _getConsoleIdFromName.asFunction();
        initHashLibrary = _initHashLibrary.asFunction();
        
        debugPrint('Successfully initialized RC Hash DLL functions');
      } catch (e) {
        debugPrint('Failed to initialize RC Hash DLL functions: $e');
        throw Exception('Failed to initialize RC Hash DLL functions: $e');
      }
      
      // Initialize the library
      try {
        initHashLibrary();
        debugPrint('Successfully initialized RC Hash Library');
      } catch (e) {
        debugPrint('Failed to initialize RC Hash Library: $e');
        throw Exception('Failed to initialize RC Hash Library: $e');
      }
    } catch (e) {
      debugPrint('Error initializing RC Hash DLL: $e');
      rethrow;
    }
  }
  
  String _getLibraryPath() {
    if (Platform.isWindows) {
      return 'rc_hash_dll.dll';
    } else if (Platform.isLinux) {
      return 'librc_hash.so';
    } else if (Platform.isMacOS) {
      return 'librc_hash.dylib';
    } else {
      throw UnsupportedError('Unsupported platform: ${Platform.operatingSystem}');
    }
  }
  
  // More efficient hashFile implementation with buffer reuse
  String hashFile(String filePath, int consoleId) {
    // Get a buffer from the cache or create a new one
    final hashBuffer = _hashBufferCache.getBuffer();
    final filePathPointer = filePath.toNativeUtf8();
    
    try {
      // Cast the hashBuffer to Pointer<Utf8> as required by the function
      final result = generateHashFromFile(filePathPointer, hashBuffer.cast<Utf8>(), consoleId);
      if (result == 0) {
        return ''; // Return empty instead of throwing
      }
      
      final hashString = hashBuffer.cast<Utf8>().toDartString();
      return hashString;
    } catch (e) {
      debugPrint('Error in native hash function: $e');
      return '';
    } finally {
      calloc.free(filePathPointer);
      // Return buffer to pool instead of freeing
      _hashBufferCache.returnBuffer(hashBuffer);
    }
  }
}

// Buffer cache to reduce memory allocations
class _HashBufferCache {
  static const _maxCacheSize = 16; // Adjust based on expected concurrent operations
  final Queue<Pointer<Char>> _availableBuffers = Queue<Pointer<Char>>();
  final Set<Pointer<Char>> _inUseBuffers = {};
  
  // Get a buffer from the cache or create a new one
  Pointer<Char> getBuffer() {
    if (_availableBuffers.isNotEmpty) {
      final buffer = _availableBuffers.removeFirst();
      _inUseBuffers.add(buffer);
      return buffer;
    } else {
      // Create a new buffer - 33 chars for MD5 (32 + null terminator)
      final newBuffer = calloc<Char>(33);
      _inUseBuffers.add(newBuffer);
      return newBuffer;
    }
  }
  
  // Return a buffer to the cache
  void returnBuffer(Pointer<Char> buffer) {
    if (_inUseBuffers.contains(buffer)) {
      _inUseBuffers.remove(buffer);
      
      // If we have too many buffers, free this one
      if (_availableBuffers.length >= _maxCacheSize) {
        calloc.free(buffer);
      } else {
        // Otherwise add it back to available buffers
        _availableBuffers.add(buffer);
      }
    }
  }
  
  // Clean up all buffers - call this when shutting down
  void dispose() {
    for (final buffer in _availableBuffers) {
      calloc.free(buffer);
    }
    _availableBuffers.clear();
    
    for (final buffer in _inUseBuffers) {
      calloc.free(buffer);
    }
    _inUseBuffers.clear();
  }
}