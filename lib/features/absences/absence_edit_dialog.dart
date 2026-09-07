import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/absence_providers.dart';
import '../../core/di/app_settings_provider.dart';
import '../../core/format/date_format.dart';
import '../../data/drift/database.dart';
import '../../data/drift/tables/absences_table.dart';
import '../../l10n/app_localizations.dart';
import 'absence_time_range.dart';

/// What an edit changed, ready to hand to `SyncedWrites.updateAbsence`.
/// Timestamps are UTC and built on the absence's own day, which the dialog
/// never moves — see `AbsencesDao.updateAbsence` for why.
typedef AbsenceEdit = ({
  String absenceTypeId,
  String portion,
  String? halfDayPart,
  DateTime? startAt,
  DateTime? endAt,
  String? note,
});

/// Edits one recorded absence: its type, its extent, the time range a
/// `range` absence covers, and its note.
///
/// Pops with an [AbsenceEdit] on save and with null on cancel; it writes
/// nothing itself. The day stays fixed, so this is the correction path for
/// a mistyped record rather than a way to move an absence — that is a
/// delete and a fresh entry.
class AbsenceEditDialog extends ConsumerStatefulWidget {
  const AbsenceEditDialog({super.key, required this.absence});

  final Absence absence;

  @override
  ConsumerState<AbsenceEditDialog> createState() => _AbsenceEditDialogState();
}

class _AbsenceEditDialogState extends ConsumerState<AbsenceEditDialog> {
  late final TextEditingController _note =
      TextEditingController(text: widget.absence.note ?? '');
  late String _typeId = widget.absence.absenceTypeId;
  late String _portion = widget.absence.portion;
  late String _halfDayPart = widget.absence.halfDayPart ?? absenceHalfDayMorning;
  late TimeOfDay _startTime = _timeOf(widget.absence.startAt, const TimeOfDay(hour: 9, minute: 0));
  late TimeOfDay _endTime = _timeOf(widget.absence.endAt, const TimeOfDay(hour: 11, minute: 0));

  /// The stored range is UTC; the pickers and the rebuilt timestamps work
  /// in local time, the same way the form that recorded it did.
  static TimeOfDay _timeOf(DateTime? stored, TimeOfDay fallback) {
    if (stored == null) return fallback;
    final local = stored.toLocal();
    return TimeOfDay(hour: local.hour, minute: local.minute);
  }

  /// Set when the range is not a span; cleared as soon as it becomes one.
  bool _rangeInvalid = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickTime({required bool isStart}) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: isStart ? _startTime : _endTime,
    );
    if (picked == null || !mounted) return;
    setState(() {
      isStart ? _startTime = picked : _endTime = picked;
      _rangeInvalid = false;
    });
  }

  DateTime _at(TimeOfDay time) {
    final day = widget.absence.date;
    return DateTime(day.year, day.month, day.day, time.hour, time.minute).toUtc();
  }

  void _save() {
    final isRange = _portion == absencePortionRange;
    if (isRange && !isAbsenceRangeInOrder(_startTime, _endTime)) {
      setState(() => _rangeInvalid = true);
      return;
    }
    final note = _note.text.trim();
    Navigator.of(context).pop((
      absenceTypeId: _typeId,
      portion: _portion,
      halfDayPart: _portion == absencePortionHalfDay ? _halfDayPart : null,
      startAt: isRange ? _at(_startTime) : null,
      endAt: isRange ? _at(_endTime) : null,
      note: note.isEmpty ? null : note,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final types = ref.watch(absenceTypesProvider).value ?? const <AbsenceType>[];
    // The same two settings every other date and time in the app reads.
    final settings = ref.watch(appSettingsProvider).value;
    final dateStyle = settings.dateStyle;
    final timeStyle = settings.timeStyle;
    final languageCode = Localizations.localeOf(context).languageCode;
    final isRange = _portion == absencePortionRange;
    // A type deleted on another device would otherwise leave the dropdown
    // with a value none of its items carry, which Flutter asserts on.
    final selectedType = types.any((type) => type.id == _typeId)
        ? _typeId
        : (types.isEmpty ? null : types.first.id);

    return AlertDialog(
      title: Text(l10n.commonEdit),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButtonFormField<String>(
            key: const ValueKey('absenceEditType'),
            initialValue: selectedType,
            isDense: true,
            decoration: InputDecoration(labelText: l10n.absenceFormType),
            items: [
              for (final type in types)
                DropdownMenuItem(value: type.id, child: Text(type.name)),
            ],
            onChanged: (id) => setState(() => _typeId = id ?? _typeId),
          ),
          const SizedBox(height: 12),
          Semantics(
            label: l10n.absenceFormPortion,
            child: SegmentedButton<String>(
              segments: [
                ButtonSegment(
                  value: absencePortionFullDay,
                  label: Text(l10n.absencePortionFullDay),
                ),
                ButtonSegment(
                  value: absencePortionHalfDay,
                  label: Text(l10n.absencePortionHalfDay),
                ),
                ButtonSegment(
                  value: absencePortionRange,
                  label: Text(l10n.absencePortionRange),
                ),
              ],
              selected: {_portion},
              onSelectionChanged: (selection) => setState(() {
                _portion = selection.first;
                _rangeInvalid = false;
              }),
            ),
          ),
          if (_portion == absencePortionHalfDay) ...[
            const SizedBox(height: 8),
            Center(
              child: SegmentedButton<String>(
                segments: [
                  ButtonSegment(
                    value: absenceHalfDayMorning,
                    label: Text(l10n.absenceHalfDayMorning),
                  ),
                  ButtonSegment(
                    value: absenceHalfDayAfternoon,
                    label: Text(l10n.absenceHalfDayAfternoon),
                  ),
                ],
                selected: {_halfDayPart},
                onSelectionChanged: (selection) =>
                    setState(() => _halfDayPart = selection.first),
              ),
            ),
          ],
          const SizedBox(height: 8),
          // Laid out like the recording form's pickers, with the day the
          // absence covers spelled out rather than offered as a button:
          // this dialog cannot move a row to another day.
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(formatDate(widget.absence.date, dateStyle, languageCode)),
              if (isRange) ...[
                TextButton(
                  key: const ValueKey('absenceEditStartTime'),
                  onPressed: () => _pickTime(isStart: true),
                  child: Text(formatTime(_at(_startTime).toLocal(), timeStyle)),
                ),
                const Text('–'),
                TextButton(
                  key: const ValueKey('absenceEditEndTime'),
                  onPressed: () => _pickTime(isStart: false),
                  child: Text(formatTime(_at(_endTime).toLocal(), timeStyle)),
                ),
              ],
            ],
          ),
          if (isRange && _rangeInvalid) ...[
            const SizedBox(height: 8),
            Text(
              l10n.absenceFormInvalidRange,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 8),
          TextField(
            key: const ValueKey('absenceEditNote'),
            controller: _note,
            decoration: InputDecoration(labelText: l10n.absenceFormNote, isDense: true),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(onPressed: _save, child: Text(l10n.commonSave)),
      ],
    );
  }
}
