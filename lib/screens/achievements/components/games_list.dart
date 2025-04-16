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
          child: Row(
            children: [
              // Game icon
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
                        width: 64,
                        height: 64,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          debugPrint('Error loading game icon: $error');
                          return Container(
                            width: 64,
                            height: 64,
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
                      width: 64,
                      height: 64,
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
                    Text(
                      title,
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          'Achievements $numAwarded of $maxPossible',
                          style: const TextStyle(
                            color: AppColors.textLight,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    if (mostRecentDate != null) 
                      Text(
                        'Last played: ${_formatDate(mostRecentDate)}',
                        style: const TextStyle(
                          color: AppColors.textSubtle,
                          fontSize: 12,
                        ),
                      ),
                      
                    // Progress bar
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Container(
                              height: 20,
                              decoration: BoxDecoration(
                                color: AppColors.darkBackground,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: LinearProgressIndicator(
                                  value: percentage / 100,
                                  backgroundColor: AppColors.darkBackground,
                                  valueColor: AlwaysStoppedAnimation<Color>(progressColor),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${percentage.toStringAsFixed(1)}%',
                            style: TextStyle(
                              color: progressColor,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (highestAward.isNotEmpty) 
                            Padding(
                              padding: const EdgeInsets.only(left: 8),
                              child: Icon(
                                _getAwardIcon(highestAward),
                                color: AppColors.primary,
                                size: 20,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              
              // Console badge
              Container(
                padding: const EdgeInsets.all(8),
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
              
              // Right chevron to indicate it's clickable
              const Padding(
                padding: EdgeInsets.only(left: 8),
                child: Icon(Icons.chevron_right, color: AppColors.primary),
              ),
            ],
          ),
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
  IconData _getAwardIcon(String awardKind) {
    if (awardKind == 'mastery') {
      return Icons.workspace_premium;
    } else if (awardKind == 'beaten-hardcore') {
      return Icons.military_tech;
    } else {
      return Icons.emoji_events_outlined;
    }
  }
  
  String _formatDate(DateTime date) {
    return DashboardFormatter.formatDate(date);
  }
}