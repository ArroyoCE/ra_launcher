import 'package:retroachievements_organizer/models/user/user_awards_model.dart';

abstract class UserAwardsRepository {
  Future<Map<String, dynamic>> getUserAwardsRaw(String username, String apiKey, {bool useCache = true});
  Future<UserAwards?> getUserAwards(String username, String apiKey, {bool useCache = true});
  Future<void> cacheUserAwards(String username, Map<String, dynamic> data);
  Future<Map<String, dynamic>?> getCachedUserAwards(String username);
}