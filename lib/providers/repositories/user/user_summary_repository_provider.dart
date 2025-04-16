// lib/providers/repositories/user_summary_repository_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retroachievements_organizer/api/user/user_summary_api.dart';
import 'package:retroachievements_organizer/repositories/user/user_summary_repository.dart';
import 'package:retroachievements_organizer/repositories/user/user_summary_repository_impl.dart';
import 'package:retroachievements_organizer/services/storage_service.dart';

// Provider for the UserSummaryAPI
final userSummaryApiProvider = Provider<UserSummaryApi>((ref) {
  return UserSummaryApi();
});

// Provider for the UserSummaryRepository
final userSummaryRepositoryProvider = Provider<UserSummaryRepository>((ref) {
  final userSummaryApi = ref.watch(userSummaryApiProvider);
  final storageService = ref.watch(storageServiceProvider);
  return UserSummaryRepositoryImpl(userSummaryApi, storageService);
});