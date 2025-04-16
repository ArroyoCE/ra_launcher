// lib/screens/dashboard/components/global_stats_summary.dart

import 'package:flutter/material.dart';
import 'package:retroachievements_organizer/constants/constants.dart';
import 'package:retroachievements_organizer/models/user/user_awards_model.dart';
import 'package:retroachievements_organizer/models/user/user_summary_model.dart';
import 'package:retroachievements_organizer/screens/dashboard/utils/dashboard_formatter.dart';

class GlobalStatsSummary extends StatelessWidget {
  final UserSummary? userSummary;
  final UserAwards? userAwards;

  const GlobalStatsSummary({
    super.key,
    required this.userSummary,
    required this.userAwards,
  });

  @override
  Widget build(BuildContext context) {
    if (userSummary == null && userAwards == null) {
      return const SizedBox.shrink();
    }
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Global Statistics',
              style: TextStyle(
                color: AppColors.textLight,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (userSummary != null && 
                userSummary!.lastActivity != null && 
                userSummary!.lastActivity!['timestamp'] != null)
              Text(
                'Last active: ${DashboardFormatter.formatDate(DateTime.parse(userSummary!.lastActivity!['timestamp']))}',
                style: const TextStyle(
                  color: AppColors.textSubtle,
                  fontSize: 12,
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        
        // Stats card
        Container(
          padding: const EdgeInsets.all(16),
          width: double.infinity,
          decoration: BoxDecoration(
            color: AppColors.cardBackground,
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Wrap(
            alignment: WrapAlignment.spaceAround,
            spacing: 20,
            runSpacing: 16,
            children: [
              _buildGlobalStatItem(
                'Rank',
                userSummary != null ? DashboardFormatter.formatNumber(userSummary!.rank) : 'N/A',
                Colors.amber,
              ),
              _buildGlobalStatItem(
                'Points',
                userSummary != null ? DashboardFormatter.formatNumber(userSummary!.totalPoints) : 'N/A',
                AppColors.primary,
              ),
              _buildGlobalStatItem(
                'Mastered',
                userAwards != null ? DashboardFormatter.formatNumber(userAwards!.masteryAwardsCount) : 'N/A',
                AppColors.primary,
              ),
              _buildGlobalStatItem(
                'Beaten',
                userAwards != null ? DashboardFormatter.formatNumber(userAwards!.beatenHardcoreAwardsCount) : 'N/A',
                AppColors.info,
              ),
              _buildGlobalStatItem(
                'Total Awards',
                userAwards != null ? DashboardFormatter.formatNumber(userAwards!.totalAwardsCount) : 'N/A',
                AppColors.warning,
              ),
            ],
          ),
        ),
      ],
    );
  }
  
  Widget _buildGlobalStatItem(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textLight,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}