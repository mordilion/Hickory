import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/app_settings_provider.dart';
import '../../core/di/autostart_service.dart';
import '../../core/di/sync_providers.dart';
import '../../core/format/date_format.dart';
import '../../l10n/app_localizations.dart';
import 'language_dropdown.dart';
import 'settings_sub_page.dart';

class GeneralSettingsScreen extends ConsumerStatefulWidget {
  const GeneralSettingsScreen({super.key});

  @override
  ConsumerState<GeneralSettingsScreen> createState() =>
      _GeneralSettingsScreenState();
}

class _GeneralSettingsScreenState extends ConsumerState<GeneralSettingsScreen> {
  bool _loading = true;
  bool _autostartEnabled = false;

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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final settings = ref.watch(appSettingsProvider).value;
    final dateStyle = settings.dateStyle;
    final timeStyle = settings.timeStyle;
    final now = DateTime.now();

    return SettingsSubPage(
      title: l10n.settingsCategoryGeneral,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
                          decoration: InputDecoration(
                            labelText: l10n.settingsDateFormat,
                          ),
                          items: DateFormatStyle.values
                              .map(
                                (style) => DropdownMenuItem(
                                  value: style,
                                  child: Text(
                                    formatDate(
                                      now,
                                      style,
                                      Localizations.localeOf(
                                        context,
                                      ).languageCode,
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (style) =>
                              style == null ? null : _setDateFormat(style),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<TimeFormatStyle>(
                          initialValue: timeStyle,
                          isDense: true,
                          decoration: InputDecoration(
                            labelText: l10n.settingsTimeFormat,
                          ),
                          items: TimeFormatStyle.values
                              .map(
                                (style) => DropdownMenuItem(
                                  value: style,
                                  child: Text(formatTime(now, style)),
                                ),
                              )
                              .toList(),
                          onChanged: (style) =>
                              style == null ? null : _setTimeFormat(style),
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
        ],
      ),
    );
  }
}
