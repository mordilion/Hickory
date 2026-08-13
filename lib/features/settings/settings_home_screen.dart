import 'dart:io';

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import 'clients_settings_screen.dart';
import 'general_settings_screen.dart';
import 'projects_settings_screen.dart';
import 'reset_settings_screen.dart';
import 'time_tracking_settings_screen.dart';
import 'update_settings_screen.dart';

/// The Settings tab's landing page: a category list. Each row pushes its
/// own sub-page onto this tab's local Navigator -- see settings_screen.dart
/// and docs/superpowers/specs/2026-08-08-settings-reorganization-design.md.
class SettingsHomeScreen extends StatelessWidget {
  const SettingsHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.settingsTitle,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 16),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.tune),
                  title: Text(l10n.settingsCategoryGeneral),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const GeneralSettingsScreen(),
                    ),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.timer_outlined),
                  title: Text(l10n.settingsCategoryTimeTracking),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const TimeTrackingSettingsScreen(),
                    ),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.folder_outlined),
                  title: Text(l10n.settingsProjectsTitle),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const ProjectsSettingsScreen(),
                    ),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.business_outlined),
                  title: Text(l10n.settingsClientsTitle),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const ClientsSettingsScreen(),
                    ),
                  ),
                ),
                if (Platform.isMacOS || Platform.isWindows) ...[
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.system_update_outlined),
                    title: Text(l10n.settingsUpdateTitle),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const UpdateSettingsScreen(),
                      ),
                    ),
                  ),
                ],
                const Divider(height: 1),
                ListTile(
                  leading: Icon(
                    Icons.warning_amber_outlined,
                    color: colorScheme.error,
                  ),
                  title: Text(
                    l10n.settingsResetTitle,
                    style: TextStyle(color: colorScheme.error),
                  ),
                  trailing: Icon(Icons.chevron_right, color: colorScheme.error),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const ResetSettingsScreen(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
