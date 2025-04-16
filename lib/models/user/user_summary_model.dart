// lib/models/user/user_summary_model.dart

class UserSummary {
  final String username;
  final String userPic;
  final String memberSince;
  final String richPresenceMsg;
  final Map<String, dynamic>? lastActivity;
  final int lastGameId;
  final int totalPoints;
  final int rank;
  final int totalTruePoints;
  final List<dynamic> recentlyPlayed;
  final Map<String, dynamic> awarded;
  final Map<String, dynamic> recentAchievements;
  final Map<String, dynamic>? lastGame;
  final String status;
  final int totalRanked;

  UserSummary({
    required this.username,
    required this.userPic,
    required this.memberSince,
    required this.richPresenceMsg,
    this.lastActivity,
    required this.lastGameId,
    required this.totalPoints,
    required this.rank,
    required this.totalTruePoints,
    required this.recentlyPlayed,
    required this.awarded,
    required this.recentAchievements,
    this.lastGame,
    required this.status,
    required this.totalRanked,
  });

  factory UserSummary.fromJson(Map<String, dynamic> json) {
    return UserSummary(
      username: json['User'] ?? '',
      userPic: json['UserPic'] ?? '',
      memberSince: json['MemberSince'] ?? '',
      richPresenceMsg: json['RichPresenceMsg'] ?? '',
      lastActivity: json['LastActivity'] as Map<String, dynamic>?,
      lastGameId: json['LastGameID'] is int ? json['LastGameID'] : int.tryParse(json['LastGameID'].toString()) ?? 0,
      totalPoints: json['TotalPoints'] is int ? json['TotalPoints'] : int.tryParse(json['TotalPoints'].toString()) ?? 0,
      rank: json['Rank'] is int ? json['Rank'] : int.tryParse(json['Rank'].toString()) ?? 0,
      totalTruePoints: json['TotalTruePoints'] is int ? json['TotalTruePoints'] : int.tryParse(json['TotalTruePoints'].toString()) ?? 0,
      recentlyPlayed: json['RecentlyPlayed'] ?? [],
      awarded: json['Awarded'] ?? {},
      recentAchievements: json['RecentAchievements'] ?? {},
      lastGame: json['LastGame'] as Map<String, dynamic>?,
      status: json['Status'] ?? 'Offline',
      totalRanked: json['TotalRanked'] is int ? json['TotalRanked'] : int.tryParse(json['TotalRanked'].toString()) ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'User': username,
      'UserPic': userPic,
      'MemberSince': memberSince,
      'RichPresenceMsg': richPresenceMsg,
      'LastActivity': lastActivity,
      'LastGameID': lastGameId,
      'TotalPoints': totalPoints,
      'Rank': rank,
      'TotalTruePoints': totalTruePoints,
      'RecentlyPlayed': recentlyPlayed,
      'Awarded': awarded,
      'RecentAchievements': recentAchievements,
      'LastGame': lastGame,
      'Status': status,
      'TotalRanked': totalRanked,
    };
  }
}