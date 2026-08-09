import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/database_provider.dart';
import '../../core/di/sync_providers.dart';
import '../../core/di/update_providers.dart';
import '../../core/update/update_checker.dart';
import '../../core/update/update_installer.dart';
import '../../l10n/app_localizations.dart';
import 'settings_sub_page.dart';

class UpdateSettingsScreen extends ConsumerStatefulWidget {
  const UpdateSettingsScreen({super.key});

  @override
  ConsumerState<UpdateSettingsScreen> createState() =>
      _UpdateSettingsScreenState();
}

class _UpdateSettingsScreenState extends ConsumerState<UpdateSettingsScreen> {
  bool _updateBusy = false;
  String? _updateStatusMessage;

  Future<void> _checkForUpdates() async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _updateBusy = true;
      _updateStatusMessage = l10n.settingsUpdateChecking;
    });
    try {
      final checker = ref.read(updateCheckerProvider);
      final update = await checker.checkForUpdate();
      ref.read(availableUpdateProvider.notifier).state = update;
      if (!mounted) return;
      setState(
        () => _updateStatusMessage = update == null
            ? l10n.settingsUpdateUpToDate
            : null,
      );
    } catch (_) {
      if (mounted)
        setState(() => _updateStatusMessage = l10n.settingsUpdateCheckError);
    } finally {
      if (mounted) setState(() => _updateBusy = false);
    }
  }

  Future<void> _installUpdate(UpdateInfo update) async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _updateBusy = true;
      _updateStatusMessage = l10n.settingsUpdateInstalling;
    });
    try {
      final installer = ref.read(updateInstallerProvider);
      final extracted = await installer.prepareUpdate(update);
      final db = ref.read(appDatabaseProvider);
      final writes = await ref.read(syncedWritesProvider.future);
      await installer.quitAndSwap(extracted, db: db, writes: writes);
    } on UpdateInstallPermissionException {
      if (mounted) {
        setState(
          () =>
              _updateStatusMessage = l10n.settingsUpdateInstallErrorPermission,
        );
      }
    } catch (_) {
      if (mounted)
        setState(() => _updateStatusMessage = l10n.settingsUpdateInstallError);
    } finally {
      if (mounted) setState(() => _updateBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final currentVersionAsync = ref.watch(currentAppVersionProvider);
    final availableUpdate = ref.watch(availableUpdateProvider);

    return SettingsSubPage(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.settingsUpdateTitle,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              currentVersionAsync.when(
                data: (version) => Text(
                  l10n.settingsUpdateCurrentVersion(version),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                loading: () => const SizedBox.shrink(),
                error: (_, _) => const SizedBox.shrink(),
              ),
              if (_updateStatusMessage != null) ...[
                const SizedBox(height: 8),
                Text(
                  _updateStatusMessage!,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 16),
              if (availableUpdate != null) ...[
                Text(l10n.settingsUpdateAvailable(availableUpdate.version)),
                if (availableUpdate.notes.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    availableUpdate.notes,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _updateBusy
                      ? null
                      : () => _installUpdate(availableUpdate),
                  child: Text(l10n.settingsUpdateInstallButton),
                ),
              ] else
                OutlinedButton(
                  onPressed: _updateBusy ? null : _checkForUpdates,
                  child: Text(l10n.settingsUpdateCheckButton),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
