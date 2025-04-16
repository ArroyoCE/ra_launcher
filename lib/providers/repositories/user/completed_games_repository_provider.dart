// lib/providers/repositories/completed_games_repository_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retroachievements_organizer/api/user/completed_games_api.dart';
import 'package:retroachievements_organizer/repositories/user/completed_games_repository.dart';
import 'package:retroachievements_organizer/repositories/user/completed_games_repository_impl.dart';
import 'package:retroachievements_organizer/services/storage_service.dart';

// Provider for the CompletedGamesAPI
final completedGamesApiProvider = Provider<CompletedGamesApi>((ref) {
  return CompletedGamesApi();
});

// Provider for the CompletedGamesRepository
final completedGamesRepositoryProvider = Provider<CompletedGamesRepository>((ref) {
  final completedGamesApi = ref.watch(completedGamesApiProvider);
  final storageService = ref.watch(storageServiceProvider);
  return CompletedGamesRepositoryImpl(completedGamesApi, storageService);
});