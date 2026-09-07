import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/app_settings_provider.dart';
import '../../core/di/balance_adjustment_providers.dart';
import '../../core/di/device_id_provider.dart';
import '../../core/di/sync_providers.dart';
import '../../core/format/date_format.dart';
import '../../data/drift/database.dart';
import '../../l10n/app_localizations.dart';
import '../settings/work_time_format.dart';
import 'balance_card.dart' show formatSignedDuration;

/// Opens the list of manual balance corrections, where one can be added or
/// taken back.
Future<void> showBalanceAdjustmentsDialog(BuildContext context, WidgetRef ref) {
  return showDialog<void>(
    context: context,
    builder: (_) => const _BalanceAdjustmentsDialog(),
  );
}

/// Every correction, newest work first, plus the form that adds one.
///
/// Corrections are written straight from here rather than handed back to a
/// caller: the dialog stays open across several of them, which a
/// pop-with-a-result shape cannot do.
class _BalanceAdjustmentsDialog extends ConsumerStatefulWidget {
  const _BalanceAdjustmentsDialog();

  @override
  ConsumerState<_BalanceAdjustmentsDialog> createState() =>
      _BalanceAdjustmentsDialogState();
}

class _BalanceAdjustmentsDialogState
    extends ConsumerState<_BalanceAdjustmentsDialog> {
  final _hours = TextEditingController();
  final _note = TextEditingController();
  DateTime _date = DateTime.now();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _hours.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(_date.year - 5),
      lastDate: DateTime(_date.year + 5),
    );
    if (picked == null || !mounted) return;
    setState(() => _date = picked);
  }

  Future<void> _add() async {
    final l10n = AppLocalizations.of(context);
    final minutes = hoursTextToMinutes(_hours.text);
    // Zero is refused alongside unparseable text: a correction of no time
    // is a row that says nothing and still has to be looked at.
    if (minutes == null || minutes == 0) {
      setState(() => _error = l10n.reportsAdjustmentInvalid);
      return;
    }

    setState(() {
      _error = null;
      _busy = true;
    });
    try {
      final deviceId = await ref.read(deviceIdProvider.future);
      final writes = await ref.read(syncedWritesProvider.future);
      final note = _note.text.trim();
      await writes.createAdjustment(
        deviceId: deviceId,
        // Local midnight, the key the balance pass groups corrections by.
        date: DateTime(_date.year, _date.month, _date.day),
        deltaMinutes: minutes,
        note: note.isEmpty ? null : note,
      );
      if (!mounted) return;
      _hours.clear();
      _note.clear();
    } catch (error) {
      debugPrint('Failed to save balance adjustment: $error');
      if (mounted) setState(() => _error = l10n.reportsAdjustmentSaveError);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(String id) async {
    setState(() => _busy = true);
    try {
      final writes = await ref.read(syncedWritesProvider.future);
      await writes.deleteAdjustment(id);
    } catch (error) {
      debugPrint('Failed to delete balance adjustment: $error');
      if (mounted) {
        setState(() => _error = AppLocalizations.of(context).reportsAdjustmentSaveError);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final settings = ref.watch(appSettingsProvider).value;
    final dateStyle = settings.dateStyle;
    final languageCode = Localizations.localeOf(context).languageCode;
    final adjustments = ref.watch(balanceAdjustmentsProvider).value ?? const <BalanceAdjustment>[];

    return AlertDialog(
      title: Text(l10n.reportsAdjustmentsTitle),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (adjustments.isEmpty)
              Text(l10n.reportsAdjustmentsEmpty, style: theme.textTheme.bodyMedium),
            for (final adjustment in adjustments)
              ListTile(
                key: ValueKey(adjustment.id),
                contentPadding: EdgeInsets.zero,
                title: Text(formatSignedDuration(Duration(minutes: adjustment.deltaMinutes))),
                subtitle: Text(
                  [
                    formatDate(adjustment.date, dateStyle, languageCode),
                    ?adjustment.note,
                  ].join(' · '),
                ),
                trailing: IconButton(
                  key: ValueKey('deleteAdjustment-${adjustment.id}'),
                  icon: const Icon(Icons.delete_outline),
                  tooltip: l10n.commonDelete,
                  onPressed: _busy ? null : () => _delete(adjustment.id),
                ),
              ),
            const Divider(),
            Row(
              children: [
                TextButton(
                  key: const ValueKey('adjustmentDate'),
                  onPressed: _busy ? null : _pickDate,
                  child: Text(formatDate(_date, dateStyle, languageCode)),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 110,
                  child: TextField(
                    key: const ValueKey('adjustmentHours'),
                    controller: _hours,
                    enabled: !_busy,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                    decoration: InputDecoration(
                      labelText: l10n.reportsAdjustmentHours,
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              key: const ValueKey('adjustmentNote'),
              controller: _note,
              enabled: !_busy,
              decoration: InputDecoration(
                labelText: l10n.reportsAdjustmentNote,
                isDense: true,
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonClose),
        ),
        FilledButton(
          onPressed: _busy ? null : _add,
          child: Text(l10n.reportsAdjustmentAdd),
        ),
      ],
    );
  }
}
