import 'package:retroachievements_organizer/api/user/user_awards_api.dart';
import 'package:retroachievements_organizer/models/user/user_awards_model.dart';
import 'package:retroachievements_organizer/repositories/user/user_awards_repository.dart';
import 'package:retroachievements_organizer/services/storage_service.dart';

class UserAwardsRepositoryImpl implements UserAwardsRepository {
  final UserAwardsApi _userAwardsApi;
  final StorageService _storageService;
  
  UserAwardsRepositoryImpl(this._userAwardsApi, this._storageService);
  
  @override
  Future<Map<String, dynamic>> getUserAwardsRaw(String username, String apiKey, {bool useCache = true}) async {
    if (useCache) {
      final cachedData = await getCachedUserAwards(username);
      if (cachedData != null) {
        return {
          'success': true,
          'data': cachedData,
        };
      }
    }
    
    final response = await _userAwardsApi.getUserAwards(username, apiKey);
    
    if (response['success'] && response['data'] != null) {
      await cacheUserAwards(username, response['data']);
    }
    
    return response;
  }
  
  @override
  Future<UserAwards?> getUserAwards(String username, String apiKey, {bool useCache = true}) async {
    final response = await getUserAwardsRaw(username, apiKey, useCache: useCache);
    
    if (response['success'] && response['data'] != null) {
      return UserAwards.fromJson(response['data']);
    }
    
    return null;
  }
  
  @override
  Future<void> cacheUserAwards(String username, Map<String, dynamic> data) async {
    await _storageService.saveJsonData(data, 'user_awards', username);
  }
  
  @override
  Future<Map<String, dynamic>?> getCachedUserAwards(String username) async {
    return await _storageService.readJsonData('user_awards', username);
  }
}