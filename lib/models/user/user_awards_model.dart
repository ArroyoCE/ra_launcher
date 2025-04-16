class UserAwards {
  final int totalAwardsCount;
  final int hiddenAwardsCount;
  final int masteryAwardsCount;
  final int completionAwardsCount;
  final int beatenHardcoreAwardsCount;
  final int beatenSoftcoreAwardsCount;
  final int eventAwardsCount;
  final int siteAwardsCount;
  final List<UserAward> visibleUserAwards;

  UserAwards({
    required this.totalAwardsCount,
    required this.hiddenAwardsCount,
    required this.masteryAwardsCount,
    required this.completionAwardsCount,
    required this.beatenHardcoreAwardsCount,
    required this.beatenSoftcoreAwardsCount,
    required this.eventAwardsCount,
    required this.siteAwardsCount,
    required this.visibleUserAwards,
  });

  factory UserAwards.fromJson(Map<String, dynamic> json) {
    List<UserAward> awards = [];
    if (json['VisibleUserAwards'] != null) {
      awards = (json['VisibleUserAwards'] as List)
          .map((award) => UserAward.fromJson(award))
          .toList();
    }

    return UserAwards(
      totalAwardsCount: json['TotalAwardsCount'] ?? 0,
      hiddenAwardsCount: json['HiddenAwardsCount'] ?? 0,
      masteryAwardsCount: json['MasteryAwardsCount'] ?? 0,
      completionAwardsCount: json['CompletionAwardsCount'] ?? 0,
      beatenHardcoreAwardsCount: json['BeatenHardcoreAwardsCount'] ?? 0,
      beatenSoftcoreAwardsCount: json['BeatenSoftcoreAwardsCount'] ?? 0,
      eventAwardsCount: json['EventAwardsCount'] ?? 0,
      siteAwardsCount: json['SiteAwardsCount'] ?? 0,
      visibleUserAwards: awards,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'TotalAwardsCount': totalAwardsCount,
      'HiddenAwardsCount': hiddenAwardsCount,
      'MasteryAwardsCount': masteryAwardsCount,
      'CompletionAwardsCount': completionAwardsCount,
      'BeatenHardcoreAwardsCount': beatenHardcoreAwardsCount,
      'BeatenSoftcoreAwardsCount': beatenSoftcoreAwardsCount,
      'EventAwardsCount': eventAwardsCount,
      'SiteAwardsCount': siteAwardsCount,
      'VisibleUserAwards': visibleUserAwards.map((award) => award.toJson()).toList(),
    };
  }
}

class UserAward {
  final String awardedAt;
  final String awardType;
  final int awardData;
  final int awardDataExtra;
  final int displayOrder;
  final String title;
  final int consoleId;
  final String consoleName;
  final int flags;
  final String imageIcon;

  UserAward({
    required this.awardedAt,
    required this.awardType,
    required this.awardData,
    required this.awardDataExtra,
    required this.displayOrder,
    required this.title,
    required this.consoleId,
    required this.consoleName,
    required this.flags,
    required this.imageIcon,
  });

  factory UserAward.fromJson(Map<String, dynamic> json) {
    return UserAward(
      awardedAt: json['AwardedAt'] ?? '',
      awardType: json['AwardType'] ?? '',
      awardData: json['AwardData'] ?? 0,
      awardDataExtra: json['AwardDataExtra'] ?? 0,
      displayOrder: json['DisplayOrder'] ?? 0,
      title: json['Title'] ?? '',
      consoleId: json['ConsoleID'] ?? 0,
      consoleName: json['ConsoleName'] ?? '',
      flags: json['Flags'] ?? 0,
      imageIcon: json['ImageIcon'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'AwardedAt': awardedAt,
      'AwardType': awardType,
      'AwardData': awardData,
      'AwardDataExtra': awardDataExtra,
      'DisplayOrder': displayOrder,
      'Title': title,
      'ConsoleID': consoleId,
      'ConsoleName': consoleName,
      'Flags': flags,
      'ImageIcon': imageIcon,
    };
  }
}