// lib/screens/dashboard/utils/dashboard_formatter.dart

class DashboardFormatter {
  // Format date as relative time (e.g. "2 days ago")
  static String formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);
    
    if (difference.inDays < 1) {
      if (difference.inHours < 1) {
        return '${difference.inMinutes} min ago';
      }
      return '${difference.inHours} hours ago';
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} days ago';
    } else if (difference.inDays < 30) {
      return '${(difference.inDays / 7).floor()} weeks ago';
    } else {
      return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    }
  }
  
  // Format short date (DD/MM/YYYY)
  static String formatShortDate(dynamic dateStr) {
    try {
      if (dateStr is String) {
        final date = DateTime.parse(dateStr);
        return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
      }
      return dateStr.toString();
    } catch (e) {
      return dateStr.toString();
    }
  }
  
  // Format numbers with K/M suffix for large values
  static String formatNumber(dynamic number) {
    if (number == null) return 'N/A';
    
    try {
      int parsedNumber = int.parse(number.toString());
      
      if (parsedNumber >= 1000000) {
        return '${(parsedNumber / 1000000).toStringAsFixed(1)}M';
      } else if (parsedNumber >= 1000) {
        return '${(parsedNumber / 1000).toStringAsFixed(1)}K';
      } else {
        return parsedNumber.toString();
      }
    } catch (e) {
      return number.toString();
    }
  }
}