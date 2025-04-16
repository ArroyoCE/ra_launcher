// Updated lib/screens/game_data/components/game_details_tab.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retroachievements_organizer/constants/constants.dart';
import 'package:retroachievements_organizer/models/games/game_extended_model.dart';
import 'package:retroachievements_organizer/providers/states/games/user_game_progress_state_provider.dart';
import 'package:retroachievements_organizer/screens/game_data/widgets/achievement_item.dart';

class GameDetailsTab extends ConsumerWidget {
  final GameExtended? gameExtended;
  final String gameId;

  const GameDetailsTab({
    super.key,
    required this.gameExtended,
    required this.gameId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userGameProgressState = ref.watch(userGameProgressProvider(gameId));
    
    if (userGameProgressState.isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }

    if (userGameProgressState.errorMessage != null) {
      return Center(
        child: Text(
          'Error loading achievements: ${userGameProgressState.errorMessage}',
          style: const TextStyle(
            color: AppColors.textLight,
            fontSize: 16,
          ),
        ),
      );
    }
    
    final userGameProgress = userGameProgressState.data;
    
    if (userGameProgress == null) {
      if (gameExtended == null) {
        return const Center(
          child: Text(
            'No detailed information available for this game.',
            style: TextStyle(
              color: AppColors.textLight,
              fontSize: 16,
            ),
          ),
        );
      }
      
      // Fall back to game extended data if user progress isn't available
      final achievements = gameExtended!.getAchievementsList();
      
      if (achievements.isEmpty) {
        return const Center(
          child: Text(
            'No achievements available for this game.',
            style: TextStyle(
              color: AppColors.textLight,
              fontSize: 16,
            ),
          ),
        );
      }
      
      // Just show the achievements without user progress
      return ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: achievements.length,
        itemBuilder: (context, index) {
          final achievement = achievements[index];
          return AchievementItem(
            achievement: achievement,
            isUnlocked: false,
            numDistinctPlayers: gameExtended?.numDistinctPlayers ?? 0,
          );
        },
      );
    }
    
    // Use user game progress data
    final achievements = userGameProgress.getAchievementsList();
    
    if (achievements.isEmpty) {
      return const Center(
        child: Text(
          'No achievements available for this game.',
          style: TextStyle(
            color: AppColors.textLight,
            fontSize: 16,
          ),
        ),
      );
    }

    // Show achievements with user progress
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: achievements.length,
      itemBuilder: (context, index) {
        final achievement = achievements[index];
        return AchievementItem(
          achievement: achievement,
          isUnlocked: achievement['isUnlocked'] ?? false,
          numDistinctPlayers: userGameProgress.numDistinctPlayers,
        );
      },
    );
  }
}