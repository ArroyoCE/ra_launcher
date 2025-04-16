// lib/repositories/all_games_hashes_repository.dart

abstract class AllGamesHashesRepository {
  Future<Map<String, dynamic>> getGameListRaw(String systemId, String apiKey, {bool useCache = true});
  Future<List<dynamic>?> getGameList(String systemId, String apiKey, {bool useCache = true});
  Future<void> cacheGameList(String systemId, List<dynamic> data);
  Future<List<dynamic>?> getCachedGameList(String systemId);
}