// lib/screens/games/components/games_filters.dart

import 'package:flutter/material.dart';
import 'package:retroachievements_organizer/constants/constants.dart';

// Modified enum without last updated options
enum GameSortOption {
  nameAsc,
  nameDesc,
}

class GamesFilters extends StatelessWidget {
  final TextEditingController searchController;
  final Function(String) onSearchChanged;
  final bool showOnlyMatched;
  final Function(bool) onFilterChanged;
  final GameSortOption currentSortOption;
  final Function(GameSortOption) onSortChanged;

  const GamesFilters({
    super.key,
    required this.searchController,
    required this.onSearchChanged,
    required this.showOnlyMatched,
    required this.onFilterChanged,
    required this.currentSortOption,
    required this.onSortChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Search bar
        TextField(
          controller: searchController,
          style: const TextStyle(color: AppColors.textLight),
          decoration: InputDecoration(
            hintText: 'Search games...',
            hintStyle: const TextStyle(color: AppColors.textSubtle),
            prefixIcon: const Icon(Icons.search, color: AppColors.primary),
            suffixIcon: searchController.text.isNotEmpty 
                ? IconButton(
                    icon: const Icon(Icons.clear, color: AppColors.textSubtle),
                    onPressed: () {
                      searchController.clear();
                      onSearchChanged('');
                    },
                  )
                : null,
            filled: true,
            fillColor: AppColors.cardBackground,
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.primary),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.primary, width: 2),
            ),
          ),
          onChanged: onSearchChanged,
        ),
        
        const SizedBox(height: 16),
        
        // Filter option
        Row(
          children: [
            Checkbox(
              value: showOnlyMatched,
              onChanged: (value) => onFilterChanged(value ?? false),
              fillColor: WidgetStateProperty.resolveWith<Color>(
                (Set<WidgetState> states) {
                  if (states.contains(WidgetState.selected)) {
                    return AppColors.primary;
                  }
                  return Colors.grey;
                },
              ),
              checkColor: AppColors.darkBackground,
            ),
            const Text(
              'Show only matched games',
              style: TextStyle(
                color: AppColors.textLight,
                fontSize: 16,
              ),
            ),
            const Spacer(),
            
            // Updated PopupMenuButton for sorting - only alphabetical options
            PopupMenuButton<GameSortOption>(
              icon: const Icon(Icons.sort, color: AppColors.primary),
              tooltip: 'Sort games',
              onSelected: onSortChanged,
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: GameSortOption.nameAsc,
                  child: Text('Name (A-Z)'),
                ),
                const PopupMenuItem(
                  value: GameSortOption.nameDesc,
                  child: Text('Name (Z-A)'),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}