import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/app_settings_provider.dart';
import '../../core/di/autostart_service.dart';
import '../../core/di/database_provider.dart';
import '../../core/di/sync_providers.dart';
import '../../core/di/update_providers.dart';
import '../../core/format/date_format.dart';
import '../../core/update/update_checker.dart';
import '../../l10n/app_localizations.dart';
import '../projects/projects_editor.dart';
import 'break_rule_tiers_editor.dart';
import 'language_dropdown.dart';
import 'quick_add_durations_editor.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _loading = true;
  bool _autostartEnabled = false;
  bool _updateBusy = false;
  String? _updateStatusMessage;

  @override
  void initState() {
    super.initState();
    _loadAutostartState();
  }

  Future<void> _loadAutostartState() async {
    final enabled = await ref.read(autostartServiceProvider).isEnabled();
    if (!mounted) return;
    setState(() {
      _autostartEnabled = enabled;
      _loading = false;
    });
  }

  Future<void> _setAutostart(bool value) async {
    setState(() => _autostartEnabled = value);
    await ref.read(autostartServiceProvider).setEnabled(value);
  }

  Future<void> _setDateFormat(DateFormatStyle style) async {
    final writes = await ref.read(syncedWritesProvider.future);
    await writes.updateAppSettings(dateFormat: style.wireName);
  }

  Future<void> _setTimeFormat(TimeFormatStyle style) async {
    final writes = await ref.read(syncedWritesProvider.future);
    await writes.updateAppSettings(timeFormat: style.wireName);
  }

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
      setState(() => _updateStatusMessage = update == null ? l10n.settingsUpdateUpToDate : null);
    } catch (_) {
      if (mounted) setState(() => _updateStatusMessage = l10n.settingsUpdateCheckError);
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
    } catch (_) {
      if (mounted) setState(() => _updateStatusMessage = l10n.settingsUpdateInstallError);
    } finally {
      if (mounted) setState(() => _updateBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final settings = ref.watch(appSettingsProvider).value;
    final dateStyle = settings.dateStyle;
    final timeStyle = settings.timeStyle;
    final now = DateTime.now();
    final currentVersionAsync = ref.watch(currentAppVersionProvider);
    final availableUpdate = ref.watch(availableUpdateProvider);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.settingsTitle, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 16),
          Card(
            child: _loading
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: LinearProgressIndicator(),
                  )
                : SwitchListTile(
                    title: Text(l10n.settingsAutostart),
                    value: _autostartEnabled,
                    onChanged: _setAutostart,
                  ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<DateFormatStyle>(
                          initialValue: dateStyle,
                          isDense: true,
                          decoration: InputDecoration(labelText: l10n.settingsDateFormat),
                          items: DateFormatStyle.values
                              .map(
                                (style) => DropdownMenuItem(
                                  value: style,
                                  child: Text(
                                    formatDate(
                                      now,
                                      style,
                                      Localizations.localeOf(context).languageCode,
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (style) => style == null ? null : _setDateFormat(style),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<TimeFormatStyle>(
                          initialValue: timeStyle,
                          isDense: true,
                          decoration: InputDecoration(labelText: l10n.settingsTimeFormat),
                          items: TimeFormatStyle.values
                              .map(
                                (style) => DropdownMenuItem(
                                  value: style,
                                  child: Text(formatTime(now, style)),
                                ),
                              )
                              .toList(),
                          onChanged: (style) => style == null ? null : _setTimeFormat(style),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const LanguageDropdown(),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: QuickAddDurationsEditor(),
            ),
          ),
          const SizedBox(height: 16),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: BreakRuleTiersEditor(),
            ),
          ),
          const SizedBox(height: 16),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: ProjectsEditor(),
            ),
          ),
          if (Platform.isMacOS || Platform.isWindows) ...[
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l10n.settingsUpdateTitle, style: Theme.of(context).textTheme.titleMedium),
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
                      Text(_updateStatusMessage!, style: Theme.of(context).textTheme.bodySmall),
                    ],
                    const SizedBox(height: 16),
                    if (availableUpdate != null) ...[
                      Text(l10n.settingsUpdateAvailable(availableUpdate.version)),
                      if (availableUpdate.notes.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(availableUpdate.notes, style: Theme.of(context).textTheme.bodySmall),
                      ],
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: _updateBusy ? null : () => _installUpdate(availableUpdate),
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
          ],
        ],
      ),
    );
  }
}
