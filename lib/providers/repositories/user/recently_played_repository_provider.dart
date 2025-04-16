// lib/providers/repositories/recently_played_repository_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retroachievements_organizer/api/user/recently_played_api.dart';
import 'package:retroachievements_organizer/repositories/user/recently_played_repository.dart';
import 'package:retroachievements_organizer/repositories/user/recently_played_repository_impl.dart';
import 'package:retroachievements_organizer/services/storage_service.dart';

// Provider for the RecentlyPlayedAPI
final recentlyPlayedApiProvider = Provider<RecentlyPlayedApi>((ref) {
  return RecentlyPlayedApi();
});

// Provider for the RecentlyPlayedRepository
final recentlyPlayedRepositoryProvider = Provider<RecentlyPlayedRepository>((ref) {
  final recentlyPlayedApi = ref.watch(recentlyPlayedApiProvider);
  final storageService = ref.watch(storageServiceProvider);
  return RecentlyPlayedRepositoryImpl(recentlyPlayedApi, storageService);
});