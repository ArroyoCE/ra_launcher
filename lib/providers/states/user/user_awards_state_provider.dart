import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retroachievements_organizer/models/user/user_awards_model.dart';
import 'package:retroachievements_organizer/providers/repositories/user/user_awards_repository_provider.dart';
import 'package:retroachievements_organizer/providers/states/auth_state_provider.dart';
import 'package:retroachievements_organizer/repositories/user/user_awards_repository.dart';

class UserAwardsState {
  final bool isLoading;
  final String? errorMessage;
  final UserAwards? data;
  final DateTime? lastUpdated;

  UserAwardsState({
    this.isLoading = false,
    this.errorMessage,
    this.data,
    this.lastUpdated,
  });

  UserAwardsState copyWith({
    bool? isLoading,
    String? errorMessage,
    UserAwards? data,
    DateTime? lastUpdated,
  }) {
    return UserAwardsState(
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage ?? this.errorMessage,
      data: data ?? this.data,
      lastUpdated: lastUpdated ?? this.lastUpdated,
    );
  }
}

class UserAwardsNotifier extends StateNotifier<UserAwardsState> {
  final UserAwardsRepository userAwardsRepository;
  final String username;
  final String apiKey;

  UserAwardsNotifier(this.userAwardsRepository, this.username, this.apiKey) 
      : super(UserAwardsState()) {
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
      final userAwards = await userAwardsRepository.getUserAwards(
        username, 
        apiKey, 
        useCache: !forceRefresh
      );

      if (userAwards != null) {
        state = state.copyWith(
          data: userAwards,
          isLoading: false,
          lastUpdated: DateTime.now(),
        );
      } else {
        state = state.copyWith(
          errorMessage: 'Failed to load user awards',
          isLoading: false,
        );
      }
    } catch (e) {
      state = state.copyWith(
        errorMessage: 'Error loading user awards: $e',
        isLoading: false,
      );
    }
  }
}

final userAwardsStateProvider = StateNotifierProvider<UserAwardsNotifier, UserAwardsState>((ref) {
  final authState = ref.watch(authStateProvider);
  final repository = ref.watch(userAwardsRepositoryProvider);
  
  return UserAwardsNotifier(
    repository, 
    authState.username ?? '', 
    authState.apiKey ?? ''
  );
});