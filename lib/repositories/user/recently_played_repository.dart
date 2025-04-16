import 'package:retroachievements_organizer/models/user/recently_played_model.dart';

abstract class RecentlyPlayedRepository {
  Future<Map<String, dynamic>> getUserRecentlyPlayedGamesRaw(String username, String apiKey, {int count = 10, bool useCache = true});
  Future<List<RecentlyPlayedGame>?> getUserRecentlyPlayedGames(String username, String apiKey, {int count = 10, bool useCache = true});
  Future<void> cacheRecentlyPlayedGames(String username, List<dynamic> data);
  Future<List<dynamic>?> getCachedRecentlyPlayedGames(String username);
}