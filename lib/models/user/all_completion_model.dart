// lib/models/completion_progress.dart

class CompletionProgress {
  final int count;
  final int total;
  final List<GameProgress> results;

  CompletionProgress({
    required this.count,
    required this.total,
    required this.results,
  });

  factory CompletionProgress.fromJson(Map<String, dynamic> json) {
    List<GameProgress> gameProgressList = [];
    if (json['Results'] != null) {
      gameProgressList = (json['Results'] as List)
          .map((progress) => GameProgress.fromJson(progress))
          .toList();
    }

    return CompletionProgress(
      count: json['Count'] ?? 0,
      total: json['Total'] ?? 0,
      results: gameProgressList,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'Count': count,
      'Total': total,
      'Results': results.map((progress) => progress.toJson()).toList(),
    };
  }
}

class GameProgress {
  final int gameId;
  final String title;
  final String imageIcon;
  final int consoleId;
  final String consoleName;
  final int maxPossible;
  final int numAwarded;
  final int numAwardedHardcore;
  final String mostRecentAwardedDate;
  final String highestAwardKind;
  final String highestAwardDate;

  GameProgress({
    required this.gameId,
    required this.title,
    required this.imageIcon,
    required this.consoleId,
    required this.consoleName,
    required this.maxPossible,
    required this.numAwarded,
    required this.numAwardedHardcore,
    required this.mostRecentAwardedDate,
    required this.highestAwardKind,
    required this.highestAwardDate,
  });

  factory GameProgress.fromJson(Map<String, dynamic> json) {
    return GameProgress(
      gameId: json['GameID'] ?? 0,
      title: json['Title'] ?? '',
      imageIcon: json['ImageIcon'] ?? '',
      consoleId: json['ConsoleID'] ?? 0,
      consoleName: json['ConsoleName'] ?? '',
      maxPossible: json['MaxPossible'] ?? 0,
      numAwarded: json['NumAwarded'] ?? 0,
      numAwardedHardcore: json['NumAwardedHardcore'] ?? 0,
      mostRecentAwardedDate: json['MostRecentAwardedDate'] ?? '',
      highestAwardKind: json['HighestAwardKind'] ?? '',
      highestAwardDate: json['HighestAwardDate'] ?? '',
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
      'NumAwardedHardcore': numAwardedHardcore,
      'MostRecentAwardedDate': mostRecentAwardedDate,
      'HighestAwardKind': highestAwardKind,
      'HighestAwardDate': highestAwardDate,
    };
  }

  double getCompletionPercentage() {
    if (maxPossible == 0) return 0.0;
    return (numAwardedHardcore / maxPossible) * 100;
  }
}