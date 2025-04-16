// lib/screens/settings_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retroachievements_organizer/constants/constants.dart';
import 'package:retroachievements_organizer/providers/states/auth_state_provider.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  final Widget child;

  const SettingsScreen({super.key, required this.child});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> with AutomaticKeepAliveClientMixin {
  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
  
  @override
  bool get wantKeepAlive => true;
}

class SettingsContent extends ConsumerStatefulWidget {
  const SettingsContent({super.key});

  @override
  ConsumerState<SettingsContent> createState() => _SettingsContentState();
}

class _SettingsContentState extends ConsumerState<SettingsContent> with AutomaticKeepAliveClientMixin {
  bool _autoLogin = true;
  
  @override
  void initState() {
    super.initState();
    // Initialize with user preferences
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final userState = ref.read(authStateProvider);
      setState(() {
        _autoLogin = userState.autoLogin;
      });
    });
  }
  
  @override
  Widget build(BuildContext context) {
    super.build(context);
    
    return Card(
      color: AppColors.cardBackground,
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Settings title
            const Text(
              'Settings',
              style: TextStyle(
                color: AppColors.primary,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Divider(color: AppColors.primary),
            const SizedBox(height: 24),
            
            // Settings options
            SwitchListTile(
              title: const Text(
                'Auto Login',
                style: TextStyle(
                  color: AppColors.textLight,
                  fontSize: 16,
                ),
              ),
              subtitle: const Text(
                'Remember login credentials',
                style: TextStyle(
                  color: AppColors.textLight,
                  fontSize: 12,
                ),
              ),
              value: _autoLogin,
              activeColor: AppColors.primary,
              onChanged: (value) {
                setState(() {
                  _autoLogin = value;
                });
                ref.read(authStateProvider.notifier).setAutoLogin(value);
              },
            ),
            
            const Divider(color: Colors.grey),
            
            // Version info
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text(
                'Version: 1.0.0 (Beta)',
                style: TextStyle(
                  color: Colors.grey,
                  fontSize: 12,
                ),
              ),
            ),
            
            // More settings to come
            const Expanded(
              child: Center(
                child: Text(
                  'More settings options coming soon!',
                  style: TextStyle(
                    color: AppColors.textLight,
                    fontSize: 16,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  @override
  bool get wantKeepAlive => true;
}