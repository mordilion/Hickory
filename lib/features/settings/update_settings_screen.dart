import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/database_provider.dart';
import '../../core/di/sync_providers.dart';
import '../../core/di/update_providers.dart';
import '../../core/update/update_checker.dart';
import '../../core/update/update_installer.dart';
import '../../l10n/app_localizations.dart';
import 'settings_sub_page.dart';

/// Update-check and install flow -- state and handlers relocated verbatim
/// from the old monolithic SettingsScreen. The Platform.isMacOS/isWindows
/// guard that gated this content lives in SettingsHomeScreen instead,
/// controlling whether this screen is reachable at all.
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
      // Captured before the await below: if this screen gets popped while
      // the check is in flight, using ref.read() after the await would
      // throw StateError (the widget's element is disposed) and silently
      // drop a real result. The notifier itself outlives this screen (its
      // provider isn't scoped to this widget), so writing to it directly is
      // safe. Kept inside the try so a throw here is still caught below.
      final checker = ref.read(updateCheckerProvider);
      final updateNotifier = ref.read(availableUpdateProvider.notifier);
      final update = await checker.checkForUpdate();
      updateNotifier.state = update;
      if (!mounted) return;
      setState(
        () => _updateStatusMessage = update == null
            ? l10n.settingsUpdateUpToDate
            : null,
      );
    } catch (_) {
      if (mounted) {
        setState(() => _updateStatusMessage = l10n.settingsUpdateCheckError);
      }
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
      // Same reasoning as _checkForUpdates: capture everything ref-derived
      // before the first await, so a pop mid-download doesn't throw and
      // silently abandon an update that already finished downloading. Kept
      // inside the try so a throw here is still caught below.
      final installer = ref.read(updateInstallerProvider);
      final db = ref.read(appDatabaseProvider);
      final writesFuture = ref.read(syncedWritesProvider.future);
      final extracted = await installer.prepareUpdate(update);
      final writes = await writesFuture;
      await installer.quitAndSwap(extracted, db: db, writes: writes);
    } on UpdateInstallPermissionException {
      if (mounted) {
        setState(
          () =>
              _updateStatusMessage = l10n.settingsUpdateInstallErrorPermission,
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _updateStatusMessage = l10n.settingsUpdateInstallError);
      }
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
