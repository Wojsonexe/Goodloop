import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:goodloop/core/constants/app_colors.dart';
import 'package:goodloop/domain/providers/auth_provider.dart';
import 'package:goodloop/domain/providers/theme_provider.dart';
import '../../../domain/providers/notification_service.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  Future<void> _pickNotificationTime(NotificationTime current) async {
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current.hour, minute: current.minute),
    );

    if (time == null) return;

    try {
      await ref
          .read(notificationSettingsProvider.notifier)
          .schedule(time.hour, time.minute);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Notification time updated!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not update notification time: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);
    final notificationTime = ref.watch(notificationSettingsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSection(
            context,
            title: 'Notifications',
            children: [
              ListTile(
                leading: const Icon(Icons.notifications_active),
                title: const Text('Daily Reminder'),
                subtitle: notificationTime.when(
                  data: (time) => Text(
                    'Every day at ${TimeOfDay(hour: time.hour, minute: time.minute).format(context)}',
                  ),
                  loading: () => const Text('Loading...'),
                  error: (_, __) => const Text('Not set'),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _pickNotificationTime(
                  notificationTime.valueOrNull ??
                      const NotificationTime(hour: 9, minute: 0),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _buildSection(
            context,
            title: 'Appearance',
            children: [
              ListTile(
                leading: const Icon(Icons.brightness_6),
                title: const Text('Theme'),
                subtitle: Text(_getThemeModeName(themeMode)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _showThemeDialog(context),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _buildSection(
            context,
            title: 'Account',
            children: [
              ListTile(
                leading: const Icon(Icons.logout, color: AppColors.error),
                title: const Text(
                  'Sign Out',
                  style: TextStyle(color: AppColors.error),
                ),
                onTap: () => _showSignOutDialog(context),
              ),
            ],
          ),
          const SizedBox(height: 32),
          Center(
            child: Text(
              'GoodLoop v1.0.0',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection(
    BuildContext context, {
    required String title,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.bold,
                ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }

  String _getThemeModeName(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'Light';
      case ThemeMode.dark:
        return 'Dark';
      case ThemeMode.system:
        return 'System';
    }
  }

  void _showThemeDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select Theme'),
        content: buildThemeSelector(context),
      ),
    );
  }

  Widget buildThemeSelector(BuildContext context) {
    final current = ref.watch(themeModeProvider);

    // The RadioGroup now handles the current value and the onChanged callback
    return RadioGroup<ThemeMode>(
      groupValue: current,
      onChanged: (ThemeMode? newValue) {
        if (newValue != null) {
          ref.read(themeModeProvider.notifier).setThemeMode(newValue);
          Navigator.pop(context);
        }
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildThemeRadio(title: 'Light', value: ThemeMode.light),
          _buildThemeRadio(title: 'Dark', value: ThemeMode.dark),
          _buildThemeRadio(title: 'System', value: ThemeMode.system),
        ],
      ),
    );
  }

  Widget _buildThemeRadio({required String title, required ThemeMode value}) {
    return RadioListTile<ThemeMode>(
      title: Text(title),
      value: value,
      contentPadding: EdgeInsets.zero, // Makes it fit better in dialogs
    );
  }

  void _showSignOutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign Out'),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              await ref.read(authControllerProvider.notifier).signOut();
              if (context.mounted) {
                context.go('/welcome');
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
            ),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );
  }
}
