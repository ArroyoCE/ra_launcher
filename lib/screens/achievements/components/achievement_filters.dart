// lib/screens/achievements/components/achievement_filters.dart

import 'package:flutter/material.dart';
import 'package:retroachievements_organizer/constants/constants.dart';

class AchievementFilters extends StatelessWidget {
  final bool showOnlyCompleted;
  final Set<String> selectedPlatforms;
  final List<dynamic> games;
  final Function({bool? showOnlyCompleted, Set<String>? selectedPlatforms}) onFilterChanged;
  final VoidCallback onClearFilters;

  const AchievementFilters({
    super.key,
    required this.showOnlyCompleted,
    required this.selectedPlatforms,
    required this.games,
    required this.onFilterChanged,
    required this.onClearFilters,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppColors.cardBackground,
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Filters',
              style: TextStyle(
                color: AppColors.primary,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            
            // Show only completed games checkbox
            Row(
              children: [
                Checkbox(
                  value: showOnlyCompleted,
                  onChanged: (value) {
                    onFilterChanged(showOnlyCompleted: value ?? false);
                  },
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
                  'Show only completed games',
                  style: TextStyle(color: AppColors.textLight),
                ),
              ],
            ),
            
            const SizedBox(height: 12),
            const Text(
              'Filter by Platform:',
              style: TextStyle(
                color: AppColors.textLight,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            
            // Platform filter chips
            _buildPlatformFilterChips(),
            
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: onClearFilters,
                  child: const Text(
                    'Clear All Filters',
                    style: TextStyle(color: AppColors.primary),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildPlatformFilterChips() {
    // Get unique console names from results
    Set<String> consoleNames = {};
    for (var game in games) {
      final consoleName = game.consoleName;
      if (consoleName.isNotEmpty) {
        consoleNames.add(consoleName);
      }
    }
    
    // Convert to sorted list
    final platforms = consoleNames.toList()..sort();
    
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: platforms.map((platform) {
        final isSelected = selectedPlatforms.contains(platform);
        return FilterChip(
          label: Text(platform),
          selected: isSelected,
          selectedColor: AppColors.primary.withOpacity(0.3),
          checkmarkColor: AppColors.primary,
          backgroundColor: AppColors.darkBackground,
          labelStyle: TextStyle(
            color: isSelected ? AppColors.primary : AppColors.textLight,
          ),
          onSelected: (selected) {
            final newSelectedPlatforms = Set<String>.from(selectedPlatforms);
            if (selected) {
              newSelectedPlatforms.add(platform);
            } else {
              newSelectedPlatforms.remove(platform);
            }
            onFilterChanged(selectedPlatforms: newSelectedPlatforms);
          },
        );
      }).toList(),
    );
  }
}