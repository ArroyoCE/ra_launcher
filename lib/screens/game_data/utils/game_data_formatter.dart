// lib/screens/game_data/utils/game_data_formatter.dart

class GameDataFormatter {
  // Format release date
  static String formatReleaseDate(String? releaseDate) {
    if (releaseDate == null || releaseDate.isEmpty) {
      return 'Unknown';
    }
    
    try {
      final date = DateTime.parse(releaseDate);
      return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    } catch (e) {
      return releaseDate;
    }
  }
  
  // Format points with abbreviation for large values
  static String formatPoints(int points) {
    if (points >= 1000) {
      return '${(points / 1000).toStringAsFixed(1)}K';
    }
    return points.toString();
  }
  
  // Format player count with abbreviation
  static String formatPlayerCount(int count) {
    if (count >= 1000000) {
      return '${(count / 1000000).toStringAsFixed(1)}M';
    } else if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(1)}K';
    }
    return count.toString();
  }
  
  // Format percentage
  static String formatPercentage(double percentage) {
    return '${percentage.toStringAsFixed(1)}%';
  }
}