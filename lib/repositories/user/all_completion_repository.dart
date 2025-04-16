abstract class AllCompletionRepository {
  Future<Map<String, dynamic>> getUserCompletionProgressRaw(String username, String apiKey, {bool useCache = true});
  Future<Map<String, dynamic>?> getUserCompletionProgress(String username, String apiKey, {bool useCache = true});
  Future<void> cacheCompletionProgress(String username, Map<String, dynamic> data);
  Future<Map<String, dynamic>?> getCachedCompletionProgress(String username);
}