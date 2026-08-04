import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/app_settings_provider.dart';
import '../../core/di/break_rule_tiers_provider.dart';
import '../../core/di/device_id_provider.dart';
import '../../core/di/sync_providers.dart';
import '../../core/format/date_format.dart';
import '../../core/format/duration_format.dart';
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

String _presetLabel(AppLocalizations l10n, _PresetCountry country) => switch (country) {
      _PresetCountry.germany => l10n.settingsBreakRulePresetGermany,
      _PresetCountry.austria => l10n.settingsBreakRulePresetAustria,
      _PresetCountry.switzerland => l10n.settingsBreakRulePresetSwitzerland,
    };

/// Settings-screen editor for the day header's break-time rule (see
/// EntriesList). Persists through the synced BreakRuleTiers table, so the
/// rule follows the user across devices, same as every other setting. See
/// docs/superpowers/specs/2026-08-04-break-rule-tiers-design.md.
class BreakRuleTiersEditor extends ConsumerWidget {
  const BreakRuleTiersEditor({super.key});

  Future<void> _applyPreset(WidgetRef ref, List<BreakRuleTierValues> tiers) async {
    final deviceId = await ref.read(deviceIdProvider.future);
    final writes = await ref.read(syncedWritesProvider.future);
    await writes.replaceBreakRuleTiers(deviceId: deviceId, tiers: tiers);
  }

  Future<void> _remove(WidgetRef ref, String id) async {
    final writes = await ref.read(syncedWritesProvider.future);
    await writes.deleteBreakRuleTier(id);
  }

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final afterController = TextEditingController();
    final requiredController = TextEditingController();
    final result = await showDialog<BreakRuleTierValues>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.settingsBreakRuleAddTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: afterController,
              keyboardType: TextInputType.number,
              autofocus: true,
              decoration: InputDecoration(labelText: l10n.settingsBreakRuleAfterMinutesLabel),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: requiredController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: l10n.settingsBreakRuleRequiredMinutesLabel),
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
              final required = int.tryParse(requiredController.text.trim());
              if (after == null || required == null || after <= 0 || required <= 0) {
                Navigator.of(context).pop();
                return;
              }
              Navigator.of(context).pop(
                BreakRuleTierValues(afterMinutes: after, requiredBreakMinutes: required),
              );
            },
            child: Text(l10n.commonSave),
          ),
        ],
      ),
    );
    if (result == null) return;
    final deviceId = await ref.read(deviceIdProvider.future);
    final writes = await ref.read(syncedWritesProvider.future);
    await writes.createBreakRuleTier(
      deviceId: deviceId,
      afterMinutes: result.afterMinutes,
      requiredBreakMinutes: result.requiredBreakMinutes,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final tiersAsync = ref.watch(breakRuleTiersProvider);
    final tiers = tiersAsync.value ?? const <BreakRuleTier>[];
    final settings = ref.watch(appSettingsProvider).value;
    final timeStyle = settings.timeStyle;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.settingsBreakRuleTitle, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(l10n.settingsBreakRuleDescription, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final preset in _presets)
              ActionChip(
                label: Text(_presetLabel(l10n, preset.country)),
                onPressed: () => _applyPreset(ref, preset.tiers),
              ),
            ActionChip(
              label: Text(l10n.settingsBreakRuleNone),
              onPressed: () => _applyPreset(ref, const []),
            ),
          ],
        ),
        const SizedBox(height: 12),
        for (final tier in tiers)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              l10n.settingsBreakRuleTierLabel(
                formatDuration(Duration(minutes: tier.afterMinutes), timeStyle),
                formatDuration(Duration(minutes: tier.requiredBreakMinutes), timeStyle),
              ),
            ),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: l10n.settingsBreakRuleRemoveTooltip,
              onPressed: () => _remove(ref, tier.id),
            ),
          ),
        ActionChip(
          avatar: const Icon(Icons.add, size: 18),
          label: Text(l10n.settingsBreakRuleAddLabel),
          onPressed: () => _add(context, ref),
        ),
      ],
    );
  }
}
