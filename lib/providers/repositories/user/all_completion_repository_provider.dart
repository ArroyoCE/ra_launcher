import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retroachievements_organizer/api/user/all_completion_api.dart';
import 'package:retroachievements_organizer/repositories/user/all_completion_repository_impl.dart';
import 'package:retroachievements_organizer/repositories/user/all_completion_repository.dart';
import 'package:retroachievements_organizer/services/storage_service.dart';

// Provider for the AllCompletionAPI
final allCompletionApiProvider = Provider<AllCompletionApi>((ref) {
  return AllCompletionApi();
});

// Provider for the AllCompletionRepository
final allCompletionRepositoryProvider = Provider<AllCompletionRepository>((ref) {
  final allCompletionApi = ref.watch(allCompletionApiProvider);
  final storageService = ref.watch(storageServiceProvider);
  return AllCompletionRepositoryImpl(allCompletionApi, storageService);
});