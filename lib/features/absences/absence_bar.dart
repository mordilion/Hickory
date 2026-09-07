import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/absence_providers.dart';
import '../../core/di/app_settings_provider.dart';
import '../../core/di/device_id_provider.dart';
import '../../core/di/sync_providers.dart';
import '../../core/format/date_format.dart';
import '../../core/theme/hickory_colors.dart';
import '../../core/widgets/gradient_buttons.dart';
import '../../data/drift/database.dart';
import '../../data/drift/tables/absences_table.dart';
import '../../l10n/app_localizations.dart';
import 'absence_days.dart';
import 'absence_time_range.dart';

/// The third way to record on the main screen, beside the timer and a
/// manual entry: a day (or a span of days) that was not worked.
///
/// A full or half day covers a span of dates, because vacation comes in
/// runs; a time range covers a single day, because that is what an
/// appointment is. Days with no target are skipped rather than recorded —
/// see [absenceDaysBetween].
class AbsenceBar extends ConsumerStatefulWidget {
  const AbsenceBar({super.key});

  @override
  ConsumerState<AbsenceBar> createState() => _AbsenceBarState();
}

class _AbsenceBarState extends ConsumerState<AbsenceBar> {
  final _noteController = TextEditingController();
  String? _typeId;
  String _portion = absencePortionFullDay;
  String _halfDayPart = absenceHalfDayMorning;
  DateTime _from = DateTime.now();
  DateTime _to = DateTime.now();
  TimeOfDay _startTime = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay _endTime = const TimeOfDay(hour: 11, minute: 0);
  bool _busy = false;

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _pickDate({required bool isStart}) async {
    final initial = isStart ? _from : _to;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(initial.year - 5),
      lastDate: DateTime(initial.year + 5),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isStart) {
        _from = picked;
        // Keep the span valid without silently discarding the user's pick.
        if (_to.isBefore(picked)) _to = picked;
        return;
      }
      _to = picked;
      if (_from.isAfter(picked)) _from = picked;
    });
  }

  Future<void> _pickTime({required bool isStart}) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: isStart ? _startTime : _endTime,
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isStart) {
        _startTime = picked;
        // The same clamping _pickDate does, and for a sharper reason: an
        // end before the start is written as a row absenceMinutes scores
        // as zero, so the snackbar would report a success that credits
        // nothing.
        if (!isAbsenceRangeInOrder(picked, _endTime)) _endTime = picked;
        return;
      }
      _endTime = picked;
      if (!isAbsenceRangeInOrder(_startTime, picked)) _startTime = picked;
    });
  }

  DateTime _at(DateTime day, TimeOfDay time) =>
      DateTime(day.year, day.month, day.day, time.hour, time.minute);

  Future<void> _submit(AppSettingsRow settings, List<AbsenceType> types) async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context);
    final typeId = _typeId ?? types.first.id;

    // The pickers keep the two times in order but cannot keep them apart,
    // and a range that ends when it starts is scored as zero minutes -- so
    // saving it would report an absence that credits nothing.
    if (_portion == absencePortionRange &&
        !isAbsenceRangeInOrder(_startTime, _endTime)) {
      _showMessage(l10n.absenceFormInvalidRange);
      return;
    }

    // A time range is one day by definition; the span pickers only apply
    // to whole and half days.
    final days = _portion == absencePortionRange
        ? absenceDaysBetween(_from, _from, settings)
        : absenceDaysBetween(_from, _to, settings);
    if (days.isEmpty) {
      _showMessage(l10n.absenceFormNoWorkDays);
      return;
    }

    setState(() => _busy = true);
    try {
      final deviceId = await ref.read(deviceIdProvider.future);
      final writes = await ref.read(syncedWritesProvider.future);
      final note = _noteController.text.trim();
      for (final day in days) {
        await writes.createAbsence(
          deviceId: deviceId,
          date: day,
          absenceTypeId: typeId,
          portion: _portion,
          startAt: _portion == absencePortionRange
              ? _at(day, _startTime).toUtc()
              : null,
          endAt: _portion == absencePortionRange
              ? _at(day, _endTime).toUtc()
              : null,
          halfDayPart: _portion == absencePortionHalfDay ? _halfDayPart : null,
          note: note.isEmpty ? null : note,
        );
      }
      _noteController.clear();
      if (mounted) _showMessage(l10n.absenceFormSaved(days.length));
    } catch (error) {
      debugPrint('Failed to save absence: $error');
      if (mounted) _showMessage(l10n.absenceFormSaveError);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final settings = ref.watch(appSettingsProvider).value;
    final types = ref.watch(absenceTypesProvider).value ?? const <AbsenceType>[];
    // The same Card > Padding(16) the timer's start card and QuickAddBar
    // use, so the three modes of this tab are one shape -- including while
    // loading and with no type yet, or the box would come and go.
    if (settings == null) {
      return const _AbsenceCard(child: Center(child: CircularProgressIndicator()));
    }
    if (types.isEmpty) return _AbsenceCard(child: Text(l10n.absenceFormNoTypes));

    // The same two settings QuickAddBar and the manual dialog read, so a
    // date or a time reads identically whichever mode of this tab wrote it.
    final dateStyle = settings.dateStyle;
    final timeStyle = settings.timeStyle;
    final languageCode = Localizations.localeOf(context).languageCode;
    final tokens = HickoryColors.of(context);
    final isRange = _portion == absencePortionRange;
    final selectedType = _typeId ?? types.first.id;

    return _AbsenceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Free text first, then what it is about: the same order the
          // timer card and QuickAddBar put their description in.
          TextField(
            key: const ValueKey('absenceNote'),
            controller: _noteController,
            enabled: !_busy,
            decoration: InputDecoration(labelText: l10n.absenceFormNote),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: const ValueKey('absenceType'),
            initialValue: selectedType,
            decoration: InputDecoration(labelText: l10n.absenceFormType),
            items: [
              for (final type in types)
                DropdownMenuItem(value: type.id, child: Text(type.name)),
            ],
            onChanged: _busy ? null : (id) => setState(() => _typeId = id),
          ),
          const SizedBox(height: 12),
          // No heading: the three segments name themselves. The label lives
          // on as the control's accessible name, which has no visible
          // equivalent to fall back on.
          Center(
            child: Semantics(
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
                onSelectionChanged: _busy
                    ? null
                    : (selection) => setState(() => _portion = selection.first),
              ),
            ),
          ),
          if (_portion == absencePortionHalfDay) ...[
            const SizedBox(height: 8),
            // Which half is informational -- half a day is credited either
            // way -- but "half a day off" without saying which half is not
            // something anyone writes down on paper either.
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
                onSelectionChanged: _busy
                    ? null
                    : (selection) => setState(() => _halfDayPart = selection.first),
              ),
            ),
          ],
          const SizedBox(height: 12),
          // Laid out like QuickAddBar's four pickers: bare text buttons in
          // a Wrap with an en dash between the two ends. A whole or half
          // day spans dates, a time range spans one day's clock, so the
          // dash sits between whichever pair is the span.
          Center(
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                TextButton(
                  key: const ValueKey('absenceStartDate'),
                  onPressed: _busy ? null : () => _pickDate(isStart: true),
                  child: Text(formatDate(_from, dateStyle, languageCode)),
                ),
                if (isRange)
                  TextButton(
                    key: const ValueKey('absenceStartTime'),
                    onPressed: _busy ? null : () => _pickTime(isStart: true),
                    child: Text(formatTime(_at(_from, _startTime), timeStyle)),
                  ),
                const Text('–'),
                TextButton(
                  key: const ValueKey('absenceEndDate'),
                  onPressed: _busy ? null : () => _pickDate(isStart: false),
                  child: Text(formatDate(_to, dateStyle, languageCode)),
                ),
                if (isRange)
                  TextButton(
                    key: const ValueKey('absenceEndTime'),
                    onPressed: _busy ? null : () => _pickTime(isStart: false),
                    child: Text(formatTime(_at(_to, _endTime), timeStyle)),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // The same commitment QuickAddBar's add and the timer's start
          // are, so it gets the same full-width pill rather than a small
          // button of its own.
          GradientPillButton(
            label: l10n.absenceFormSubmit,
            icon: Icons.event_busy_outlined,
            gradient: tokens.primaryGradient,
            foregroundColor: tokens.onPrimaryGradient,
            onPressed: _busy ? null : () => _submit(settings, types),
          ),
        ],
      ),
    );
  }
}

/// The box every mode of the timer tab shares: `Card > Padding(16)`, the
/// same shape as the timer's start card and QuickAddBar.
class _AbsenceCard extends StatelessWidget {
  const _AbsenceCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(padding: const EdgeInsets.all(16), child: child),
      );
}
