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
    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
    decoration: BoxDecoration(
      color: AppColors.darkBackground.withOpacity(0.5),
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
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        value,
        style: TextStyle(
          color: color,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
      ),
      Text(
        label,
        style: const TextStyle(
          color: AppColors.textLight,
          fontSize: 14,
        ),
      ),
    ],
  );
}
}