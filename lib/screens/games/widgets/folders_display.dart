// lib/screens/games/widgets/folders_display_widget.dart

import 'package:flutter/material.dart';
import 'package:retroachievements_organizer/constants/constants.dart';

class FoldersDisplayWidget extends StatelessWidget {
  final List<String> folders;
  final VoidCallback onAddFolder;

  const FoldersDisplayWidget({
    super.key,
    required this.folders,
    required this.onAddFolder,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppColors.darkBackground,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Linked ROM Folders:',
                  style: TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add_circle, color: AppColors.primary),
                  onPressed: onAddFolder,
                  tooltip: 'Add Folder',
                ),
              ],
            ),
            const SizedBox(height: 8),
            
            // Folders list or empty message
            if (folders.isEmpty)
              const Padding(
                padding: EdgeInsets.all(8.0),
                child: Text(
                  'No folders linked to this Console',
                  style: TextStyle(
                    color: AppColors.textSubtle,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              )
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: folders.length,
                itemBuilder: (context, index) {
                  return Container(
                    padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                    margin: const EdgeInsets.only(bottom: 4),
                    decoration: BoxDecoration(
                      color: AppColors.cardBackground,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.folder, color: AppColors.primary, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            folders[index],
                            style: const TextStyle(
                              color: AppColors.textLight,
                              fontSize: 14,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}