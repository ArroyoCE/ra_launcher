// lib/screens/achievements/components/games_list.dart

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retroachievements_organizer/constants/constants.dart';
import 'package:retroachievements_organizer/models/user/all_completion_model.dart';
import 'package:retroachievements_organizer/screens/dashboard/utils/completion_color_helper.dart';
import 'package:retroachievements_organizer/screens/dashboard/utils/dashboard_formatter.dart';
import 'package:retroachievements_organizer/services/storage_service.dart';

class GamesList extends ConsumerStatefulWidget {
  final List<dynamic> games;
  final Function(GameProgress) onGameSelected;

  const GamesList({
    super.key,
    required this.games,
    required this.onGameSelected,
  });

  @override
  ConsumerState<GamesList> createState() => _GamesListState();
}

class _GamesListState extends ConsumerState<GamesList> {
  final Map<int, String?> _gameIconPaths = {};

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: widget.games.length,
      itemBuilder: (context, index) {
        final game = widget.games[index];
        return _buildGameCard(game);
      },
    );
  }

  Widget _buildGameCard(GameProgress game) {
    final gameId = game.gameId;
    final title = game.title;
    final iconPath = game.imageIcon;
    final consoleName = game.consoleName;
    final maxPossible = game.maxPossible;
    final numAwarded = game.numAwardedHardcore;
    final percentage = game.getCompletionPercentage();
    final highestAward = game.highestAwardKind;
    final mostRecentDate = game.mostRecentAwardedDate.isNotEmpty 
        ? DateTime.parse(game.mostRecentAwardedDate) 
        : null;
    
    final progressColor = CompletionColorHelper.getCompletionColor(percentage);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: AppColors.cardBackground,
      child: InkWell(
        onTap: () => widget.onGameSelected(game),
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Game icon (smaller size)
                  FutureBuilder<String?>(
                    future: _getGameIcon(gameId, iconPath),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.done && 
                          snapshot.hasData && 
                          snapshot.data != null) {
                        return ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: Image.file(
                            File(snapshot.data!),
                            width: 56,
                            height: 56,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return Container(
                                width: 56,
                                height: 56,
                                color: AppColors.darkBackground,
                                child: const Icon(
                                  Icons.videogame_asset,
                                  color: AppColors.primary,
                                ),
                              );
                            },
                          ),
                        );
                      } else {
                        return Container(
                          width: 56,
                          height: 56,
                          color: AppColors.darkBackground,
                          child: const Icon(
                            Icons.videogame_asset,
                            color: AppColors.primary,
                          ),
                        );
                      }
                    },
                  ),
                  
                  const SizedBox(width: 16),
                  
                  // Game info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            // Game title
                            Expanded(
                              child: Text(
                                title,
                                style: const TextStyle(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.bold,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            
                            // Award indicator (if any)
                            if (highestAward.isNotEmpty) 
                              Padding(
                                padding: const EdgeInsets.only(left: 8),
                                child: _buildAwardBadge(highestAward),
                              ),
                          ],
                        ),
                        
                        const SizedBox(height: 4),
                        
                        // Game metadata row
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            // Achievement count
                            Text(
                              'Achievements $numAwarded of $maxPossible',
                              style: const TextStyle(
                                color: AppColors.textLight,
                                fontSize: 12,
                              ),
                            ),
                            
                            // Console badge
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.darkBackground,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                consoleName,
                                style: const TextStyle(
                                  color: AppColors.textLight,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                        
                        // Last played date
                        if (mostRecentDate != null) 
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              'Last played: ${_formatDate(mostRecentDate)}',
                              style: const TextStyle(
                                color: AppColors.textSubtle,
                                fontSize: 12,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              
              // Progress bar - now in its own row with full width
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Container(
                        height: 16, // Slightly smaller height
                        decoration: BoxDecoration(
                          color: AppColors.darkBackground,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: LinearProgressIndicator(
                            value: percentage / 100,
                            backgroundColor: AppColors.darkBackground,
                            valueColor: AlwaysStoppedAnimation<Color>(progressColor),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Percentage text
                    Text(
                      '${percentage.toStringAsFixed(1)}%',
                      style: TextStyle(
                        color: progressColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  // Create a more visually distinct award badge
  Widget _buildAwardBadge(String awardKind) {
    IconData icon;
    Color color;
    String tooltip;
    
    if (awardKind == 'mastery') {
      icon = Icons.workspace_premium;
      color = Colors.amber;
      tooltip = 'Mastered';
    } else if (awardKind == 'beaten-hardcore') {
      icon = Icons.military_tech;
      color = AppColors.success;
      tooltip = 'Beaten Hardcore';
    } else {
      icon = Icons.emoji_events_outlined;
      color = AppColors.info;
      tooltip = 'Completed';
    }
    
    return Tooltip(
      message: tooltip,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: AppColors.darkBackground,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Icon(
          icon,
          color: color,
          size: 16,
        ),
      ),
    );
  }
  
  Future<String?> _getGameIcon(int gameId, String iconPath) async {
    // Check cache first
    if (_gameIconPaths.containsKey(gameId)) {
      return _gameIconPaths[gameId];
    }
    
    // Otherwise fetch and cache
    final storageService = ref.read(storageServiceProvider);
    
    // Make sure the icon path starts with '/' for API URL consistency
    final normalizedIconPath = iconPath.startsWith('/') ? iconPath : '/$iconPath';
    
    final localPath = await storageService.saveImageFromUrl(
      'https://retroachievements.org$normalizedIconPath',
      'game_images',
      'game_$gameId.png',
    );
    
    if (mounted) {
      setState(() {
        _gameIconPaths[gameId] = localPath;
      });
    }
    
    return localPath;
  }
  
  // Get appropriate award badge icon based on highest award
  
  String _formatDate(DateTime date) {
    return DashboardFormatter.formatDate(date);
  }
}