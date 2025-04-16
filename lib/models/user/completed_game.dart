class CompletedGame {
  final int gameId;
  final String title;
  final String imageIcon;
  final int consoleId;
  final String consoleName;
  final int maxPossible;
  final int numAwarded;
  final double pctWon;
  final bool hardcoreMode;

  CompletedGame({
    required this.gameId,
    required this.title,
    required this.imageIcon,
    required this.consoleId,
    required this.consoleName,
    required this.maxPossible,
    required this.numAwarded,
    required this.pctWon,
    required this.hardcoreMode,
  });

  factory CompletedGame.fromJson(Map<String, dynamic> json) {
    return CompletedGame(
      gameId: json['GameID'] ?? 0,
      title: json['Title'] ?? '',
      imageIcon: json['ImageIcon'] ?? '',
      consoleId: json['ConsoleID'] ?? 0,
      consoleName: json['ConsoleName'] ?? '',
      maxPossible: int.tryParse(json['MaxPossible']?.toString() ?? '0') ?? 0,
      numAwarded: int.tryParse(json['NumAwarded']?.toString() ?? '0') ?? 0,
      pctWon: double.tryParse(json['PctWon']?.toString() ?? '0') ?? 0.0,
      hardcoreMode: json['HardcoreMode'] == '1' || json['HardcoreMode'] == 1,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'GameID': gameId,
      'Title': title,
      'ImageIcon': imageIcon,
      'ConsoleID': consoleId,
      'ConsoleName': consoleName,
      'MaxPossible': maxPossible,
      'NumAwarded': numAwarded,
      'PctWon': pctWon.toString(),
      'HardcoreMode': hardcoreMode ? '1' : '0',
    };
  }

  double getCompletionPercentage() {
    return pctWon * 100;
  }
}