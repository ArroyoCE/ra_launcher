// lib/repositories/user_summary_repository.dart
import 'package:retroachievements_organizer/models/user/user_summary_model.dart';


abstract class UserSummaryRepository {
  Future<Map<String, dynamic>> getUserSummaryRaw(String username, String apiKey, {bool useCache = true});
  Future<UserSummary?> getUserSummary(String username, String apiKey, {bool useCache = true});
  Future<void> cacheUserSummary(String username, Map<String, dynamic> data);
  Future<Map<String, dynamic>?> getCachedUserSummary(String username);
}