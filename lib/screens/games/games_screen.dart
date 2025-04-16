// lib/screens/games/games_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:retroachievements_organizer/constants/constants.dart';
import 'package:retroachievements_organizer/models/consoles/all_game_hash.dart';
import 'package:retroachievements_organizer/models/local/hash_match_model.dart';
import 'package:retroachievements_organizer/providers/repositories/local_data_repository_provider.dart';
import 'package:retroachievements_organizer/providers/states/consoles/all_games_hashes_state_provider.dart';
import 'package:retroachievements_organizer/providers/states/local_data_state_provider.dart';
import 'package:retroachievements_organizer/screens/games/components/games_filters.dart';
import 'package:retroachievements_organizer/screens/games/components/games_grid.dart';
import 'package:retroachievements_organizer/screens/games/components/games_header.dart';
import 'package:retroachievements_organizer/screens/games/components/games_list.dart';
import 'package:retroachievements_organizer/screens/games/dialogs/folder_management_dialog.dart';
import 'package:retroachievements_organizer/screens/games/widgets/folders_display.dart';
import 'package:shared_preferences/shared_preferences.dart';





class GamesScreen extends ConsumerStatefulWidget {
  final int consoleId;
  final String consoleName;

  const GamesScreen({
    super.key,
    required this.consoleId,
    required this.consoleName,
  });

  @override
  ConsumerState<GamesScreen> createState() => _GamesScreenState();
}

class _GamesScreenState extends ConsumerState<GamesScreen> with AutomaticKeepAliveClientMixin {
  bool _isGridView = true;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  bool _showOnlyMatched = false;
  bool _isLoading = true;
  bool _isHashingInProgress = false;
  List<String> _consoleFolders = [];
  Map<String, String> _localHashes = {};
  Map<int, MatchStatus> _matchStatuses = {};
  GameSortOption _currentSortOption = GameSortOption.nameAsc;
  


  @override
  void initState() {
    super.initState();
    _loadSavedPreferences();
    
    // Load games data
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _loadFolders();
      await _loadGamesData();
      await _loadLocalHashes();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _handleSortChange(GameSortOption option) {
  setState(() {
    _currentSortOption = option;
  });
}

  Future<void> _loadSavedPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Load view preference
      final savedIsGridView = prefs.getBool('games_grid_view');
      if (savedIsGridView != null) {
        setState(() {
          _isGridView = savedIsGridView;
        });
      }
      
      // Load filter preference
      final savedShowOnlyMatched = prefs.getBool('games_show_only_matched');
      if (savedShowOnlyMatched != null) {
        setState(() {
          _showOnlyMatched = savedShowOnlyMatched;
        });
      }
    } catch (e) {
      debugPrint('Error loading saved preferences: $e');
    }
  }

  Future<void> _saveViewPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('games_grid_view', _isGridView);
    } catch (e) {
      debugPrint('Error saving view preference: $e');
    }
  }

  Future<void> _saveFilterPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('games_show_only_matched', _showOnlyMatched);
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

  void _toggleMatchedFilter(bool value) {
    setState(() {
      _showOnlyMatched = value;
    });
    _saveFilterPreference();
  }

  Future<void> _loadFolders() async {
    try {
      final localDataRepository = ref.read(localDataRepositoryProvider);
      final consoleFolders = await localDataRepository.getConsoleFolders();
      
      setState(() {
        _consoleFolders = consoleFolders[widget.consoleId] ?? [];
      });
    } catch (e) {
      debugPrint('Error loading console folders: $e');
    }
  }

  Future<void> _loadLocalHashes() async {
    try {
      final localDataRepository = ref.read(localDataRepositoryProvider);
      final hashes = await localDataRepository.getLocalHashes(widget.consoleId);
      
      if (mounted) {
        setState(() {
          _localHashes = hashes;
        });
        
        _matchGamesWithLocalHashes();
      }
    } catch (e) {
      debugPrint('Error loading local hashes: $e');
    }
  }

  void _matchGamesWithLocalHashes() {
  final gamesState = ref.read(gamesHashesStateProvider);
  
  if (gamesState.data == null || gamesState.data!.isEmpty) {
    return;
  }
  
  final Map<int, MatchStatus> statuses = {};
  
  // Track statistics for saving
  int matchedGamesCount = 0;
  int matchedHashesCount = 0;
  final Set<String> uniqueMatchedHashes = <String>{};
  
  // If there are no local hashes, set all games to "No Match"
  if (_localHashes.isEmpty) {
    for (final game in gamesState.data!) {
      statuses[game.id] = MatchStatus.noMatch;
    }
    
    if (mounted) {
      setState(() {
        _matchStatuses = statuses;
      });
      
      // Save stats with zeros
      _saveHashStats(0, 0);
    }
    return;
  }
  
  // Process each game and determine match status
  for (final game in gamesState.data!) {
    if (game.hashes.isEmpty) {
      statuses[game.id] = MatchStatus.noMatch;
      continue;
    }
    
    final apiHashes = game.hashes.map((hash) => hash.toLowerCase()).toList();
    
    // Count matches
    int matchCount = 0;
    for (final apiHash in apiHashes) {
      if (_localHashes.values.contains(apiHash)) {
        matchCount++;
        uniqueMatchedHashes.add(apiHash);
      }
    }
    
    // Determine status
    if (matchCount == 0) {
      statuses[game.id] = MatchStatus.noMatch;
    } else if (matchCount == apiHashes.length) {
      statuses[game.id] = MatchStatus.fullMatch;
      matchedGamesCount++;
    } else {
      statuses[game.id] = MatchStatus.partialMatch;
      matchedGamesCount++; // Count partial matches too
    }
  }
  
  if (mounted) {
    setState(() {
      _matchStatuses = statuses;
    });
    
    // Save hash stats
    matchedHashesCount = uniqueMatchedHashes.length;
    _saveHashStats(matchedGamesCount, matchedHashesCount);
  }
}


Future<void> _saveHashStats(int matchedGames, int matchedHashes) async {
  try {
    final localDataRepository = ref.read(localDataRepositoryProvider);
    await localDataRepository.saveHashStats(
      widget.consoleId,
      matchedGames,
      matchedHashes
    );
    
    // Get hash method
    final hashMethod = ref.read(consoleHashMethodProvider(widget.consoleId));
    
    // Get games count from current state
    final gamesState = ref.read(gamesHashesStateProvider);
    final totalGames = gamesState.data?.length ?? 0;
    final totalHashes = gamesState.data != null 
        ? gamesState.data!.fold<int>(0, (sum, game) => sum + game.hashes.length) 
        : 0;
    
    // Create updated stats map
    final updatedStats = {
      'totalGames': totalGames,
      'totalHashes': totalHashes,
      'matchedGames': matchedGames,
      'matchedHashes': matchedHashes,
      'hashMethod': hashMethod.name,
      'lastUpdated': DateTime.now().toIso8601String(), // Make sure timestamp is included
    };
    
    // Update the stats directly through the notifier
    ref.read(consoleStatsNotifierProvider.notifier).updateConsoleStats(widget.consoleId, updatedStats);
    
    // Force refresh on the notifier to ensure all listeners are updated
    ref.invalidate(consoleStatsProvider);
  } catch (e) {
    debugPrint('Error saving hash stats: $e');
  }
}


  Future<void> _loadGamesData() async {
  setState(() {
    _isLoading = true;
  });

  try {
    await ref.read(gamesHashesStateProvider.notifier).loadGameList(
      widget.consoleId.toString(),
      forceRefresh: false,
    );
  } catch (e) {
    debugPrint('Error loading games data: $e');
  } finally {
    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }
}
  void _refreshData() async {
  // If no folders are added, just refresh game data
  if (_consoleFolders.isEmpty) {
    setState(() {
      _isLoading = true;
    });

    try {
      await ref.read(gamesHashesStateProvider.notifier).loadGameList(
        widget.consoleId.toString(),
        forceRefresh: true,
      );
      
  
      
    
      
      // Update match statuses
      _matchGamesWithLocalHashes();
    } catch (e) {
      debugPrint('Error refreshing games data: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  } else {
    // If folders are added, ask user if they want to rehash
    final shouldRehash = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.cardBackground,
        title: const Text(
          'Refresh Game Data',
          style: TextStyle(color: AppColors.primary),
        ),
        content: const Text(
          'Do you want to rehash all files in your folders? This may take some time.',
          style: TextStyle(color: AppColors.textLight),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: AppColors.textLight),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.textDark,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Yes, Rehash'),
          ),
        ],
      ),
    ) ?? false;

    if (shouldRehash) {
      setState(() {
        _isLoading = true;
        _isHashingInProgress = true;
      });

      try {
        // First refresh games data
        await ref.read(gamesHashesStateProvider.notifier).loadGameList(
          widget.consoleId.toString(),
          forceRefresh: true,
        );

        // Show hashing in progress notification
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Hashing files... This may take a while.'),
              duration: Duration(seconds: 5),
            ),
          );
        }

        // Get local data repository
        final localDataRepository = ref.read(localDataRepositoryProvider);
        
        // Rehash all files in folders
        final hashes = await localDataRepository.hashFilesInFolders(
          widget.consoleId, 
          _consoleFolders
        );

        if (mounted) {
          setState(() {
            _localHashes = hashes;
            _isHashingInProgress = false;
            _isLoading = false;
          });
          
          // Match newly hashed files with games
          _matchGamesWithLocalHashes();
          
          // Show success notification
          if (context.mounted){
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${hashes.length} files hashed successfully'),
              backgroundColor: AppColors.success,
            ),
          );
          }
        }
      } catch (e) {
        debugPrint('Error during refresh and rehash: $e');
        if (mounted) {
          setState(() {
            _isHashingInProgress = false;
            _isLoading = false;
          });
          if (context.mounted){
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error refreshing data: $e'),
              backgroundColor: AppColors.error,
            ),
          );
          }
        }
      }
    }
  }
}

  void _onAddFolder() async {
  try {
    final localDataRepository = ref.read(localDataRepositoryProvider);
    
    // Get existing folders for this console
    final consoleFolders = await localDataRepository.getConsoleFolders();
    final existingFolders = consoleFolders[widget.consoleId] ?? [];
    
    // Get hash method for this console
    final hashMethod = localDataRepository.getHashMethodForConsole(widget.consoleId);
    
    if (mounted) {
      showDialog(
        context: context,
        builder: (context) => FolderManagementDialog(
          consoleId: widget.consoleId,
          consoleName: widget.consoleName,
          initialFolders: existingFolders,
          hashMethod: hashMethod,
          onSave: (updatedFolders) async {
            setState(() {
              _isHashingInProgress = true;
              _consoleFolders = updatedFolders;
              // Clear match statuses when folder list changes
              _matchStatuses = {};
            });
            
            // Show hashing in progress notification
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Updating folder configuration...'),
                  duration: Duration(seconds: 3),
                ),
              );
            }
            
            // Save updated folders - this will also clean up hashes for removed folders
            await localDataRepository.saveConsoleFolders(widget.consoleId, updatedFolders);
            
            // If folders were removed, we need to update the local hashes
            if (existingFolders.length > updatedFolders.length) {
              // Reload local hashes which were updated by cleanHashesForRemovedFolders
              final updatedLocalHashes = await localDataRepository.getLocalHashes(widget.consoleId);
              setState(() {
                _localHashes = updatedLocalHashes;
              });
              
              // Get the updated hash stats
              final hashStats = await localDataRepository.getHashStats(widget.consoleId);
              if (hashStats != null) {
                // Get hash method
                final hashMethod = ref.read(consoleHashMethodProvider(widget.consoleId));
                
                // Create updated stats map
                final updatedStats = {
                  'totalGames': hashStats['totalGames'] ?? 0,
                  'totalHashes': hashStats['totalHashes'] ?? 0,
                  'matchedGames': hashStats['matchedGames'] ?? 0,
                  'matchedHashes': hashStats['matchedHashes'] ?? 0,
                  'hashMethod': hashMethod.name,
                  'lastUpdated': DateTime.now().toIso8601String(),
                };
                
                // Update the stats provider
                ref.read(consoleStatsNotifierProvider.notifier).updateConsoleStats(widget.consoleId, updatedStats);
                
                // Force refresh provider
                ref.invalidate(consoleStatsProvider);
                
                // Re-match games with updated hashes
                _matchGamesWithLocalHashes();
              }
            }
            
            // Hash files in folders if there are any
            if (updatedFolders.isNotEmpty) {
              try {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Hashing files... This may take a while.'),
                      duration: Duration(seconds: 5),
                    ),
                  );
                }
                
                final hashes = await localDataRepository.hashFilesInFolders(
                  widget.consoleId, 
                  updatedFolders
                );
                
                if (mounted) {
                  setState(() {
                    _localHashes = hashes;
                    _isHashingInProgress = false;
                  });
                  
                  // Match newly hashed files with games
                  _matchGamesWithLocalHashes();
                  
                  // Show success notification
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('${hashes.length} files hashed successfully'),
                        backgroundColor: AppColors.success,
                      ),
                    );
                  }
                }
              } catch (e) {
                if (mounted) {
                  setState(() {
                    _isHashingInProgress = false;
                  });
                  
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Error hashing files: $e'),
                        backgroundColor: AppColors.error,
                      ),
                    );
                  }
                }
              }
            } else {
              // If no folders, clear all hashes
              await localDataRepository.saveLocalHashes(widget.consoleId, {});
              
              if (mounted) {
                // Explicitly update match statuses for ALL games to NoMatch
                final gamesState = ref.read(gamesHashesStateProvider);
                Map<int, MatchStatus> updatedStatuses = {};
                
                if (gamesState.data != null) {
                  for (final game in gamesState.data!) {
                    updatedStatuses[game.id] = MatchStatus.noMatch;
                  }
                }
                
                setState(() {
                  _localHashes = {};
                  _isHashingInProgress = false;
                  _matchStatuses = updatedStatuses; // Direct assignment of new map
                });
                
                // Update hash stats to zero
                final updatedStats = {
                  'totalGames': gamesState.data?.length ?? 0,
                  'totalHashes': gamesState.data != null 
                      ? gamesState.data!.fold<int>(0, (sum, game) => sum + game.hashes.length) 
                      : 0,
                  'matchedGames': 0,
                  'matchedHashes': 0,
                  'hashMethod': hashMethod.name,
                  'lastUpdated': DateTime.now().toIso8601String(),
                };
                
                // Update the stats provider
                ref.read(consoleStatsNotifierProvider.notifier).updateConsoleStats(widget.consoleId, updatedStats);
                
                // Force refresh provider
                ref.invalidate(consoleStatsProvider);
                
                // Show info notification
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('All folders removed, hashes cleared'),
                      backgroundColor: AppColors.info,
                    ),
                  );
                }
              }
            }
          },
        ),
      );
    }
  } catch (e) {
    debugPrint('Error opening folder management dialog: $e');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error opening folder management dialog: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }
}



void _sortGames(List<GameHash> games) {
  switch (_currentSortOption) {
    case GameSortOption.nameAsc:
      games.sort((a, b) {
        // Special handling for games starting with ~
        bool aStartsWithTilde = a.title.startsWith('~');
        bool bStartsWithTilde = b.title.startsWith('~');
        
        // If one starts with ~ and the other doesn't, the ~ one goes last
        if (aStartsWithTilde && !bStartsWithTilde) return 1;
        if (!aStartsWithTilde && bStartsWithTilde) return -1;
        
        // Otherwise, normal alphabetical comparison
        return a.title.compareTo(b.title);
      });
      break;
    case GameSortOption.nameDesc:
      games.sort((a, b) {
        // Special handling for games starting with ~
        bool aStartsWithTilde = a.title.startsWith('~');
        bool bStartsWithTilde = b.title.startsWith('~');
        
        // If one starts with ~ and the other doesn't, the ~ one goes first for Z-A
        if (aStartsWithTilde && !bStartsWithTilde) return -1;
        if (!aStartsWithTilde && bStartsWithTilde) return 1;
        
        // Otherwise, reverse alphabetical comparison
        return b.title.compareTo(a.title);
      });
      break;
  }
}


  // Filter games based on search and matched filter
  List<GameHash> _getFilteredGames() {
    final gamesState = ref.watch(gamesHashesStateProvider);
    if (gamesState.data == null) return [];
    
    // Filter by matched games if needed
    List<GameHash> filteredList = List.from(gamesState.data!);
    
    if (_showOnlyMatched) {
      // Filter games based on actual match status
      filteredList = filteredList.where((game) {
        final status = _matchStatuses[game.id];
        return status == MatchStatus.fullMatch || status == MatchStatus.partialMatch;
      }).toList();
    }
    
    // Filter by search query
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      filteredList = filteredList.where((game) => 
        game.title.toLowerCase().contains(query)).toList();
    }
    
    // Apply sorting
    _sortGames(filteredList);
    
    return filteredList;
  }




  @override
  Widget build(BuildContext context) {
    super.build(context);
    
    final filteredGames = _getFilteredGames();
    final gamesState = ref.watch(gamesHashesStateProvider);
    
    return Card(
      color: AppColors.cardBackground,
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with title and actions
            GamesHeader(
  consoleName: widget.consoleName,
  onViewToggle: _toggleView,
  onRefresh: _refreshData,
  isGridView: _isGridView,
  isHashingInProgress: _isHashingInProgress,  
),
            
            const SizedBox(height: 16),
            
            // Folders display
            FoldersDisplayWidget(
              folders: _consoleFolders,
              onAddFolder: _onAddFolder,
            ),
            
            const SizedBox(height: 16),
            
            // Search and filters
            GamesFilters(
              searchController: _searchController,
              onSearchChanged: (value) {
                setState(() {
                  _searchQuery = value;
                });
              },
              showOnlyMatched: _showOnlyMatched,
              onFilterChanged: _toggleMatchedFilter,
              currentSortOption: _currentSortOption, 
            onSortChanged: _handleSortChange, 
            ),
            
            const SizedBox(height: 16),
            
            // Game count and hashing progress
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Showing ${filteredGames.length} games',
                  style: const TextStyle(
                    color: AppColors.info,
                    fontSize: 14,
                  ),
                ),
                if (_isHashingInProgress)
                  const Row(
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                        ),
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Hashing in progress...',
                        style: TextStyle(
                          color: AppColors.primary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            
            const SizedBox(height: 16),
            
            // Loading indicator or games grid/list
            _isLoading || gamesState.isLoading
                ? const Expanded(
                    child: Center(
                      child: CircularProgressIndicator(color: AppColors.primary),
                    ),
                  )
                : gamesState.data == null || gamesState.data!.isEmpty
                    ? const Expanded(
                        child: Center(
                          child: Text(
                            'No games found',
                            style: TextStyle(
                              color: AppColors.textLight,
                              fontSize: 18,
                            ),
                          ),
                        ),
                      )
                    : Expanded(
                        child: _isGridView
                            ? GamesGrid(
                                games: filteredGames,
                                onGameSelected: _navigateToGameDetails,
                                matchStatuses: _matchStatuses,
                                isHashingInProgress: _isHashingInProgress,
                              )
                            : GamesList(
                                games: filteredGames,
                                onGameSelected: _navigateToGameDetails,
                                matchStatuses: _matchStatuses,
                                isHashingInProgress: _isHashingInProgress,
                              ),
                      ),
          ],
        ),
      ),
    );
  }
  

void _navigateToGameDetails(GameHash game) {
  // Navigate to game details screen using GoRouter with nested route
  // This maintains the navigation stack with games/:consoleId as the parent
  context.go('/games/${widget.consoleId}/game/${game.id}?title=${Uri.encodeComponent(game.title)}&icon=${Uri.encodeComponent(game.imageIcon)}&console=${Uri.encodeComponent(widget.consoleName)}');
}
  
  @override
  bool get wantKeepAlive => true;
}