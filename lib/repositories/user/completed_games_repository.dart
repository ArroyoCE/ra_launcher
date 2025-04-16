import 'package:retroachievements_organizer/models/user/completed_game.dart';

abstract class CompletedGamesRepository {
  Future<Map<String, dynamic>> getUserCompletedGamesRaw(String username, String apiKey, {bool useCache = true});
  Future<List<CompletedGame>?> getUserCompletedGames(String username, String apiKey, {bool useCache = true});
  Future<void> cacheCompletedGames(String username, List<dynamic> data);
  Future<List<dynamic>?> getCachedCompletedGames(String username);
}