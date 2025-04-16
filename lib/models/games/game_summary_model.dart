// lib/models/game_summary_model.dart

class GameSummary {
  final int id;
  final String title;
  final String consoleName;
  final int consoleId;
  final String imageIcon;
  final String imageTitle;
  final String imageIngame;
  final String imageBoxArt;
  final String publisher;
  final String developer;
  final String genre;
  final String released;
  final int numAchievements;
  final int numLeaderboards;
  final int points;
  final String dateModified;
  final int forumTopicId;

  GameSummary({
    required this.id,
    required this.title,
    required this.consoleName,
    required this.consoleId,
    required this.imageIcon,
    required this.imageTitle,
    required this.imageIngame,
    required this.imageBoxArt,
    required this.publisher,
    required this.developer,
    required this.genre,
    required this.released,
    required this.numAchievements,
    required this.numLeaderboards,
    required this.points,
    required this.dateModified,
    required this.forumTopicId,
  });

  factory GameSummary.fromJson(Map<String, dynamic> json) {
    return GameSummary(
      id: json['ID'] != null ? int.parse(json['ID'].toString()) : 0,
      title: json['Title'] ?? '',
      consoleName: json['ConsoleName'] ?? '',
      consoleId: json['ConsoleID'] != null ? int.parse(json['ConsoleID'].toString()) : 0,
      imageIcon: json['ImageIcon'] ?? '',
      imageTitle: json['ImageTitle'] ?? '',
      imageIngame: json['ImageIngame'] ?? '',
      imageBoxArt: json['ImageBoxArt'] ?? '',
      publisher: json['Publisher'] ?? '',
      developer: json['Developer'] ?? '',
      genre: json['Genre'] ?? '',
      released: json['Released'] ?? '',
      numAchievements: json['NumAchievements'] != null ? int.parse(json['NumAchievements'].toString()) : 0,
      numLeaderboards: json['NumLeaderboards'] != null ? int.parse(json['NumLeaderboards'].toString()) : 0,
      points: json['Points'] != null ? int.parse(json['Points'].toString()) : 0,
      dateModified: json['DateModified'] ?? '',
      forumTopicId: json['ForumTopicID'] != null ? int.parse(json['ForumTopicID'].toString()) : 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'ID': id,
      'Title': title,
      'ConsoleName': consoleName,
      'ConsoleID': consoleId,
      'ImageIcon': imageIcon,
      'ImageTitle': imageTitle,
      'ImageIngame': imageIngame,
      'ImageBoxArt': imageBoxArt,
      'Publisher': publisher,
      'Developer': developer,
      'Genre': genre,
      'Released': released,
      'NumAchievements': numAchievements,
      'NumLeaderboards': numLeaderboards,
      'DateModified': dateModified,
      'ForumTopicID': forumTopicId,
    };
  }
}