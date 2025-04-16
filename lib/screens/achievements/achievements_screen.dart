// lib/screens/achievements_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:retroachievements_organizer/constants/constants.dart';
import 'package:retroachievements_organizer/models/user/all_completion_model.dart';
import 'package:retroachievements_organizer/providers/states/user/all_completion_state_provider.dart';
import 'package:retroachievements_organizer/providers/states/user/user_awards_state_provider.dart';
import 'package:retroachievements_organizer/screens/achievements/components/achievement_filters.dart';
import 'package:retroachievements_organizer/screens/achievements/components/achievement_header.dart';
import 'package:retroachievements_organizer/screens/achievements/components/achievement_stats.dart';
import 'package:retroachievements_organizer/screens/achievements/components/games_list.dart';
import 'package:retroachievements_organizer/screens/achievements/utils/achievement_sorter.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AchievementsScreen extends ConsumerStatefulWidget {
  final Widget child;

  const AchievementsScreen({super.key, required this.child});

  @override
  ConsumerState<AchievementsScreen> createState() => _AchievementsScreenState();
}

class _AchievementsScreenState extends ConsumerState<AchievementsScreen> with AutomaticKeepAliveClientMixin {
  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
  
  @override
  bool get wantKeepAlive => true;
}

class AchievementsContent extends ConsumerStatefulWidget {
  const AchievementsContent({super.key});

  @override
  ConsumerState<AchievementsContent> createState() => _AchievementsContentState();
}

class _AchievementsContentState extends ConsumerState<AchievementsContent> with AutomaticKeepAliveClientMixin {
  SortOption _currentSortOption = SortOption.alphabeticalAsc;
  bool _showOnlyCompleted = false;
  Set<String> _selectedPlatforms = {};
  bool _isFilterExpanded = false;
  List<dynamic> _filteredGames = [];
  bool _initialLoadComplete = false; // Add this flag

  @override
  void initState() {
    super.initState();
    _loadSavedPreferences();
    
    // Initial data load
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initialDataLoad();
    });
  }


  Future<void> _initialDataLoad() async {
    setState(() {
      _initialLoadComplete = false; // Ensure loading indicator shows
    });
    
    try {
      // Load both providers in parallel
      await Future.wait([
        ref.read(completionProgressStateProvider.notifier).loadData(),
        ref.read(userAwardsStateProvider.notifier).loadData(),
      ]);
      
      // Apply filters to loaded data
      _applyFiltersAndSort();
      
      if (mounted) {
        setState(() {
          _initialLoadComplete = true;
        });
      }
    } catch (e) {
      debugPrint('Error in initial data load: $e');
      if (mounted) {
        setState(() {
          _initialLoadComplete = true; // Still set to true to hide loading indicator
        });
      }
    }
  }

  // Load saved user preferences
  Future<void> _loadSavedPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Load sort option
      final savedSortOption = prefs.getInt('achievements_sort_option');
      if (savedSortOption != null && savedSortOption < SortOption.values.length) {
        setState(() {
          _currentSortOption = SortOption.values[savedSortOption];
        });
      }
      
      // Load show only completed preference
      final savedShowOnlyCompleted = prefs.getBool('achievements_show_only_completed');
      if (savedShowOnlyCompleted != null) {
        setState(() {
          _showOnlyCompleted = savedShowOnlyCompleted;
        });
      }
      
      // Load selected platforms
      final savedSelectedPlatforms = prefs.getStringList('achievements_selected_platforms');
      if (savedSelectedPlatforms != null) {
        setState(() {
          _selectedPlatforms = savedSelectedPlatforms.toSet();
        });
      }
      
      // Load filter expanded state
      final savedFilterExpanded = prefs.getBool('achievements_filter_expanded');
      if (savedFilterExpanded != null) {
        setState(() {
          _isFilterExpanded = savedFilterExpanded;
        });
      }
    } catch (e) {
      debugPrint('Error loading saved preferences: $e');
    }
  }

  // Save user preferences
  Future<void> _savePreferences() async {
  if (!mounted) return;
  
  try {
    final prefs = await SharedPreferences.getInstance();
    
    // Save sort option
    await prefs.setInt('achievements_sort_option', _currentSortOption.index);
    
    // Save show only completed preference
    await prefs.setBool('achievements_show_only_completed', _showOnlyCompleted);
    
    // Save selected platforms
    await prefs.setStringList('achievements_selected_platforms', _selectedPlatforms.toList());
    
    // Save filter expanded state
    await prefs.setBool('achievements_filter_expanded', _isFilterExpanded);
  } catch (e) {
    debugPrint('Error saving preferences: $e');
  }
}


  // Refresh all data
  Future<void> _refreshData() async {
    setState(() {
      _initialLoadComplete = false; // Show loading during refresh
    });
    
    try {
      await Future.wait([
        ref.read(completionProgressStateProvider.notifier).loadData(forceRefresh: true),
        ref.read(userAwardsStateProvider.notifier).loadData(forceRefresh: true),
      ]);
      
      _applyFiltersAndSort();
      
      if (mounted) {
        setState(() {
          _initialLoadComplete = true;
        });
      }
    } catch (e) {
      debugPrint('Error refreshing data: $e');
      if (mounted) {
        setState(() {
          _initialLoadComplete = true;
        });
      }
    }
  }

  // Toggle filter panel
  void _toggleFilterPanel() {
    setState(() {
      _isFilterExpanded = !_isFilterExpanded;
    });
    _savePreferences();
  }

  // Update sort option

  // Update filter options
  void _updateFilterOptions({
    bool? showOnlyCompleted,
    Set<String>? selectedPlatforms,
  }) {
    setState(() {
      if (showOnlyCompleted != null) {
        _showOnlyCompleted = showOnlyCompleted;
      }
      
      if (selectedPlatforms != null) {
        _selectedPlatforms = selectedPlatforms;
      }
    });
    _applyFiltersAndSort();
  }

  // Clear all filters
  void _clearFilters() {
    setState(() {
      _showOnlyCompleted = false;
      _selectedPlatforms = {};
    });
    _applyFiltersAndSort();
  }

  // Apply filters and sorting
  void _applyFiltersAndSort() {
  if (!mounted) return;
  
  final completionState = ref.read(completionProgressStateProvider);
  
  if (completionState.data == null) {
    setState(() {
      _filteredGames = [];
    });
    return;
  }
  
  try {
    final results = List<dynamic>.from(completionState.data!.results);
    
    // Apply filters
    List<dynamic> filtered = AchievementSorter.applyFilters(
      results,
      showOnlyCompleted: _showOnlyCompleted,
      selectedPlatforms: _selectedPlatforms,
    );
    
    // Apply sorting
    filtered = AchievementSorter.applySorting(filtered, _currentSortOption);
    
    if (mounted) {
      setState(() {
        _filteredGames = filtered;
      });
      
      // Save preferences
      _savePreferences();
    }
  } catch (e) {
    
    if (mounted) {
      setState(() {
        _filteredGames = [];
      });
    }
  }
}

  // Navigate to game details
void _navigateToGameDetails(GameProgress game) {
  final gameId = game.gameId.toString();
  final encodedTitle = Uri.encodeComponent(game.title);
  final encodedIconPath = Uri.encodeComponent(game.imageIcon);
  final encodedConsoleName = Uri.encodeComponent(game.consoleName);
  
  // Use context.go to navigate to the nested route
  context.go('/achievements/game/$gameId?title=$encodedTitle&icon=$encodedIconPath&console=$encodedConsoleName');
}

   @override
  Widget build(BuildContext context) {
    super.build(context);
    
    final completionState = ref.watch(completionProgressStateProvider);
    final userAwardsState = ref.watch(userAwardsStateProvider);
    
    // Show loading indicator during initial load or when providers indicate loading
    final isLoading = !_initialLoadComplete || completionState.isLoading || userAwardsState.isLoading;
        
    return Card(
      color: AppColors.cardBackground,
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header with title and action buttons
                AchievementHeader(
                  onSort: _showSortDialog,
                  onFilter: _toggleFilterPanel,
                  onRefresh: _refreshData,
                  isFilterExpanded: _isFilterExpanded,
                ),
                
                // Filter panel
                if (_isFilterExpanded)
                  AchievementFilters(
                    showOnlyCompleted: _showOnlyCompleted,
                    selectedPlatforms: _selectedPlatforms,
                    games: completionState.data?.results ?? [],
                    onFilterChanged: _updateFilterOptions,
                    onClearFilters: _clearFilters,
                  ),
                
                const SizedBox(height: 16),
                
                // Stats summary
                if (completionState.data != null && userAwardsState.data != null)
                  AchievementStats(
                    gamesPlayed: completionState.data!.count,
                    totalMastered: userAwardsState.data!.masteryAwardsCount,
                    totalBeaten: userAwardsState.data!.beatenHardcoreAwardsCount,
                  ),
                
                const SizedBox(height: 16),
                
                // Game count
                Text(
                  'Viewing ${_filteredGames.length} games',
                  style: const TextStyle(
                    color: AppColors.info,
                    fontSize: 16,
                  ),
                ),
                
                const SizedBox(height: 16),
                
                // Games list
                Expanded(
                  child: _filteredGames.isNotEmpty
                    ? GamesList(
                        games: _filteredGames,
                        onGameSelected: _navigateToGameDetails,
                      )
                    : const Center(
                        child: Text(
                          'No games match your filters',
                          style: TextStyle(color: AppColors.textLight),
                        ),
                      ),
                ),
              ],
            ),
      ),
    );
  }
  
 void _showSortDialog() {
  if (!mounted) return;
  
  showDialog(
    context: context,
    builder: (BuildContext dialogContext) {
      return AlertDialog(
        backgroundColor: AppColors.cardBackground,
        title: const Text(
          'Sort Games By',
          style: TextStyle(color: AppColors.primary),
        ),
        content: StatefulBuilder(
          builder: (BuildContext context, StateSetter setDialogState) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildSortOption(SortOption.completionAsc, 'Completion Rate (Low to High)', dialogContext, setDialogState),
                _buildSortOption(SortOption.completionDesc, 'Completion Rate (High to Low)', dialogContext, setDialogState),
                _buildSortOption(SortOption.alphabeticalAsc, 'Game Title (A to Z)', dialogContext, setDialogState),
                _buildSortOption(SortOption.alphabeticalDesc, 'Game Title (Z to A)', dialogContext, setDialogState),
                _buildSortOption(SortOption.platformAsc, 'Platform (A to Z)', dialogContext, setDialogState),
                _buildSortOption(SortOption.platformDesc, 'Platform (Z to A)', dialogContext, setDialogState),
              ],
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text(
              'Close',
              style: TextStyle(color: AppColors.primary),
            ),
          ),
        ],
      );
    },
  );
}


Widget _buildSortOption(SortOption option, String label, BuildContext dialogContext, StateSetter setDialogState) {
  return RadioListTile<SortOption>(
    title: Text(
      label,
      style: const TextStyle(color: AppColors.textLight),
    ),
    value: option,
    groupValue: _currentSortOption,
    activeColor: AppColors.primary,
    onChanged: (SortOption? value) {
      if (value != null) {
        // Update both the dialog state and the parent widget state
        setDialogState(() {
          _currentSortOption = value;
        });
        
        // Update the parent state too
        setState(() {
          _currentSortOption = value;
        });
        
        // Apply filters and sort
        _applyFiltersAndSort();
        
        // Close the dialog
        Navigator.of(dialogContext).pop();
      }
    },
  );
}

  @override
  bool get wantKeepAlive => true;
}