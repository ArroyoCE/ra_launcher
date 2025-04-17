/// Enum representing different hashing methods supported by the app
enum HashMethod {
  md5,
  sha1,
  crc32,
  psx,
  threedo,
  arcade,
  arduboy,
  nes,
  snes,
  atari7800,
  lynx,
  pce,
  fds,
  combined, // New method for combined console hashing
  // Add more hash methods as needed
}

/// Extension to provide string representation of hash methods
extension HashMethodExtension on HashMethod {
  String get name {
    switch (this) {
      case HashMethod.md5:
        return 'MD5';
      case HashMethod.sha1:
        return 'SHA-1';
      case HashMethod.crc32:
        return 'CRC32';
      case HashMethod.psx:
        return 'PSX';
      case HashMethod.threedo:
        return '3DO';
      case HashMethod.arcade:
        return 'ARCADE';
      case HashMethod.arduboy:
        return 'ARDUBOY';
      case HashMethod.nes:
        return 'NES';
      case HashMethod.snes:
        return 'SNES';
      case HashMethod.atari7800:
        return 'Atari 7800';
      case HashMethod.lynx:
        return 'Lynx';
      case HashMethod.pce:
        return 'PC Engine';
      case HashMethod.fds:
        return 'Famicom Disk System';
      case HashMethod.combined:
        return 'Combined';
      default:
        return 'MD5';
    }
  }
}

/// Mapping of console IDs to their appropriate hashing methods
class ConsoleHashMethods {
  // Private constructor to prevent instantiation
  ConsoleHashMethods._();
  
  // Map of console IDs to their respective hash methods
  static final Map<int, HashMethod> consoleHashMap = {
    // These are the consoles that use MD5 hashing
    1: HashMethod.md5,  // Mega Drive
    7: HashMethod.combined,  // NES/Famicom
    4: HashMethod.md5,  // Game Boy
    5: HashMethod.md5,  // Game Boy Advance
    6: HashMethod.md5,  // Game Boy Color
    3: HashMethod.combined,  // SNES/Super Famicom
    51: HashMethod.combined,  // Atari 7800
    13: HashMethod.combined,  // Atari Lynx
    10: HashMethod.md5, // 32X
    11: HashMethod.md5, // Master System
    12: HashMethod.psx, // PlayStation
    8: HashMethod.combined, // PC Engine/TurboGrafx-16
    14: HashMethod.md5, // NeoGeo Pocket
    15: HashMethod.md5, // Game Gear
    17: HashMethod.md5, // Atari Jaguar
    23: HashMethod.md5, // Magnavox
    24: HashMethod.md5, // Pokemon Mini
    25: HashMethod.md5, // Atari 2600
    27: HashMethod.arcade, // arcade
    28: HashMethod.md5, // Virtual Boy
    29: HashMethod.md5, // MSX
    33: HashMethod.md5, // SG-1000
    37: HashMethod.md5, //Amstrad CPC
    38: HashMethod.md5, // Apple II
    43: HashMethod.threedo, // 3DO
    44: HashMethod.md5, // ColecoVision
    45: HashMethod.md5, // Intellivision
    46: HashMethod.md5, // Vectrex
    47: HashMethod.md5, // NEC PC-8000
    53: HashMethod.md5, // Wonderswan
    57: HashMethod.md5, // Fairchild
    63: HashMethod.md5, // Watara
    69: HashMethod.md5, // Mega Duck
    71: HashMethod.arduboy, // Arduboy
    72: HashMethod.md5, // Wasm-4
  };
  


static final Map<int, List<String>> consoleFileExtensions = {
  // Mega Drive
  1: ['.bin', '.md', '.smd', '.gen'],
  // NES/Famicom
  7: ['.nes', '.fds'],
  // Game Boy
  4: ['.gb', '.gbc'],
  // Game Boy Advance
  5: ['.gba'],
  // Game Boy Color
  6: ['.gb', '.gbc'],
  // SNES/Super Famicom
  3: ['.sfc', '.smc', '.swc', '.fig'],
  // Atari 7800
  51: ['.a78'],
  // Atari Lynx
  13: ['.lnx'],
  // 32X
  10: ['.bin', '.32x'],
  // Master System
  11: ['.bin', '.sms'],
  // Playstation
  12: ['.cue', '.chd'],
  // PC Engine/TurboGrafx-16
  8: ['.pce', '.sgx'],
  // NeoGeo Pocket
  14: ['.ngp', '.ngc'],
  // Game Gear
  15: ['.gg', '.bin'],
  // Atari Jaguar
  17: ['.j64'],
  // Magnavox
  23: ['.bin'],
  // Pokemon Mini
  24: ['.eep', '.min'],
  // Atari 2600
  25: ['.bin', '.a26'],
  //Arcade
  27: ['.zip', '.7z'],
  // Virtual Boy
  28: ['.vb'],
  //MSX
  29: ['.rom', '.dsk'],
  // SG-1000
  33: ['.sg'],
  //Amstrad CPC
  37: ['.dsk', '.bin'],
  //Apple II
  38: ['.dsk', '.woz', '.nib'],
   // 3DO
  43: ['.cue', '.chd'],
  // ColecoVision
  44: ['.col', '.bin'],
  // Intellivision
  45: ['.int', '.bin'],
  // Vectrex
  46: ['.vec'],
  //NEC PC-8000
  47: ['.d88'],
  // Wonderswan
  53: ['.bin', '.ws', '.wsc'],
  // Fairchild
  57: ['.bin'],
  // Watara
  63: ['.sv'],
  // Mega Duck
  69: ['.md2', '.md1'],
  // Arduboy
  71: ['.hex', '.zip'],
  // WASM-4
  72: ['.wasm'],
  
  
};

/// Get supported file extensions for a console
static List<String> getFileExtensionsForConsole(int consoleId) {
  return consoleFileExtensions[consoleId] ?? ['.bin']; // Default to .bin if not found
}

  /// Get the appropriate hash method for a given console ID
  static HashMethod getHashMethodForConsole(int consoleId) {
    return consoleHashMap[consoleId] ?? HashMethod.md5; // Default to MD5 if console not found
  }
  
  /// Check if a console is supported based on hash method availability
  static bool isConsoleSupported(int consoleId) {
    return consoleHashMap.containsKey(consoleId);
  }
  
  /// Get a list of all console IDs that use a specific hash method
  static List<int> getConsolesByHashMethod(HashMethod method) {
    return consoleHashMap.entries
        .where((entry) => entry.value == method)
        .map((entry) => entry.key)
        .toList();
  }
  
  /// Get a list of all supported console IDs
  static List<int> get supportedConsoleIds {
    return consoleHashMap.keys.toList();
  }
}