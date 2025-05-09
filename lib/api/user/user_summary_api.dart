// lib/api/user_summary_api.dart

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:retroachievements_organizer/constants/api_constants.dart';

class UserSummaryApi {
  Future<Map<String, dynamic>> getUserSummary(String username, String apiKey, {bool useCache = true}) async {
    try {
      final url = ApiConstants.getUserSummaryUrl(username, apiKey);
      final response = await http.get(Uri.parse(url));
      
      if (response.statusCode == 200) {
        final decodedResponse = json.decode(response.body);
        return {
          'success': true,
          'data': decodedResponse,
        };
      } else {
        return {
          'success': false,
          'error': 'Failed to load user summary: ${response.statusCode}',
        };
      }
    } catch (e) {
      debugPrint('Error getting user summary: $e');
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }
}

/*
HTML RESPONSE EXAMPLE
{
  "User": "xelnia",
  "ULID": "00003EMFWR7XB8SDPEHB3K56ZQ",
  "MemberSince": "2021-12-20 03:13:20",
  "LastActivity": {
    "ID": 0,
    "timestamp": null,
    "lastupdate": null,
    "activitytype": null,
    "User": "xelnia",
    "data": null,
    "data2": null
  },
  "RichPresenceMsg": "L=08-1 | 1 lives | 189300 points",
  "LastGameID": 15758,
  "ContribCount": 0,
  "ContribYield": 0,
  "TotalPoints": 8317,
  "TotalSoftcorePoints": 0,
  "TotalTruePoints": 26760,
  "Permissions": 1,
  "Untracked": 0,
  "ID": 224958,
  "UserWallActive": 1,
  "Motto": "",
  "Rank": 4616,
  "RecentlyPlayedCount": 1,
  "RecentlyPlayed": [
    {
      "GameID": 15758,
      "ConsoleID": 27,
      "ConsoleName": "Arcade",
      "Title": "Crazy Kong",
      "ImageIcon": "/Images/068578.png",
      "ImageTitle": "/Images/068579.png",
      "ImageIngame": "/Images/068580.png",
      "ImageBoxArt": "/Images/068205.png",
      "LastPlayed": "2023-03-09 08:20:34",
      "AchievementsTotal": 43
    }
  ],
  "Awarded": {
    "15758": {
      "NumPossibleAchievements": 43,
      "PossibleScore": 615,
      "NumAchieved": 41,
      "ScoreAchieved": 490,
      "NumAchievedHardcore": 41,
      "ScoreAchievedHardcore": 490
    }
  },
  "RecentAchievements": {
    "15758": {
      "293505": {
        "ID": 293505,
        "GameID": 15758,
        "GameTitle": "Crazy Kong",
        "Title": "Prodigy of the Arcade",
        "Description": "Score 200,000 points",
        "Points": 25,
        "Type": null,
        "BadgeName": "325551",
        "IsAwarded": "1",
        "DateAwarded": "2023-03-09 08:20:34",
        "HardcoreAchieved": 1
      },
      "293526": {
        "ID": 293526,
        "GameID": 15758,
        "GameTitle": "Crazy Kong",
        "Title": "Super Smasher III",
        "Description": "Get 6 smashes with a single bottom hammer on any barrel board",
        "Points": 10,
        "Type": null,
        "BadgeName": "325572",
        "IsAwarded": "1",
        "DateAwarded": "2023-03-09 08:19:37",
        "HardcoreAchieved": 1
      }
    }
  },
  "LastGame": {
    "ID": 15758,
    "Title": "Crazy Kong",
    "ConsoleID": 27,
    "ConsoleName": "Arcade",
    "ForumTopicID": 20415,
    "Flags": 0,
    "ImageIcon": "/Images/068578.png",
    "ImageTitle": "/Images/068579.png",
    "ImageIngame": "/Images/068580.png",
    "ImageBoxArt": "/Images/068205.png",
    "Publisher": "Falcon",
    "Developer": "Falcon",
    "Genre": "2D Platforming, Arcade",
    "Released": "1981-01-01",
    "ReleasedAtGranularity": "year",
    "IsFinal": 0
  },
  "UserPic": "/UserPic/xelnia.png",
  "TotalRanked": 45654,
  "Status": "Offline"
}
*/