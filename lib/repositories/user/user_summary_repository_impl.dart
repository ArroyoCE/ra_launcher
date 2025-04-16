import 'package:retroachievements_organizer/api/user/user_summary_api.dart';
import 'package:retroachievements_organizer/models/user/user_summary_model.dart';
import 'package:retroachievements_organizer/repositories/user/user_summary_repository.dart';
import 'package:retroachievements_organizer/services/storage_service.dart';

class UserSummaryRepositoryImpl implements UserSummaryRepository {
  final UserSummaryApi _userSummaryApi;
  final StorageService _storageService;
  
  UserSummaryRepositoryImpl(this._userSummaryApi, this._storageService);
  
  @override
  Future<Map<String, dynamic>> getUserSummaryRaw(String username, String apiKey, {bool useCache = true}) async {
    if (useCache) {
      final cachedData = await getCachedUserSummary(username);
      if (cachedData != null) {
        return {
          'success': true,
          'data': cachedData,
        };
      }
    }
    
    final response = await _userSummaryApi.getUserSummary(username, apiKey);
    
    if (response['success'] && response['data'] != null) {
      await cacheUserSummary(username, response['data']);
    }
    
    return response;
  }
  
  @override
  Future<UserSummary?> getUserSummary(String username, String apiKey, {bool useCache = true}) async {
    final response = await getUserSummaryRaw(username, apiKey, useCache: useCache);
    
    if (response['success'] && response['data'] != null) {
      return UserSummary.fromJson(response['data']);
    }
    
    return null;
  }
  
  @override
  Future<void> cacheUserSummary(String username, Map<String, dynamic> data) async {
    await _storageService.saveJsonData(data, 'user_summary', username);
  }
  
  @override
  Future<Map<String, dynamic>?> getCachedUserSummary(String username) async {
    return await _storageService.readJsonData('user_summary', username);
  }
}