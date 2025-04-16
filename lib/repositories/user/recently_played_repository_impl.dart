import 'package:retroachievements_organizer/api/user/recently_played_api.dart';
import 'package:retroachievements_organizer/models/user/recently_played_model.dart';
import 'package:retroachievements_organizer/repositories/user/recently_played_repository.dart';
import 'package:retroachievements_organizer/services/storage_service.dart';

class RecentlyPlayedRepositoryImpl implements RecentlyPlayedRepository {
  final RecentlyPlayedApi _recentlyPlayedApi;
  final StorageService _storageService;
  
  RecentlyPlayedRepositoryImpl(this._recentlyPlayedApi, this._storageService);
  
  @override
  Future<Map<String, dynamic>> getUserRecentlyPlayedGamesRaw(String username, String apiKey, {int count = 10, bool useCache = true}) async {
    if (useCache) {
      final cachedData = await getCachedRecentlyPlayedGames(username);
      if (cachedData != null) {
        return {
          'success': true,
          'data': cachedData,
        };
      }
    }
    
    final response = await _recentlyPlayedApi.getUserRecentlyPlayedGames(username, apiKey, count: count);
    
    if (response['success'] && response['data'] != null) {
      await cacheRecentlyPlayedGames(username, response['data']);
    }
    
    return response;
  }
  
  @override
  Future<List<RecentlyPlayedGame>?> getUserRecentlyPlayedGames(String username, String apiKey, {int count = 10, bool useCache = true}) async {
    final response = await getUserRecentlyPlayedGamesRaw(username, apiKey, count: count, useCache: useCache);
    
    if (response['success'] && response['data'] != null) {
      return (response['data'] as List)
          .map((gameData) => RecentlyPlayedGame.fromJson(gameData))
          .toList();
    }
    
    return null;
  }
  
  @override
  Future<void> cacheRecentlyPlayedGames(String username, List<dynamic> data) async {
    await _storageService.saveJsonData({'games': data}, 'recently_played_games', username);
  }
  
  @override
  Future<List<dynamic>?> getCachedRecentlyPlayedGames(String username) async {
    final cachedData = await _storageService.readJsonData('recently_played_games', username);
    return cachedData != null ? cachedData['games'] as List<dynamic> : null;
  }
}