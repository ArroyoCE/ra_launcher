// lib/services/hashing/dreamcast/dreamcast_hash_utils.dart
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

class DreamcastHashUtils {
  static const int IP_BIN_SIZE = 256;
  
  static bool validateSegaSegakatana(Uint8List data) {
    if (data.length < 16) return false;
    
    const marker = 'SEGA SEGAKATANA ';
    final markerBytes = utf8.encode(marker);
    
    for (int i = 0; i < 16; i++) {
      if (data[i] != markerBytes[i]) return false;
    }
    
    return true;
  }
  
  static bool validateCd001(Uint8List data, int offset) {
    if (data.length < offset + 5) return false;
    
    final cd001 = [0x43, 0x44, 0x30, 0x30, 0x31]; // 'CD001'
    
    for (int i = 0; i < 5; i++) {
      if (data[offset + i] != cd001[i]) return false;
    }
    
    return true;
  }
  
  static String? extractBootFileName(Uint8List ipBinData) {
    try {
      // Boot file name starts at offset 96
      int i = 96;
      while (i < ipBinData.length && i < 128 && !isWhitespace(ipBinData[i]) && ipBinData[i] != 0) {
        i++;
      }
      
      if (i == 96 || i >= ipBinData.length) {
        // No boot file specified
        return null;
      }
      
      return utf8.decode(ipBinData.sublist(96, i));
    } catch (e) {
      return null;
    }
  }
  
  static bool isWhitespace(int byte) {
    return byte == 0x20 || byte == 0x09 || byte == 0x0D || byte == 0x0A;
  }
  
static String calculateDreamcastHash(Uint8List ipBinData, String bootFileName, Uint8List bootFileContent) {
  debugPrint('IP.BIN first 16 bytes: ${ipBinData.sublist(0, 16).map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');
  debugPrint('Boot file name: "$bootFileName" (${bootFileName.length} chars)');
  debugPrint('Boot content bytes: ${bootFileContent.length}');
  
  // Create combined data exactly like the C implementation
  final combinedData = <int>[];
  
  // 1. Add IP.BIN data (first 256 bytes)
  if (ipBinData.length >= IP_BIN_SIZE) {
    combinedData.addAll(ipBinData.sublist(0, IP_BIN_SIZE));
  } else {
    combinedData.addAll(ipBinData);
    // Pad to IP_BIN_SIZE if needed
    for (int i = ipBinData.length; i < IP_BIN_SIZE; i++) {
      combinedData.add(0);
    }
  }
  
  // 2. Add boot file name bytes
  // Important: Use ASCII encoding like the C code does, not UTF-8
  final bootFileNameBytes = ascii.encode(bootFileName);
  combinedData.addAll(bootFileNameBytes);
  
  // 3. Add boot file content 
  combinedData.addAll(bootFileContent);
  
  // Hash using MD5
  final hash = md5.convert(combinedData);
  return hash.toString();
}




  static int getInt32(Uint8List data, int offset) {
    if (offset + 3 >= data.length) return 0;
    return (data[offset]) | 
           (data[offset + 1] << 8) | 
           (data[offset + 2] << 16) | 
           (data[offset + 3] << 24);
  }
}

class FileInfo {
  final int sector;
  final int size;
  
  FileInfo(this.sector, this.size);
}