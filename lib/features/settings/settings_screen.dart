import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/app_settings_provider.dart';
import '../../core/di/autostart_service.dart';
import '../../core/di/sync_providers.dart';
import '../../core/format/date_format.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
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
    final settings = ref.watch(appSettingsProvider).value;
    final dateStyle = settings.dateStyle;
    final timeStyle = settings.timeStyle;
    final now = DateTime.now();

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Einstellungen', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 16),
          Card(
            child: _loading
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: LinearProgressIndicator(),
                  )
                : SwitchListTile(
                    title: const Text('Beim Systemstart öffnen'),
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
                  DropdownButtonFormField<DateFormatStyle>(
                    initialValue: dateStyle,
                    decoration: const InputDecoration(labelText: 'Datumsformat'),
                    items: DateFormatStyle.values
                        .map(
                          (style) => DropdownMenuItem(
                            value: style,
                            child: Text(formatDate(now, style)),
                          ),
                        )
                        .toList(),
                    onChanged: (style) => style == null ? null : _setDateFormat(style),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<TimeFormatStyle>(
                    initialValue: timeStyle,
                    decoration: const InputDecoration(labelText: 'Zeitformat'),
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
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
