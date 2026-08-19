import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/database_provider.dart';
import '../../core/di/sync_providers.dart';
import '../../core/di/update_providers.dart';
import '../../core/update/update_checker.dart';
import '../../core/update/update_installer.dart';
import '../../core/update/update_progress.dart';
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

  /// Non-null only while an install is running; drives the progress bar.
  UpdateProgress? _updateProgress;

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
      final extracted = await installer.prepareUpdate(
        update,
        onProgress: (progress) {
          if (mounted) setState(() => _updateProgress = progress);
        },
      );
      final writes = await writesFuture;
      await installer.quitAndSwap(extracted, db: db, writes: writes);
    } on UpdateInstallPermissionException catch (error) {
      if (mounted) {
        setState(
          () => _updateStatusMessage = l10n
              .settingsUpdateInstallErrorPermission(error.installParentPath),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _updateStatusMessage = l10n.settingsUpdateInstallError);
      }
    } finally {
      if (mounted) {
        setState(() {
          _updateBusy = false;
          _updateProgress = null;
        });
      }
    }
  }

  /// Label for the current phase, or null when nothing is running. Only the
  /// download has numbers to show -- see [UpdateProgress].
  String? _progressLabel(AppLocalizations l10n, String localeName) {
    final megabytes = NumberFormat.decimalPatternDigits(
      locale: localeName,
      decimalDigits: 1,
    );
    return switch (_updateProgress) {
      null => null,
      UpdateVerifying() => l10n.settingsUpdateVerifying,
      UpdateExtracting() => l10n.settingsUpdateExtracting,
      UpdateDownloading(:final receivedBytes, :final totalBytes) =>
        totalBytes == null || totalBytes <= 0
            ? l10n.settingsUpdateDownloadingUnknownSize(
                megabytes.format(receivedBytes / _bytesPerMegabyte),
              )
            : l10n.settingsUpdateDownloading(
                megabytes.format(receivedBytes / _bytesPerMegabyte),
                megabytes.format(totalBytes / _bytesPerMegabyte),
              ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final currentVersionAsync = ref.watch(currentAppVersionProvider);
    final availableUpdate = ref.watch(availableUpdateProvider);
    final progressLabel = _progressLabel(
      l10n,
      Localizations.localeOf(context).languageCode,
    );

    return SettingsSubPage(
      child: SizedBox(
        width: double.infinity,
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
                if (progressLabel != null) ...[
                  const SizedBox(height: 12),
                  // Null value means indeterminate, which is exactly right for
                  // the verify and extract phases and for a download whose size
                  // the server didn't announce.
                  LinearProgressIndicator(
                    value: switch (_updateProgress) {
                      UpdateDownloading(:final fraction) => fraction,
                      _ => null,
                    },
                  ),
                  const SizedBox(height: 6),
                  Text(
                    progressLabel,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ] else if (_updateStatusMessage != null) ...[
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
      ),
    );
  }
}

const _bytesPerMegabyte = 1024 * 1024;
