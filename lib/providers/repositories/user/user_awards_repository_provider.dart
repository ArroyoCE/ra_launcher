// lib/providers/repositories/user_awards_repository_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retroachievements_organizer/api/user/user_awards_api.dart';
import 'package:retroachievements_organizer/repositories/user/user_awards_repository.dart';
import 'package:retroachievements_organizer/repositories/user/user_awards_repository_impl.dart';
import 'package:retroachievements_organizer/services/storage_service.dart';

// Provider for the UserAwardsAPI
final userAwardsApiProvider = Provider<UserAwardsApi>((ref) {
  return UserAwardsApi();
});

// Provider for the UserAwardsRepository
final userAwardsRepositoryProvider = Provider<UserAwardsRepository>((ref) {
  final userAwardsApi = ref.watch(userAwardsApiProvider);
  final storageService = ref.watch(storageServiceProvider);
  return UserAwardsRepositoryImpl(userAwardsApi, storageService);
});