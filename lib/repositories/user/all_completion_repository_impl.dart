import 'package:retroachievements_organizer/api/user/all_completion_api.dart';
import 'package:retroachievements_organizer/repositories/user/all_completion_repository.dart';
import 'package:retroachievements_organizer/services/storage_service.dart';

class AllCompletionRepositoryImpl implements AllCompletionRepository {
  final AllCompletionApi _allCompletionApi;
  final StorageService _storageService;
  
  AllCompletionRepositoryImpl(this._allCompletionApi, this._storageService);
  
  @override
  Future<Map<String, dynamic>> getUserCompletionProgressRaw(String username, String apiKey, {bool useCache = true}) async {
    if (useCache) {
      final cachedData = await getCachedCompletionProgress(username);
      if (cachedData != null) {
        return {
          'success': true,
          'data': cachedData,
        };
      }
    }
    
    final response = await _allCompletionApi.getUserCompletionProgress(username, apiKey);
    
    if (response['success'] && response['data'] != null) {
      await cacheCompletionProgress(username, response['data']);
    }
    
    return response;
  }
  
  @override
  Future<Map<String, dynamic>?> getUserCompletionProgress(String username, String apiKey, {bool useCache = true}) async {
    final response = await getUserCompletionProgressRaw(username, apiKey, useCache: useCache);
    
    if (response['success'] && response['data'] != null) {
      return response['data'];
    }
    
    return null;
  }
  
  @override
  Future<void> cacheCompletionProgress(String username, Map<String, dynamic> data) async {
    await _storageService.saveJsonData(data, 'user_completion_progress', username);
  }
  
  @override
  Future<Map<String, dynamic>?> getCachedCompletionProgress(String username) async {
    return await _storageService.readJsonData('user_completion_progress', username);
  }
}