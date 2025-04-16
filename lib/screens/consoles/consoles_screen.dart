// lib/screens/consoles/consoles_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retroachievements_organizer/constants/constants.dart';
import 'package:retroachievements_organizer/models/consoles/all_console_model.dart';
import 'package:retroachievements_organizer/models/local/hash_model.dart';
import 'package:retroachievements_organizer/providers/repositories/local_data_repository_provider.dart';
import 'package:retroachievements_organizer/providers/states/consoles/all_consoles_state_provider.dart';
import 'package:retroachievements_organizer/providers/states/consoles/all_games_hashes_state_provider.dart';
import 'package:retroachievements_organizer/providers/states/local_data_state_provider.dart';
import 'package:retroachievements_organizer/screens/consoles/components/consoles_filters.dart';
import 'package:retroachievements_organizer/screens/consoles/components/consoles_grid.dart';
import 'package:retroachievements_organizer/screens/consoles/components/consoles_header.dart';
import 'package:retroachievements_organizer/screens/consoles/components/consoles_list.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ConsolesScreen extends StatefulWidget {
  final Widget child;

  const ConsolesScreen({super.key, required this.child});

  @override
  State<ConsolesScreen> createState() => _ConsolesScreenState();
}

class _ConsolesScreenState extends State<ConsolesScreen> with AutomaticKeepAliveClientMixin {
  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
  
  @override
  bool get wantKeepAlive => true;
}

class GamesContent extends ConsumerStatefulWidget {
  const GamesContent({super.key});

  @override
  ConsumerState<GamesContent> createState() => _GamesContentState();
}

class _GamesContentState extends ConsumerState<GamesContent> with AutomaticKeepAliveClientMixin {
  bool _isGridView = true;
  final Map<int, Map<String, dynamic>> _libraryStats = {};
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  bool _showOnlyAvailable = true;



  


  @override
void initState() {
  super.initState();
  _loadSavedPreferences();
  
  // Load consoles and game data
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    await ref.read(consolesStateProvider.notifier).loadData();
    
    // Add this line to load the totals for all consoles
    await _loadConsoleStats();
    
    // Then preload game data
    _preloadGameData();
  });
}

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadSavedPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Load view preference
      final savedIsGridView = prefs.getBool('consoles_grid_view');
      if (savedIsGridView != null) {
        setState(() {
          _isGridView = savedIsGridView;
        });
      }
      
      // Load filter preference
      final savedShowOnlyAvailable = prefs.getBool('consoles_show_only_available');
      if (savedShowOnlyAvailable != null) {
        setState(() {
          _showOnlyAvailable = savedShowOnlyAvailable;
        });
      }
    } catch (e) {
      debugPrint('Error loading saved preferences: $e');
    }
  }

  Future<void> _loadConsoleStats() async {
  try {
    // Get supported console IDs
    final supportedConsoleIds = ref.read(supportedConsoleIdsProvider);
    
    // Get local data repository
    final localDataRepository = ref.read(localDataRepositoryProvider);
    
    // Load totals for each console from JSON storage
    for (final consoleId in supportedConsoleIds) {
      // Get cached console totals
      final cachedTotals = await localDataRepository.getConsoleTotals(consoleId);
      
      if (cachedTotals != null) {
        // Get hash stats
        final hashStats = await localDataRepository.getHashStats(consoleId);
        
        // Create updated stats with loaded totals
        final stats = {
          'matchedGames': hashStats?['matchedGames'] ?? 0,
          'matchedHashes': hashStats?['matchedHashes'] ?? 0,
          'totalGames': cachedTotals['totalGames'] ?? 0,
          'totalHashes': cachedTotals['totalHashes'] ?? 0,
          'hashMethod': ref.read(consoleHashMethodProvider(consoleId)).name,
          'lastUpdated': DateTime.now().toIso8601String(),
        };
        
        // Update the stats provider
        ref.read(consoleStatsNotifierProvider.notifier).updateConsoleStats(consoleId, stats);
        
        // Update local state
        if (mounted) {
          setState(() {
            _libraryStats[consoleId] = Map.from(stats);
          });
        }
      }
    }
  } catch (e) {
    debugPrint('Error loading console stats: $e');
  }
}


  Future<void> _saveViewPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('consoles_grid_view', _isGridView);
    } catch (e) {
      debugPrint('Error saving view preference: $e');
    }
  }

  Future<void> _saveFilterPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('consoles_show_only_available', _showOnlyAvailable);
    } catch (e) {
      debugPrint('Error saving filter preference: $e');
    }
  }

  void _toggleView() {
    setState(() {
      _isGridView = !_isGridView;
    });
    _saveViewPreference();
  }

  void _toggleAvailableFilter(bool value) {
    setState(() {
      _showOnlyAvailable = value;
    });
    _saveFilterPreference();
  }

  // Preload game data for all consoles
 Future<void> _preloadGameData() async {
  if (!mounted) return;
  
  final consoleState = ref.read(consolesStateProvider);
  if (consoleState.data == null) {
    debugPrint('Consoles not loaded yet, skipping preload');
    return;
  }
  
  // Get supported console IDs
  final supportedConsoleIds = ref.read(supportedConsoleIdsProvider);
  
  // Process each console
  const batchSize = 5;
  for (int i = 0; i < supportedConsoleIds.length; i += batchSize) {
    final end = (i + batchSize < supportedConsoleIds.length) ? i + batchSize : supportedConsoleIds.length;
    final batch = supportedConsoleIds.sublist(i, end);
    
    // Process batch in parallel
    await Future.wait(
      batch.map((consoleId) async {
        try {
          // Get local data repository
          final localDataRepository = ref.read(localDataRepositoryProvider);
          
          // Check if we have cached totals
          final cachedTotals = await localDataRepository.getConsoleTotals(consoleId);
          int totalGames = 0;
          int totalHashes = 0;
          
          // If we don't have cached totals, or they're outdated, fetch from API
          if (cachedTotals == null) {
            // Load game list to get total counts
            await ref.read(gamesHashesStateProvider.notifier).loadGameList(consoleId.toString());
            final gamesState = ref.read(gamesHashesStateProvider);
            
            if (gamesState.data != null) {
              totalGames = gamesState.data!.length;
              totalHashes = gamesState.data!.fold<int>(
                0, (sum, game) => sum + game.hashes.length
              );
              
              // Save the totals for future use
              await localDataRepository.saveConsoleTotals(consoleId, totalGames, totalHashes);
            }
          } else {
            // Use cached totals
            totalGames = cachedTotals['totalGames'] ?? 0;
            totalHashes = cachedTotals['totalHashes'] ?? 0;
          }
          
          // Get hash stats
          final hashStats = await localDataRepository.getHashStats(consoleId);
          
          // Create stats with proper totals
          final stats = {
            'matchedGames': hashStats?['matchedGames'] ?? 0,
            'matchedHashes': hashStats?['matchedHashes'] ?? 0,
            'totalGames': totalGames,
            'totalHashes': totalHashes,
            'hashMethod': ref.read(consoleHashMethodProvider(consoleId)).name,
            'lastUpdated': DateTime.now().toIso8601String(),
          };
          
          // Update the stats
          ref.read(consoleStatsNotifierProvider.notifier).updateConsoleStats(consoleId, stats);
          
          // Update local state
          if (mounted) {
            setState(() {
              _libraryStats[consoleId] = Map.from(stats);
            });
          }
        } catch (e) {
          debugPrint('Error loading stats for console $consoleId: $e');
        }
      })
    );
    
    // Small delay between batches
    if (end < supportedConsoleIds.length) {
      await Future.delayed(const Duration(milliseconds: 200));
    }
  }
}



void _refreshData() async {
  // First refresh console data from API
  await ref.read(consolesStateProvider.notifier).loadData(forceRefresh: true);
  
  // Get supported console IDs
  final supportedConsoleIds = ref.read(supportedConsoleIdsProvider);
  
  // Process each console to refresh totals
  for (final consoleId in supportedConsoleIds) {
    try {
      // Get local data repository
      final localDataRepository = ref.read(localDataRepositoryProvider);
      
      // Load game list to get fresh total counts
      await ref.read(gamesHashesStateProvider.notifier).loadGameList(consoleId.toString(), forceRefresh: true);
      final gamesState = ref.read(gamesHashesStateProvider);
      
      if (gamesState.data != null) {
        final totalGames = gamesState.data!.length;
        final totalHashes = gamesState.data!.fold<int>(
          0, (sum, game) => sum + game.hashes.length
        );
        
        // Save the updated totals
        await localDataRepository.saveConsoleTotals(consoleId, totalGames, totalHashes);
        
        // Get hash stats
        final hashStats = await localDataRepository.getHashStats(consoleId);
        
        // Create updated stats with proper totals
        final stats = {
          'matchedGames': hashStats?['matchedGames'] ?? 0,
          'matchedHashes': hashStats?['matchedHashes'] ?? 0,
          'totalGames': totalGames,
          'totalHashes': totalHashes,
          'hashMethod': ref.read(consoleHashMethodProvider(consoleId)).name,
          'lastUpdated': DateTime.now().toIso8601String(),
        };
        
        // Update the stats
        ref.read(consoleStatsNotifierProvider.notifier).updateConsoleStats(consoleId, stats);
        
        // Update local state
        if (mounted) {
          setState(() {
            _libraryStats[consoleId] = Map.from(stats);
          });
        }
      }
    } catch (e) {
      debugPrint('Error refreshing stats for console $consoleId: $e');
    }
  }
  
  // Refresh all stats from storage
  await ref.read(consoleStatsNotifierProvider.notifier).refreshAllStats();
}

  // Filter consoles based on search and availability
  List<Console> _getFilteredConsoles() {
    final consoleState = ref.read(consolesStateProvider);
    if (consoleState.data == null) return [];
    
    // First filter by supported consoles if needed
    List<Console> filteredList = consoleState.data!;
    
    if (_showOnlyAvailable) {
      final supportedIds = ref.read(supportedConsoleIdsProvider);
      filteredList = filteredList.where((console) => 
        supportedIds.contains(console.id)).toList();
    }
    
    // Then filter by search query
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      filteredList = filteredList.where((console) => 
        console.name.toLowerCase().contains(query)).toList();
    }
    
    return filteredList;
  }

@override
Widget build(BuildContext context) {
  super.build(context);

  // Explicitly watch the stats provider to get updates
  final statsCache = ref.watch(consoleStatsProvider);
  
  // If there are updated stats, copy them to our local state
  if (statsCache.isNotEmpty && mounted) {
    for (final entry in statsCache.entries) {
      if (!_libraryStats.containsKey(entry.key) || 
          _libraryStats[entry.key]!['lastUpdated'] != entry.value['lastUpdated']) {
        _libraryStats[entry.key] = Map.from(entry.value);
      }
    }
  }
  
  final consoleState = ref.watch(consolesStateProvider);
  final filteredConsoles = _getFilteredConsoles();
    
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with title and actions
          ConsolesHeader(
            onViewToggle: _toggleView,
            onRefresh: _refreshData,
            isGridView: _isGridView,
          ),
          
          const SizedBox(height: 16),
          
          // Search and filters
          ConsolesFilters(
            searchController: _searchController,
            onSearchChanged: (value) {
              setState(() {
                _searchQuery = value;
              });
            },
            showOnlyAvailable: _showOnlyAvailable,
            onFilterChanged: _toggleAvailableFilter,
          ),
          
          const SizedBox(height: 16),
          
          // Console count
          Text(
            'Showing ${filteredConsoles.length} consoles',
            style: const TextStyle(
              color: AppColors.info,
              fontSize: 14,
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Loading indicator or consoles grid/list
          consoleState.isLoading
              ? const Expanded(
                  child: Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  ),
                )
              : consoleState.data == null || consoleState.data!.isEmpty
                  ? const Expanded(
                      child: Center(
                        child: Text(
                          'No consoles found',
                          style: TextStyle(
                            color: AppColors.textLight,
                            fontSize: 18,
                          ),
                        ),
                      ),
                    )
                  : Expanded(
                      child: _isGridView
                          ? ConsolesGrid(
                              consoles: filteredConsoles,
                              libraryStats: _libraryStats,
                            )
                          : ConsolesList(
                              consoles: filteredConsoles,
                              libraryStats: _libraryStats,
                            ),
                    ),
        ],
      ),
    );
  }
  
  @override
  bool get wantKeepAlive => true;
}