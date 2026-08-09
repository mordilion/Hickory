import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/app_settings_provider.dart';
import '../../core/di/break_rule_tiers_provider.dart';
import '../../core/di/device_id_provider.dart';
import '../../core/di/sync_providers.dart';
import '../../data/drift/database.dart';
import '../../data/sync/synced_writes.dart';
import '../../l10n/app_localizations.dart';

enum _PresetCountry { germany, austria, switzerland }

class _Preset {
  const _Preset({required this.country, required this.tiers});
  final _PresetCountry country;
  final List<BreakRuleTierValues> tiers;
}

const _presets = [
  _Preset(
    country: _PresetCountry.germany,
    tiers: [
      BreakRuleTierValues(afterMinutes: 360, requiredBreakMinutes: 30),
      BreakRuleTierValues(afterMinutes: 540, requiredBreakMinutes: 45),
    ],
  ),
  _Preset(
    country: _PresetCountry.austria,
    tiers: [BreakRuleTierValues(afterMinutes: 360, requiredBreakMinutes: 30)],
  ),
  _Preset(
    country: _PresetCountry.switzerland,
    tiers: [
      BreakRuleTierValues(afterMinutes: 330, requiredBreakMinutes: 15),
      BreakRuleTierValues(afterMinutes: 420, requiredBreakMinutes: 30),
      BreakRuleTierValues(afterMinutes: 540, requiredBreakMinutes: 60),
    ],
  ),
];

String _presetLabel(AppLocalizations l10n, _PresetCountry country) =>
    switch (country) {
      _PresetCountry.germany => l10n.settingsBreakRulePresetGermany,
      _PresetCountry.austria => l10n.settingsBreakRulePresetAustria,
      _PresetCountry.switzerland => l10n.settingsBreakRulePresetSwitzerland,
    };

/// "6h 30m" / "6h" / "45m" -- deliberately not the app's clock-style
/// `formatDuration` (which reads like a time of day, e.g. "06:00", and
/// shows seconds under a "*_sec" time style): these values are always
/// whole minutes, and the design spec calls for an hours+minutes phrasing
/// here specifically.
String _formatHoursMinutes(Duration d) {
  final hours = d.inHours;
  final minutes = d.inMinutes.remainder(60);
  if (hours == 0) return '${minutes}m';
  if (minutes == 0) return '${hours}h';
  return '${hours}h ${minutes}m';
}

/// Settings-screen editor for the day header's break-time rule (see
/// EntriesList). Persists through the synced BreakRuleTiers table, so the
/// rule follows the user across devices, same as every other setting. See
/// docs/superpowers/specs/2026-08-04-break-rule-tiers-design.md.
class BreakRuleTiersEditor extends ConsumerStatefulWidget {
  const BreakRuleTiersEditor({super.key});

  @override
  ConsumerState<BreakRuleTiersEditor> createState() =>
      _BreakRuleTiersEditorState();
}

class _BreakRuleTiersEditorState extends ConsumerState<BreakRuleTiersEditor> {
  /// True while a write is in flight -- disables every action in this
  /// editor so a fast double-tap (e.g. on a preset chip) can't interleave
  /// two delete/create loops and produce duplicated tiers.
  bool _busy = false;

  Future<void> _guardedWrite(Future<void> Function() write) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await write();
    } catch (error) {
      debugPrint('Failed to save break-rule setting: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context).settingsBreakRuleSaveError,
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _applyPreset(List<BreakRuleTierValues> tiers) =>
      _guardedWrite(() async {
        final deviceId = await ref.read(deviceIdProvider.future);
        final writes = await ref.read(syncedWritesProvider.future);
        await writes.replaceBreakRuleTiers(deviceId: deviceId, tiers: tiers);
      });

  Future<void> _remove(String id) => _guardedWrite(() async {
    final writes = await ref.read(syncedWritesProvider.future);
    await writes.deleteBreakRuleTier(id);
  });

  Future<void> _setCountPausedTimeAsBreak(bool value) =>
      _guardedWrite(() async {
        final writes = await ref.read(syncedWritesProvider.future);
        await writes.updateAppSettings(countPausedTimeAsBreak: value);
      });

  Future<void> _add() async {
    final l10n = AppLocalizations.of(context);
    final afterController = TextEditingController();
    final requiredController = TextEditingController();
    String? errorText;
    try {
      final result = await showDialog<BreakRuleTierValues>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(l10n.settingsBreakRuleAddTitle),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: afterController,
                    keyboardType: TextInputType.number,
                    autofocus: true,
                    decoration: InputDecoration(
                      labelText: l10n.settingsBreakRuleAfterMinutesLabel,
                      errorText: errorText,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: requiredController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: l10n.settingsBreakRuleRequiredMinutesLabel,
                      errorText: errorText,
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(l10n.commonCancel),
                ),
                FilledButton(
                  onPressed: () {
                    final after = int.tryParse(afterController.text.trim());
                    final required = int.tryParse(
                      requiredController.text.trim(),
                    );
                    if (after == null ||
                        required == null ||
                        after <= 0 ||
                        required <= 0) {
                      setDialogState(
                        () =>
                            errorText = l10n.settingsBreakRuleInvalidTierError,
                      );
                      return;
                    }
                    Navigator.of(context).pop(
                      BreakRuleTierValues(
                        afterMinutes: after,
                        requiredBreakMinutes: required,
                      ),
                    );
                  },
                  child: Text(l10n.commonSave),
                ),
              ],
            );
          },
        ),
      );
      if (result == null) return;
      await _guardedWrite(() async {
        final deviceId = await ref.read(deviceIdProvider.future);
        final writes = await ref.read(syncedWritesProvider.future);
        await writes.createBreakRuleTier(
          deviceId: deviceId,
          afterMinutes: result.afterMinutes,
          requiredBreakMinutes: result.requiredBreakMinutes,
        );
      });
    } finally {
      afterController.dispose();
      requiredController.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tiersAsync = ref.watch(breakRuleTiersProvider);
    final tiers = tiersAsync.value ?? const <BreakRuleTier>[];
    final settings = ref.watch(appSettingsProvider).value;
    final countPausedTimeAsBreak = settings?.countPausedTimeAsBreak ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.settingsBreakRuleTitle,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 4),
        Text(
          l10n.settingsBreakRuleDescription,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final preset in _presets)
              ActionChip(
                label: Text(_presetLabel(l10n, preset.country)),
                onPressed: _busy ? null : () => _applyPreset(preset.tiers),
              ),
            ActionChip(
              label: Text(l10n.settingsBreakRuleNone),
              onPressed: _busy ? null : () => _applyPreset(const []),
            ),
          ],
        ),
        const SizedBox(height: 12),
        for (final tier in tiers)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              l10n.settingsBreakRuleTierLabel(
                _formatHoursMinutes(Duration(minutes: tier.afterMinutes)),
                _formatHoursMinutes(
                  Duration(minutes: tier.requiredBreakMinutes),
                ),
              ),
            ),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: l10n.settingsBreakRuleRemoveTooltip,
              onPressed: _busy ? null : () => _remove(tier.id),
            ),
          ),
        ActionChip(
          avatar: const Icon(Icons.add, size: 18),
          label: Text(l10n.settingsBreakRuleAddLabel),
          onPressed: _busy ? null : _add,
        ),
        const SizedBox(height: 12),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.settingsBreakRuleIncludePausedTime),
          subtitle: Text(l10n.settingsBreakRuleIncludePausedTimeDescription),
          value: countPausedTimeAsBreak,
          onChanged: _busy ? null : _setCountPausedTimeAsBreak,
        ),
      ],
    );
  }
}
