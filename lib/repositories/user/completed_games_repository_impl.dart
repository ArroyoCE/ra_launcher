import 'package:retroachievements_organizer/api/user/completed_games_api.dart';
import 'package:retroachievements_organizer/models/user/completed_game.dart';
import 'package:retroachievements_organizer/repositories/user/completed_games_repository.dart';
import 'package:retroachievements_organizer/services/storage_service.dart';

class CompletedGamesRepositoryImpl implements CompletedGamesRepository {
  final CompletedGamesApi _completedGamesApi;
  final StorageService _storageService;
  
  CompletedGamesRepositoryImpl(this._completedGamesApi, this._storageService);
  
  @override
  Future<Map<String, dynamic>> getUserCompletedGamesRaw(String username, String apiKey, {bool useCache = true}) async {
    if (useCache) {
      final cachedData = await getCachedCompletedGames(username);
      if (cachedData != null) {
        return {
          'success': true,
          'data': cachedData,
        };
      }
    }
    
    final response = await _completedGamesApi.getUserCompletedGames(username, apiKey);
    
    if (response['success'] && response['data'] != null) {
      await cacheCompletedGames(username, response['data']);
    }
    
    return response;
  }
  
  @override
  Future<List<CompletedGame>?> getUserCompletedGames(String username, String apiKey, {bool useCache = true}) async {
    final response = await getUserCompletedGamesRaw(username, apiKey, useCache: useCache);
    
    if (response['success'] && response['data'] != null) {
      return (response['data'] as List)
          .map((gameData) => CompletedGame.fromJson(gameData))
          .toList();
    }
    
    return null;
  }
  
  @override
  Future<void> cacheCompletedGames(String username, List<dynamic> data) async {
    await _storageService.saveJsonData({'games': data}, 'completed_games', username);
  }
  
  @override
  Future<List<dynamic>?> getCachedCompletedGames(String username) async {
    final cachedData = await _storageService.readJsonData('completed_games', username);
    return cachedData != null ? cachedData['games'] as List<dynamic> : null;
  }
}