// lib/services/hashing/DC/dreamcast_hash_utils.dart
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'dart:math';

class DreamcastHashUtils {
  static const int IP_BIN_SIZE = 256;
  static const int BOOT_FILENAME_OFFSET = 96;
  static const int BOOT_FILENAME_MAX_LEN = 32;

  // --- Place the new method here ---
  /// Determines the likely data offset within a raw 2352-byte sector.
  static int detectDataOffset(
      Uint8List rawSectorData,
      int logicalSectorNumber,
      { int defaultOffset = 16 }
  ) {
    // Check only relevant sectors and if data is plausibly large enough (e.g., > 24 + marker size)
    if (rawSectorData.length < 24 + 16) {
      return defaultOffset;
    }

    // Check for SEGA marker (usually in logical sector 0)
    if (logicalSectorNumber == 0) {
      try {
        if (validateSegaSegakatana(rawSectorData)) return 0;
        if (validateSegaSegakatana(rawSectorData.sublist(16))) return 16;
        if (validateSegaSegakatana(rawSectorData.sublist(24))) return 24;
      } catch (_) { /* Sublist errors possible if length is too small */ }
    }
    // Check for CD001 marker (usually in logical sector 16 - PVD)
    else if (logicalSectorNumber == 16) {
      try {
        // validateCd001 checks identifier starting at offset+1
        if (validateCd001(rawSectorData, 0)) return 0;
        if (validateCd001(rawSectorData, 16)) return 16;
        if (validateCd001(rawSectorData, 24)) return 24;
      } catch (_) { /* Bounds errors possible */ }
    }
    return defaultOffset;
  }
  // --- End of new method ---


  // --- Existing methods below (validateSegaSegakatana, extractBootFileNameBytes, etc.) ---
  static bool validateSegaSegakatana(Uint8List data) {
    if (data.length < 16) return false;
    const marker = 'SEGA SEGAKATANA ';
    final markerBytes = ascii.encode(marker);
    for (int i = 0; i < 16; i++) {
      if (data[i] != markerBytes[i]) return false;
    }
    return true;
  }

  static bool validateCd001(Uint8List data, int offset) {
    if (offset + 5 >= data.length) return false; // Changed check to >=
     // Check bytes 'C', 'D', '0', '0', '1' starting at offset + 1
    if (data[offset + 1] == 0x43 &&
        data[offset + 2] == 0x44 &&
        data[offset + 3] == 0x30 &&
        data[offset + 4] == 0x30 &&
        data[offset + 5] == 0x31) {
        return true;
    }
    return false;
  }

  static bool isWhitespace(int byte) {
    return byte == 0x20 || byte == 0x09 || byte == 0x0D || byte == 0x0A;
  }

  static Uint8List? extractBootFileNameBytes(Uint8List ipBinData) {
    if (ipBinData.length < BOOT_FILENAME_OFFSET + 1) {
        return null;
    }
    int endOffset = BOOT_FILENAME_OFFSET;
    final int maxOffset = min(ipBinData.length, BOOT_FILENAME_OFFSET + BOOT_FILENAME_MAX_LEN);
    while (endOffset < maxOffset && !isWhitespace(ipBinData[endOffset]) && ipBinData[endOffset] != 0) {
      endOffset++;
    }
    if (endOffset == BOOT_FILENAME_OFFSET) {
      return null;
    }
    try {
        return ipBinData.sublist(BOOT_FILENAME_OFFSET, endOffset);
    } catch (e) {
        return null;
    }
  }

  static String? calculateDreamcastHash(
      Uint8List ipBinData,
      Uint8List? bootFileNameBytes,
      Uint8List bootFileContent) {
    if (bootFileNameBytes == null || bootFileNameBytes.isEmpty) {
        return null;
    }
    final List<int> combinedData = [];
    if (ipBinData.length >= IP_BIN_SIZE) {
      combinedData.addAll(ipBinData.sublist(0, IP_BIN_SIZE));
    } else {
      combinedData.addAll(ipBinData);
      combinedData.addAll(List.filled(IP_BIN_SIZE - ipBinData.length, 0));
    }
    combinedData.addAll(bootFileNameBytes);
    combinedData.addAll(bootFileContent);
    final Uint8List dataToHash = Uint8List.fromList(combinedData);
    final digest = md5.convert(dataToHash);
    final hash = digest.toString();
    // Fewer debug prints now
    // debugPrint('Combined data size for hashing: ${dataToHash.length} bytes');
    debugPrint('Generated hash: $hash');
    return hash;
  }

  static int getInt32(Uint8List data, int offset) {
    if (offset + 3 >= data.length) return 0;
    return (data[offset]) |
           (data[offset + 1] << 8) |
           (data[offset + 2] << 16) |
           (data[offset + 3] << 24);
  }
} // End of class

class FileInfo { // Keep FileInfo class as is
  final int sector;
  final int size;
  FileInfo(this.sector, this.size);
}