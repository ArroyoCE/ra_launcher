import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

/// Class that implements hashing for multiple console systems
/// Based on the RetroAchievements C code implementation
class CombinedConsoleHashIntegration {
  // Constants
  static const int maxBufferSize = 64 * 1024 * 1024; // 64MB, similar to RC_HASH_MAX_BUFFER_SIZE

  /// Processa arquivos em paralelo usando isolates
  Future<Map<String, String>> hashFilesForConsole(List<String> folders, int consoleId) async {
    final Map<String, String> hashes = {};
    List<String> validExtensions = _getValidExtensions(consoleId);

    if (validExtensions.isEmpty) return hashes;

    final List<File> filesToProcess = [];
    for (final folderPath in folders) {
      final directory = Directory(folderPath);
      if (await directory.exists()) {
        await for (final entity in directory.list(recursive: true)) {
          if (entity is File && validExtensions.contains(path.extension(entity.path).toLowerCase())) {
            filesToProcess.add(entity);
          }
        }
      }
    }

    // Dividir arquivos em lotes para processamento paralelo
    final int batchSize = 4; // Número de arquivos por lote
    final List<List<File>> batches = [];
    for (int i = 0; i < filesToProcess.length; i += batchSize) {
      batches.add(filesToProcess.sublist(i, i + batchSize > filesToProcess.length ? filesToProcess.length : i + batchSize));
    }

    // Processar lotes em paralelo
    final List<Future<Map<String, String>>> batchResults = batches.map((batch) {
      return _processBatch(batch, consoleId);
    }).toList();

    // Combinar resultados
    for (final result in await Future.wait(batchResults)) {
      hashes.addAll(result);
    }

    return hashes;
  }

  /// Processa um lote de arquivos em um isolate
  Future<Map<String, String>> _processBatch(List<File> files, int consoleId) async {
    final ReceivePort receivePort = ReceivePort();
    await Isolate.spawn(_hashBatchIsolate, [files, consoleId, receivePort.sendPort]);
    return await receivePort.first as Map<String, String>;
  }

  /// Função executada no isolate para processar um lote
  void _hashBatchIsolate(List<dynamic> args) async {
  final List<File> files = args[0] as List<File>;
  final int consoleId = args[1] as int;
  final SendPort sendPort = args[2] as SendPort;

  final Map<String, String> batchHashes = {};
  final CombinedConsoleHashIntegration hasher = CombinedConsoleHashIntegration();

  for (final file in files) {
    try {
      final bytes = await file.readAsBytes();
      String? fileHash;
      
      switch (consoleId) {
        case 7: // Now handles both NES and FDS files
          fileHash = await hasher.hashNES(bytes);
          break;
        case 3:
          fileHash = await hasher.hashSNES(bytes);
          break;
        case 51:
          fileHash = await hasher.hash7800(bytes);
          break;
        case 13:
          fileHash = await hasher.hashLynx(bytes);
          break;
        case 8:
          fileHash = await hasher.hashPCE(bytes);
          break;
        // Removed case 81 (FDS) as it's now integrated with NES
      }
      if (fileHash != null) {
        batchHashes[file.path] = fileHash;
      }
    } catch (_) {
      // Ignorar erros de hashing
    }
  }

  sendPort.send(batchHashes);
}

/// Obtém extensões válidas para o console
List<String> _getValidExtensions(int consoleId) {
  switch (consoleId) {
    case 7:
      return ['.nes', '.fds']; // Added FDS extension to NES console
    case 3:
      return ['.sfc', '.smc', '.swc', '.fig'];
    case 51:
      return ['.a78'];
    case 13:
      return ['.lnx'];
    case 8:
      return ['.pce', '.sgx'];
    // Removed case 81 (FDS)
    default:
      return [];
  }
}

  /// Hashes an Atari 7800 ROM
  /// Based on rc_hash_7800() in the C code
  Future<String?> hash7800(Uint8List bytes) async {
    // Limit buffer size
    final bufferSize = bytes.length > maxBufferSize ? maxBufferSize : bytes.length;

    // Check header - A78 games begin with ATARI7800
    if (bufferSize < 128) return await computeRawMD5(bytes);

    final header = String.fromCharCodes(bytes.sublist(1, 17));
    if (header.startsWith('ATARI7800')) {
      // A78 header is 128 bytes
      final dataBytes = bytes.sublist(128, bufferSize);
      return await computeRawMD5(dataBytes);
    }

    // If no header found, hash the whole file
    return await computeRawMD5(bytes.sublist(0, bufferSize));
  }

  /// Hashes an Atari Lynx ROM
  /// Based on rc_hash_lynx() in the C code
  Future<String?> hashLynx(Uint8List bytes) async {
    // Limit buffer size
    final bufferSize = bytes.length > maxBufferSize ? maxBufferSize : bytes.length;

    // Lynx ROMs have a 64-byte header
    if (bufferSize <= 64) return await computeRawMD5(bytes);

    // Check for "LYNX" signature in header
    if (bytes[0] == 0x4C && bytes[1] == 0x59 && bytes[2] == 0x4E && bytes[3] == 0x58) {
      // Skip the 64-byte header
      final dataBytes = bytes.sublist(64, bufferSize);
      return await computeRawMD5(dataBytes);
    }

    // Check for alternate signature "BS93" (homebrew ROMs)
    if (bytes[0] == 0x42 && bytes[1] == 0x53 && bytes[2] == 0x39 && bytes[3] == 0x33) {
      // Skip the 64-byte header
      final dataBytes = bytes.sublist(64, bufferSize);
      return await computeRawMD5(dataBytes);
    }

    // If no header detected, hash the whole file
    return await computeRawMD5(bytes.sublist(0, bufferSize));
  }

  /// Hashes a PC Engine ROM
  /// Based on rc_hash_pce() in the C code
  Future<String?> hashPCE(Uint8List bytes) async {
    // Limit buffer size
    final bufferSize = bytes.length > maxBufferSize ? maxBufferSize : bytes.length;

    // Special case for sgx files - just hash the whole file
    if (bytes.length >= 512 * 1024) {
      final dataBytes = bytes.sublist(0, bufferSize);
      return await computeRawMD5(dataBytes);
    }

    // Some PC Engine games have a 512-byte header
    // If file is an odd multiple of 8KB, assume it has a header
    if (bytes.length % 8192 == 512) {
      final dataBytes = bytes.sublist(512, bufferSize);
      return await computeRawMD5(dataBytes);
    }

    // If no header detected, hash the entire file
    return await computeRawMD5(bytes.sublist(0, bufferSize));
  }

  /// Hashes a Famicom Disk System ROM
  /// Based on rc_hash_fds() in the C code
  Future<String?> hashFDS(Uint8List bytes) async {
    // Limit buffer size
    final bufferSize = bytes.length > maxBufferSize ? maxBufferSize : bytes.length;

    // Check FDS header for "FDS\x1A"
    if (bufferSize >= 16 &&
        bytes[0] == 0x46 && bytes[1] == 0x44 && bytes[2] == 0x53 && bytes[3] == 0x1A) {
      // Skip 16-byte header
      final dataBytes = bytes.sublist(16, bufferSize);
      return await computeRawMD5(dataBytes);
    }

    // No FDS header, hash the entire file
    return await computeRawMD5(bytes.sublist(0, bufferSize));
  }

  /// Hashes an NES ROM
  /// Based on rc_hash_nes() in the C code
  Future<String?> hashNES(Uint8List bytes, {bool isFDS = false}) async {
  // Limit buffer size
  final bufferSize = bytes.length > maxBufferSize ? maxBufferSize : bytes.length;

  // First check if this is an FDS file
  if (isFDS || (bufferSize >= 16 && 
      bytes[0] == 0x46 && bytes[1] == 0x44 && bytes[2] == 0x53 && bytes[3] == 0x1A)) {
    // Check FDS header for "FDS\x1A"
    if (bufferSize >= 16 &&
        bytes[0] == 0x46 && bytes[1] == 0x44 && bytes[2] == 0x53 && bytes[3] == 0x1A) {
      // Skip 16-byte header
      final dataBytes = bytes.sublist(16, bufferSize);
      return await computeRawMD5(dataBytes);
    }
    
    // No FDS header, hash the entire file
    return await computeRawMD5(bytes.sublist(0, bufferSize));
  }

  // Check if this is an iNES ROM (header starts with NES\x1A)
  if (bufferSize >= 16 &&
      bytes[0] == 0x4E && bytes[1] == 0x45 && bytes[2] == 0x53 && bytes[3] == 0x1A) {
    // Get sizes from header - bytes 4-5 indicate PRG/CHR sizes
    int prgSize = bytes[4] * 16384; // PRG size in 16K units
    int chrSize = bytes[5] * 8192; // CHR size in 8K units

    // Check for NES 2.0 format
    bool isNes20 = ((bytes[7] & 0x0C) == 0x08);
    if (isNes20) {
      // For NES 2.0, sizes can be larger
      int prgSizeMSB = (bytes[9] & 0x0F);
      prgSize = ((prgSizeMSB << 8) | bytes[4]) * 16384;

      int chrSizeMSB = (bytes[9] >> 4);
      chrSize = ((chrSizeMSB << 8) | bytes[5]) * 8192;
    }

    // Calculate header size (iNES header is minimum 16 bytes)
    int headerSize = 16;

    // Check for trainer - adds 512 bytes after header
    if ((bytes[6] & 0x04) != 0) {
      headerSize += 512;
    }

    // Combine PRG and CHR data for hashing
    int dataSize = prgSize + chrSize;
    if (dataSize == 0 || headerSize + dataSize > bufferSize) {
      // If sizes are invalid, hash the whole file
      return await computeRawMD5(bytes.sublist(0, bufferSize));
    }

    // Extract PRG+CHR data for hashing
    final dataBytes = bytes.sublist(headerSize, headerSize + dataSize);
    return await computeRawMD5(dataBytes);
  }

  // Not an iNES ROM or invalid header, hash the whole file
  return await computeRawMD5(bytes.sublist(0, bufferSize));
}

  /// Hashes a SNES ROM
  /// Based on rc_hash_snes() in the C code
  Future<String?> hashSNES(Uint8List bytes) async {
    // Limit buffer size
    final bufferSize = bytes.length > maxBufferSize ? maxBufferSize : bytes.length;

    // SNES ROMs can have headers and be in different formats
    // Need to check for different ROM layouts
    if (bufferSize < 0x8000) {
      // Too small to be a valid SNES ROM
      return await computeRawMD5(bytes.sublist(0, bufferSize));
    }

    int offset = 0;
    bool hasHeader = false;

    // Check for 512-byte header (typically .smc files)
    if (bufferSize % 1024 == 512) {
      offset = 512;
      hasHeader = true;
    }

    // Check for LoROM vs HiROM format
    bool isHiROM = false;

    // Check HiROM marker at 0xFFD5 (or + 512 if has header)
    if (offset + 0xFFD5 < bufferSize) {
      final romMode = bytes[offset + 0xFFD5] & 0x01;
      if (romMode == 1) {
        isHiROM = true;
      }
    }

    // Verify the format with checksum check
    if (offset + 0xFFDC + 4 < bufferSize) {
      int checksum = bytes[offset + 0xFFDC] | (bytes[offset + 0xFFDD] << 8);
      int checksumComplement = bytes[offset + 0xFFDE] | (bytes[offset + 0xFFDF] << 8);

      // Valid checksum should be complement of checksum complement
      if ((checksum ^ checksumComplement) != 0xFFFF) {
        // Try alternate location for LoROM
        if (!isHiROM && offset + 0x7FDC + 4 < bufferSize) {
          checksum = bytes[offset + 0x7FDC] | (bytes[offset + 0x7FDD] << 8);
          checksumComplement = bytes[offset + 0x7FDE] | (bytes[offset + 0x7FDF] << 8);

          // If valid, it's LoROM
          if ((checksum ^ checksumComplement) == 0xFFFF) {
            isHiROM = false;
          }
        }
      }
    }

    // Get the file data for hashing
    final dataBytes = hasHeader
        ? bytes.sublist(offset, bufferSize)
        : bytes.sublist(0, bufferSize);

    return await computeRawMD5(dataBytes);
  }

  /// Computes an MD5 hash of raw bytes
  Future<String> computeRawMD5(Uint8List bytes) async {
    // Use compute for better performance on larger files
    return await compute(_md5Hash, bytes);
  }

  // Static method for compute isolation
  static String _md5Hash(Uint8List bytes) {
    final digest = md5.convert(bytes);
    return digest.toString();
  }
}