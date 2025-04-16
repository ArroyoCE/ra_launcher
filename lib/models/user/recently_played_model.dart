class RecentlyPlayedGame {
  final int gameId;
  final int consoleId;
  final String consoleName;
  final String title;
  final String imageIcon;
  final String imageTitle;
  final String imageIngame;
  final String imageBoxArt;
  final String lastPlayed;
  final int achievementsTotal;
  final int numPossibleAchievements;
  final int possibleScore;
  final int numAchieved;
  final int scoreAchieved;
  final int numAchievedHardcore;
  final int scoreAchievedHardcore;

  RecentlyPlayedGame({
    required this.gameId,
    required this.consoleId,
    required this.consoleName,
    required this.title,
    required this.imageIcon,
    required this.imageTitle,
    required this.imageIngame,
    required this.imageBoxArt,
    required this.lastPlayed,
    required this.achievementsTotal,
    required this.numPossibleAchievements,
    required this.possibleScore,
    required this.numAchieved,
    required this.scoreAchieved,
    required this.numAchievedHardcore,
    required this.scoreAchievedHardcore,
  });

  factory RecentlyPlayedGame.fromJson(Map<String, dynamic> json) {
    return RecentlyPlayedGame(
      gameId: json['GameID'] ?? 0,
      consoleId: json['ConsoleID'] ?? 0,
      consoleName: json['ConsoleName'] ?? '',
      title: json['Title'] ?? '',
      imageIcon: json['ImageIcon'] ?? '',
      imageTitle: json['ImageTitle'] ?? '',
      imageIngame: json['ImageIngame'] ?? '',
      imageBoxArt: json['ImageBoxArt'] ?? '',
      lastPlayed: json['LastPlayed'] ?? '',
      achievementsTotal: json['AchievementsTotal'] ?? 0,
      numPossibleAchievements: json['NumPossibleAchievements'] ?? 0,
      possibleScore: json['PossibleScore'] ?? 0,
      numAchieved: json['NumAchieved'] ?? 0,
      scoreAchieved: json['ScoreAchieved'] ?? 0,
      numAchievedHardcore: json['NumAchievedHardcore'] ?? 0,
      scoreAchievedHardcore: json['ScoreAchievedHardcore'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'GameID': gameId,
      'ConsoleID': consoleId,
      'ConsoleName': consoleName,
      'Title': title,
      'ImageIcon': imageIcon,
      'ImageTitle': imageTitle,
      'ImageIngame': imageIngame,
      'ImageBoxArt': imageBoxArt,
      'LastPlayed': lastPlayed,
      'AchievementsTotal': achievementsTotal,
      'NumPossibleAchievements': numPossibleAchievements,
      'PossibleScore': possibleScore,
      'NumAchieved': numAchieved,
      'ScoreAchieved': scoreAchieved,
      'NumAchievedHardcore': numAchievedHardcore,
      'ScoreAchievedHardcore': scoreAchievedHardcore,
    };
  }

  double getCompletionPercentage() {
    if (numPossibleAchievements == 0) return 0.0;
    return (numAchievedHardcore / numPossibleAchievements) * 100;
  }
}