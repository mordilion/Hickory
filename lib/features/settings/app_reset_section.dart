import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/jira_providers.dart';
import '../../core/di/locale_provider.dart';
import '../../core/di/personio_providers.dart';
import '../../core/di/reset_providers.dart';
import '../../core/di/sync_providers.dart';
import '../../features/reports/report_view_controller.dart';
import '../../l10n/app_localizations.dart';

/// Settings-screen "danger zone": returns this device to a fresh-install
/// state. See
/// docs/superpowers/specs/2026-08-05-project-delete-and-full-reset-design.md
/// for why this only ever touches this device's own data.
class AppResetSection extends ConsumerStatefulWidget {
  const AppResetSection({super.key});

  @override
  ConsumerState<AppResetSection> createState() => _AppResetSectionState();
}

class _AppResetSectionState extends ConsumerState<AppResetSection> {
  bool _busy = false;

  Future<void> _reset() async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.settingsResetConfirmTitle),
        content: Text(l10n.settingsResetConfirmMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.settingsResetConfirmButton),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      final service = await ref.read(appResetServiceProvider.future);
      await service.resetEverything();
      ref.invalidate(configuredSyncFolderPathProvider);
      ref.invalidate(jiraCredentialsProvider);
      ref.invalidate(personioCredentialsProvider);
      ref.invalidate(localeControllerProvider);
      ref.invalidate(reportViewControllerProvider);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.settingsResetSuccess)));
      }
    } catch (error) {
      debugPrint('Failed to reset the app: $error');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.settingsResetError)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.settingsResetTitle,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 4),
        Text(
          l10n.settingsResetDescription,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          style: OutlinedButton.styleFrom(
            foregroundColor: colorScheme.error,
            side: BorderSide(color: colorScheme.error),
          ),
          onPressed: _busy ? null : _reset,
          child: Text(l10n.settingsResetButton),
        ),
      ],
    );
  }
}
