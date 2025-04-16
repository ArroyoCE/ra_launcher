// lib/repositories/all_consoles_repository.dart

abstract class AllConsolesRepository {
  Future<Map<String, dynamic>> getConsoleIDsRaw(String apiKey, {bool useCache = true});
  Future<List<dynamic>?> getConsoleIDs(String apiKey, {bool useCache = true});
  Future<void> cacheConsoleIDs(List<dynamic> data);
  Future<List<dynamic>?> getCachedConsoleIDs();
}