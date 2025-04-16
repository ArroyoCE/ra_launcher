// lib/screens/achievements/components/achievement_stats.dart

import 'package:flutter/material.dart';
import 'package:retroachievements_organizer/constants/constants.dart';

class AchievementStats extends StatelessWidget {
  final int gamesPlayed;
  final int totalMastered;
  final int totalBeaten;

  const AchievementStats({
    super.key,
    required this.gamesPlayed,
    required this.totalMastered,
    required this.totalBeaten,
  });

  @override
  Widget build(BuildContext context) {
    // Calculate unfinished games
    final unfinished = gamesPlayed - totalBeaten;

    return Container(
      padding: const EdgeInsets.all(16),
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStatCard('$gamesPlayed', 'Played', Colors.amber),
          _buildStatCard('$unfinished', 'Unfinished', AppColors.info),
          _buildStatCard('$totalBeaten', 'Beaten', AppColors.success),
          _buildStatCard('$totalMastered', 'Mastered', AppColors.primary),
        ],
      ),
    );
  }
  
  Widget _buildStatCard(String value, String label, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            color: AppColors.textLight,
            fontSize: 16,
          ),
        ),
      ],
    );
  }
}