// lib/screens/consoles/components/consoles_header.dart

import 'package:flutter/material.dart';
import 'package:retroachievements_organizer/constants/constants.dart';

class ConsolesHeader extends StatelessWidget {
  final VoidCallback onViewToggle;
  final VoidCallback onRefresh;
  final bool isGridView;

  const ConsolesHeader({
    super.key,
    required this.onViewToggle,
    required this.onRefresh,
    required this.isGridView,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text(
          AppStrings.myGames,
          style: TextStyle(
            color: AppColors.textLight,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        Row(
          children: [
            // View toggle button
            IconButton(
              icon: Icon(
                isGridView ? Icons.view_list : Icons.grid_view,
                color: AppColors.primary,
              ),
              onPressed: onViewToggle,
              tooltip: isGridView ? 'Switch to list view' : 'Switch to grid view',
            ),
            // Refresh button
            IconButton(
              icon: const Icon(Icons.refresh, color: AppColors.primary),
              onPressed: onRefresh,
              tooltip: 'Refresh consoles',
            ),
          ],
        ),
      ],
    );
  }
}