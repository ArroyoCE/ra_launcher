// lib/providers/states/all_completion_state_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retroachievements_organizer/models/user/all_completion_model.dart';
import 'package:retroachievements_organizer/providers/repositories/user/all_completion_repository_provider.dart';
import 'package:retroachievements_organizer/providers/states/auth_state_provider.dart';
import 'package:retroachievements_organizer/repositories/user/all_completion_repository.dart';

class CompletionProgressState {
  final bool isLoading;
  final String? errorMessage;
  final CompletionProgress? data;
  final DateTime? lastUpdated;

  CompletionProgressState({
    this.isLoading = false,
    this.errorMessage,
    this.data,
    this.lastUpdated,
  });

  CompletionProgressState copyWith({
    bool? isLoading,
    String? errorMessage,
    CompletionProgress? data,
    DateTime? lastUpdated,
  }) {
    return CompletionProgressState(
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage ?? this.errorMessage,
      data: data ?? this.data,
      lastUpdated: lastUpdated ?? this.lastUpdated,
    );
  }
}

class CompletionProgressNotifier extends StateNotifier<CompletionProgressState> {
  final AllCompletionRepository allCompletionRepository;
  final String username;
  final String apiKey;

  CompletionProgressNotifier(this.allCompletionRepository, this.username, this.apiKey) 
      : super(CompletionProgressState()) {
    if (username.isNotEmpty && apiKey.isNotEmpty) {
      loadData();
    }
  }

  Future<void> loadData({bool forceRefresh = false}) async {
    if (username.isEmpty || apiKey.isEmpty) {
      state = state.copyWith(
        errorMessage: 'No user credentials available',
        isLoading: false,
      );
      return;
    }

    state = state.copyWith(isLoading: true);

    try {
      final completionProgress = await allCompletionRepository.getUserCompletionProgress(
        username, 
        apiKey, 
        useCache: !forceRefresh
      );

      if (completionProgress != null) {
        state = state.copyWith(
          data: CompletionProgress.fromJson(completionProgress),
          isLoading: false,
          lastUpdated: DateTime.now(),
        );
      } else {
        state = state.copyWith(
          errorMessage: 'Failed to load completion progress',
          isLoading: false,
        );
      }
    } catch (e) {
      state = state.copyWith(
        errorMessage: 'Error loading completion progress: $e',
        isLoading: false,
      );
    }
  }
}

final completionProgressStateProvider = StateNotifierProvider<CompletionProgressNotifier, CompletionProgressState>((ref) {
  final authState = ref.watch(authStateProvider);
  final repository = ref.watch(allCompletionRepositoryProvider);
  
  return CompletionProgressNotifier(
    repository, 
    authState.username ?? '', 
    authState.apiKey ?? ''
  );
});