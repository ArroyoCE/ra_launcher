// lib/providers/repositories/all_consoles_repository_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retroachievements_organizer/api/consoles/all_consoles_api.dart';
import 'package:retroachievements_organizer/repositories/consoles/all_consoles_repository.dart';
import 'package:retroachievements_organizer/repositories/consoles/all_consoles_repository_impl.dart';
import 'package:retroachievements_organizer/services/storage_service.dart';

// Provider for the AllConsolesAPI
final allConsolesApiProvider = Provider<AllConsolesApi>((ref) {
  return AllConsolesApi();
});

// Provider for the AllConsolesRepository
final allConsolesRepositoryProvider = Provider<AllConsolesRepository>((ref) {
  final allConsolesApi = ref.watch(allConsolesApiProvider);
  final storageService = ref.watch(storageServiceProvider);
  return AllConsolesRepositoryImpl(allConsolesApi, storageService);
});