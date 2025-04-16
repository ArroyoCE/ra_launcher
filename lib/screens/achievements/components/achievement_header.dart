// lib/screens/achievements/components/achievement_header.dart

import 'package:flutter/material.dart';
import 'package:retroachievements_organizer/constants/constants.dart';

class AchievementHeader extends StatelessWidget {
  final VoidCallback onSort;
  final VoidCallback onFilter;
  final VoidCallback onRefresh;
  final bool isFilterExpanded;

  const AchievementHeader({
    super.key,
    required this.onSort,
    required this.onFilter,
    required this.onRefresh,
    required this.isFilterExpanded,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text(
          'My Achievements',
          style: TextStyle(
            color: AppColors.textLight,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        Row(
          children: [
            // Sort button
            IconButton(
              icon: const Icon(Icons.sort, color: AppColors.primary),
              onPressed: onSort,
              tooltip: 'Sort games',
            ),
            // Filter button
            IconButton(
              icon: Icon(
                isFilterExpanded ? Icons.filter_list_off : Icons.filter_list,
                color: AppColors.primary,
              ),
              onPressed: onFilter,
              tooltip: 'Filter games',
            ),
            // Refresh button
            IconButton(
              icon: const Icon(Icons.refresh, color: AppColors.primary),
              onPressed: onRefresh,
              tooltip: 'Refresh achievements data',
            ),
          ],
        ),
      ],
    );
  }
}