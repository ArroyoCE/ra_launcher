// lib/models/hash_match_model.dart

enum MatchStatus {
  noMatch,     // No matching hashes found
  partialMatch, // Some, but not all matching hashes
  fullMatch     // All hashes match
}

class HashMatchModel {
  final int gameId;
  final String gameTitle;
  final List<String> apiHashes;
  final List<String> matchedHashes;
  final MatchStatus status;
  final List<String> matchedFilePaths;

  HashMatchModel({
    required this.gameId,
    required this.gameTitle,
    required this.apiHashes,
    required this.matchedHashes,
    required this.status,
    required this.matchedFilePaths,
  });

  factory HashMatchModel.fromGame(
    int gameId, 
    String gameTitle,
    List<String> apiHashes, 
    Map<String, String> localHashes
  ) {
    // Find matching hashes
    final List<String> matchedHashes = [];
    final List<String> matchedPaths = [];

    // Convert values to a list for easier searching
    final localHashValues = localHashes.values.toList();
    
    for (final hash in apiHashes) {
      if (localHashValues.contains(hash)) {
        matchedHashes.add(hash);
        
        // Find the file path for this hash
        localHashes.forEach((path, hashValue) {
          if (hashValue == hash && !matchedPaths.contains(path)) {
            matchedPaths.add(path);
          }
        });
      }
    }

    // Determine match status
    MatchStatus status;
    if (matchedHashes.isEmpty) {
      status = MatchStatus.noMatch;
    } else if (matchedHashes.length == apiHashes.length) {
      status = MatchStatus.fullMatch;
    } else {
      status = MatchStatus.partialMatch;
    }

    return HashMatchModel(
      gameId: gameId,
      gameTitle: gameTitle,
      apiHashes: apiHashes,
      matchedHashes: matchedHashes,
      status: status,
      matchedFilePaths: matchedPaths,
    );
  }
}