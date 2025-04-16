// lib/models/achievement.dart

class Achievement {
  final int id;
  final String title;
  final String description;
  final int points;
  final int trueRatio;
  final String author;
  final String dateCreated;
  final String dateModified;
  final String badgeName; // This is the image name
  final int displayOrder;
  final int gameId;
  final int memAddr;
  final bool isAwarded;
  final String dateAwarded;
  final bool hardcoreAchieved;
  final String hardcoreDateAwarded;

  Achievement({
    required this.id,
    required this.title,
    required this.description,
    required this.points,
    required this.trueRatio,
    required this.author,
    required this.dateCreated,
    required this.dateModified,
    required this.badgeName,
    required this.displayOrder,
    required this.gameId,
    required this.memAddr,
    required this.isAwarded,
    required this.dateAwarded,
    required this.hardcoreAchieved,
    required this.hardcoreDateAwarded,
  });

  factory Achievement.fromJson(Map<String, dynamic> json) {
    return Achievement(
      id: json['ID'] != null ? int.parse(json['ID'].toString()) : 0,
      title: json['Title'] ?? '',
      description: json['Description'] ?? '',
      points: json['Points'] != null ? int.parse(json['Points'].toString()) : 0,
      trueRatio: json['TrueRatio'] != null ? int.parse(json['TrueRatio'].toString()) : 0,
      author: json['Author'] ?? '',
      dateCreated: json['DateCreated'] ?? '',
      dateModified: json['DateModified'] ?? '',
      badgeName: json['BadgeName'] ?? '',
      displayOrder: json['DisplayOrder'] != null ? int.parse(json['DisplayOrder'].toString()) : 0,
      gameId: json['GameID'] != null ? int.parse(json['GameID'].toString()) : 0,
      memAddr: json['MemAddr'] != null ? int.parse(json['MemAddr'].toString()) : 0,
      isAwarded: json['DateEarned'] != null && json['DateEarned'].toString().isNotEmpty,
      dateAwarded: json['DateEarned'] ?? '',
      hardcoreAchieved: json['HardcoreAchieved'] == 1,
      hardcoreDateAwarded: json['HardcoreDateEarned'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'ID': id,
      'Title': title,
      'Description': description,
      'Points': points,
      'TrueRatio': trueRatio,
      'Author': author,
      'DateCreated': dateCreated,
      'DateModified': dateModified,
      'BadgeName': badgeName,
      'DisplayOrder': displayOrder,
      'GameID': gameId,
      'MemAddr': memAddr,
      'DateEarned': dateAwarded,
      'HardcoreAchieved': hardcoreAchieved ? 1 : 0,
      'HardcoreDateEarned': hardcoreDateAwarded,
    };
  }
  
  // Create the full badge image URL
  String getBadgeUrl() {
    return 'https://retroachievements.org/Badge/$badgeName';
  }
}