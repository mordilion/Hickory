import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/app_settings_provider.dart';
import '../../core/di/sync_providers.dart';
import '../../core/format/quick_add_durations.dart';
import '../../l10n/app_localizations.dart';

/// Settings-screen editor for the Timer tab's quick-add duration presets
/// (see QuickAddBar). Persists through the same synced AppSettings row as
/// date/time format, so the presets follow the user across devices.
class QuickAddDurationsEditor extends ConsumerWidget {
  const QuickAddDurationsEditor({super.key});

  Future<void> _remove(WidgetRef ref, List<int> current, int minutes) async {
    final updated = List<int>.from(current)..remove(minutes);
    final writes = await ref.read(syncedWritesProvider.future);
    await writes.updateAppSettings(quickAddDurationsMinutes: formatQuickAddDurations(updated));
  }

  Future<void> _add(BuildContext context, WidgetRef ref, List<int> current) async {
    final l10n = AppLocalizations.of(context);
    final controller = TextEditingController();
    final minutes = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.settingsQuickAddNewDurationLabel),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: InputDecoration(labelText: l10n.settingsQuickAddNewDurationLabel),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(l10n.commonCancel)),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(int.tryParse(controller.text.trim())),
            child: Text(l10n.commonSave),
          ),
        ],
      ),
    );
    if (minutes == null || minutes <= 0 || current.contains(minutes)) return;
    final updated = List<int>.from(current)..add(minutes);
    final writes = await ref.read(syncedWritesProvider.future);
    await writes.updateAppSettings(quickAddDurationsMinutes: formatQuickAddDurations(updated));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final settings = ref.watch(appSettingsProvider).value;
    final durations = settings.quickAddDurations;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.settingsQuickAddTitle, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(l10n.settingsQuickAddDescription, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final minutes in durations)
              Chip(
                label: Text(l10n.quickAddDurationChipLabel(minutes)),
                onDeleted: () => _remove(ref, durations, minutes),
                deleteButtonTooltipMessage: l10n.settingsQuickAddRemoveTooltip,
              ),
            ActionChip(
              avatar: const Icon(Icons.add, size: 18),
              label: Text(l10n.settingsQuickAddAddLabel),
              onPressed: () => _add(context, ref, durations),
            ),
          ],
        ),
      ],
    );
  }
}
