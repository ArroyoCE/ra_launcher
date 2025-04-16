// lib/screens/games/components/games_grid.dart

import 'package:flutter/material.dart';
import 'package:retroachievements_organizer/models/consoles/all_game_hash.dart';
import 'package:retroachievements_organizer/models/local/hash_match_model.dart';
import 'package:retroachievements_organizer/screens/games/widgets/game_grid_item.dart';

class GamesGrid extends StatelessWidget {
  final List<GameHash> games;
  final Function(GameHash) onGameSelected;
  final Map<int, MatchStatus>? matchStatuses;
  final bool isHashingInProgress;

  const GamesGrid({
    super.key,
    required this.games,
    required this.onGameSelected,
    this.matchStatuses,
    this.isHashingInProgress = false,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 8,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: 0.7,
      ),
      itemCount: games.length,
      itemBuilder: (context, index) {
        final game = games[index];
        
        // Get match status for this game if available
        final matchStatus = matchStatuses != null ? matchStatuses![game.id] : null;
        
        return GameGridItem(
          game: game,
          onTap: () => onGameSelected(game),
          matchStatus: matchStatus,
          isHashingInProgress: isHashingInProgress,
        );
      },
    );
  }
}