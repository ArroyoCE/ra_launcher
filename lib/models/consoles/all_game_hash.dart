// lib/models/consoles/all_game_hash.dart

class GameHash {
  final String title;
  final int id;
  final int consoleId;
  final String consoleName;
  final String imageIcon;
  final int numAchievements;
  final int numLeaderboards;
  final int points;
  final String dateModified;
  final int forumTopicId;
  final List<String> hashes;

  GameHash({
    required this.title,
    required this.id,
    required this.consoleId,
    required this.consoleName,
    required this.imageIcon,
    required this.numAchievements,
    required this.numLeaderboards,
    required this.points,
    required this.dateModified,
    required this.forumTopicId,
    required this.hashes,
  });

  factory GameHash.fromJson(Map<String, dynamic> json) {
    // Handle the hashes which can be either a list of strings or a list of dynamic
    List<String> parsedHashes = [];
    if (json['Hashes'] != null) {
      parsedHashes = (json['Hashes'] as List).map((hash) => hash.toString()).toList();
    }

    return GameHash(
      title: json['Title'] ?? '',
      id: json['ID'] is int ? json['ID'] : int.tryParse(json['ID'].toString()) ?? 0,
      consoleId: json['ConsoleID'] is int ? json['ConsoleID'] : int.tryParse(json['ConsoleID'].toString()) ?? 0,
      consoleName: json['ConsoleName'] ?? '',
      imageIcon: json['ImageIcon'] ?? '',
      numAchievements: json['NumAchievements'] is int ? json['NumAchievements'] : int.tryParse(json['NumAchievements'].toString()) ?? 0,
      numLeaderboards: json['NumLeaderboards'] is int ? json['NumLeaderboards'] : int.tryParse(json['NumLeaderboards'].toString()) ?? 0,
      points: json['Points'] is int ? json['Points'] : int.tryParse(json['Points'].toString()) ?? 0,
      dateModified: json['DateModified'] ?? '',
      forumTopicId: json['ForumTopicID'] is int ? json['ForumTopicID'] : int.tryParse(json['ForumTopicID'].toString()) ?? 0,
      hashes: parsedHashes,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'Title': title,
      'ID': id,
      'ConsoleID': consoleId,
      'ConsoleName': consoleName,
      'ImageIcon': imageIcon,
      'NumAchievements': numAchievements,
      'NumLeaderboards': numLeaderboards,
      'Points': points,
      'DateModified': dateModified,
      'ForumTopicID': forumTopicId,
      'Hashes': hashes,
    };
  }
}