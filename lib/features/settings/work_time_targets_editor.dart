import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/di/app_settings_provider.dart';
import '../../core/di/sync_providers.dart';
import '../../data/drift/database.dart';
import '../../features/reports/balance_calculations.dart' show targetMinutesForWeekday;
import '../../l10n/app_localizations.dart';
import 'weekly_target_distribution.dart';

/// Settings editor for the per-weekday work-time target. Two input modes
/// over the same seven stored values: seven day fields, or one weekly
/// figure plus work-day toggles that is distributed on save. The mode is
/// persisted only so the screen reopens the way the user left it — every
/// calculation reads the seven day values.
class WorkTimeTargetsEditor extends ConsumerStatefulWidget {
  const WorkTimeTargetsEditor({super.key});

  @override
  ConsumerState<WorkTimeTargetsEditor> createState() => _WorkTimeTargetsEditorState();
}

class _WorkTimeTargetsEditorState extends ConsumerState<WorkTimeTargetsEditor> {
  /// True while a write is in flight — disables the inputs so a fast
  /// double edit cannot interleave two read-modify-write cycles on the
  /// singleton settings row.
  bool _busy = false;

  /// The mode the user picked this session, overriding the stored value
  /// until the settings stream catches up. A `SegmentedButton` must flip
  /// instantly on tap; waiting for the write's round trip through the
  /// database would make it feel unresponsive, and the settings stream can
  /// otherwise lag a frame or more behind the tap.
  String? _selectedMode;

  Future<void> _guardedWrite(Future<void> Function() write) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await write();
    } catch (error) {
      debugPrint('Failed to save work-time target: $error');
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.settingsWorkTimeSaveError)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Flips the visible mode immediately (a segmented button must not wait on
  /// a database round trip) and writes the change through in the
  /// background. The stored value's only job is remembering the choice for
  /// next time the screen opens -- no calculation reads it -- so nothing is
  /// lost if the write settles a moment after the UI already switched.
  void _setMode(String mode) {
    setState(() => _selectedMode = mode);
    unawaited(
      _guardedWrite(() async {
        final writes = await ref.read(syncedWritesProvider.future);
        await writes.updateAppSettings(targetInputMode: mode);
      }),
    );
  }

  Future<void> _setDayMinutes(int weekday, int minutes) async {
    await _guardedWrite(() async {
      final writes = await ref.read(syncedWritesProvider.future);
      await writes.updateAppSettings(
        targetMinutesMonday: weekday == DateTime.monday ? minutes : null,
        targetMinutesTuesday: weekday == DateTime.tuesday ? minutes : null,
        targetMinutesWednesday: weekday == DateTime.wednesday ? minutes : null,
        targetMinutesThursday: weekday == DateTime.thursday ? minutes : null,
        targetMinutesFriday: weekday == DateTime.friday ? minutes : null,
        targetMinutesSaturday: weekday == DateTime.saturday ? minutes : null,
        targetMinutesSunday: weekday == DateTime.sunday ? minutes : null,
      );
    });
  }

  Future<void> _setWeekly(int weeklyMinutes, Set<int> workDays) async {
    await _guardedWrite(() async {
      final perDay = distributeWeeklyMinutes(weeklyMinutes, workDays);
      final writes = await ref.read(syncedWritesProvider.future);
      await writes.updateAppSettings(
        targetInputMode: 'perWeek',
        targetMinutesMonday: perDay[DateTime.monday],
        targetMinutesTuesday: perDay[DateTime.tuesday],
        targetMinutesWednesday: perDay[DateTime.wednesday],
        targetMinutesThursday: perDay[DateTime.thursday],
        targetMinutesFriday: perDay[DateTime.friday],
        targetMinutesSaturday: perDay[DateTime.saturday],
        targetMinutesSunday: perDay[DateTime.sunday],
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final settings = ref.watch(appSettingsProvider).value;
    if (settings == null) return const Center(child: CircularProgressIndicator());

    final isWeekly = (_selectedMode ?? settings.targetInputMode) == 'perWeek';
    final workDays = {
      for (var weekday = 1; weekday <= 7; weekday++)
        if (targetMinutesForWeekday(settings, weekday) > 0) weekday,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.settingsWorkTimeTargetsTitle, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          l10n.settingsWorkTimeTargetsDescription,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        SegmentedButton<bool>(
          segments: [
            ButtonSegment(value: false, label: Text(l10n.settingsWorkTimeModePerWeekday)),
            ButtonSegment(value: true, label: Text(l10n.settingsWorkTimeModePerWeek)),
          ],
          selected: {isWeekly},
          onSelectionChanged: _busy
              ? null
              : (selection) => _setMode(selection.first ? 'perWeek' : 'perWeekday'),
        ),
        const SizedBox(height: 16),
        if (isWeekly)
          _WeeklyInput(
            settings: settings,
            workDays: workDays,
            enabled: !_busy,
            onChanged: _setWeekly,
          )
        else
          _PerWeekdayInput(settings: settings, enabled: !_busy, onChanged: _setDayMinutes),
      ],
    );
  }
}

/// The weekday's localized full name, from intl rather than seven ARB keys
/// per locale. 2024-01-01 was a Monday, so it anchors the offset.
String weekdayName(BuildContext context, int weekday) {
  final localeName = Localizations.localeOf(context).toLanguageTag();
  return DateFormat.EEEE(localeName).format(DateTime(2024, 1, weekday));
}

/// Parses an hours field ("7,7" or "7.7") into whole minutes; null when the
/// text is not a number.
int? hoursTextToMinutes(String text) {
  final hours = double.tryParse(text.trim().replaceAll(',', '.'));
  if (hours == null) return null;
  return (hours * 60).round();
}

String minutesToHoursText(int minutes) {
  if (minutes == 0) return '';
  final hours = minutes / 60;
  return hours == hours.roundToDouble()
      ? hours.round().toString()
      : hours.toStringAsFixed(2).replaceAll('.', ',');
}

/// Seven day fields, one per weekday. Stateful (not a plain
/// StatelessWidget) because it owns a [TextEditingController] per field:
/// this widget rebuilds on every emission of the settings stream, and a
/// controller built fresh in `build()` would reset the field text on each
/// rebuild -- including while the user is mid-keystroke in it.
class _PerWeekdayInput extends StatefulWidget {
  const _PerWeekdayInput({
    required this.settings,
    required this.enabled,
    required this.onChanged,
  });

  final AppSettingsRow settings;
  final bool enabled;
  final Future<void> Function(int weekday, int minutes) onChanged;

  @override
  State<_PerWeekdayInput> createState() => _PerWeekdayInputState();
}

class _PerWeekdayInputState extends State<_PerWeekdayInput> {
  late final List<TextEditingController> _controllers = [
    for (var weekday = 1; weekday <= 7; weekday++)
      TextEditingController(
        text: minutesToHoursText(targetMinutesForWeekday(widget.settings, weekday)),
      ),
  ];

  @override
  void didUpdateWidget(_PerWeekdayInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only push a stored value into its controller when that value actually
    // changed -- otherwise every rebuild (e.g. the `_busy` flag toggling
    // around this same field's own write) would reset the cursor and
    // overwrite whatever the user is currently typing.
    for (var weekday = 1; weekday <= 7; weekday++) {
      final oldMinutes = targetMinutesForWeekday(oldWidget.settings, weekday);
      final newMinutes = targetMinutesForWeekday(widget.settings, weekday);
      if (oldMinutes != newMinutes) {
        _controllers[weekday - 1].text = minutesToHoursText(newMinutes);
      }
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      children: [
        for (var weekday = 1; weekday <= 7; weekday++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(child: Text(weekdayName(context, weekday))),
                SizedBox(
                  width: 120,
                  child: TextField(
                    key: ValueKey('workTimeTarget$weekday'),
                    enabled: widget.enabled,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    controller: _controllers[weekday - 1],
                    decoration: InputDecoration(
                      isDense: true,
                      suffixText: l10n.settingsWorkTimeHoursSuffix,
                    ),
                    onSubmitted: (text) {
                      final minutes = hoursTextToMinutes(text);
                      if (minutes != null && minutes >= 0) widget.onChanged(weekday, minutes);
                    },
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _WeeklyInput extends StatefulWidget {
  const _WeeklyInput({
    required this.settings,
    required this.workDays,
    required this.enabled,
    required this.onChanged,
  });

  final AppSettingsRow settings;
  final Set<int> workDays;
  final bool enabled;
  final Future<void> Function(int weeklyMinutes, Set<int> workDays) onChanged;

  @override
  State<_WeeklyInput> createState() => _WeeklyInputState();
}

class _WeeklyInputState extends State<_WeeklyInput> {
  late final Set<int> _workDays = widget.workDays.isEmpty
      ? {DateTime.monday, DateTime.tuesday, DateTime.wednesday, DateTime.thursday, DateTime.friday}
      : {...widget.workDays};

  late final TextEditingController _weeklyController = TextEditingController(
    text: minutesToHoursText(_weeklyMinutesOf(widget.settings)),
  );

  int _weeklyMinutesOf(AppSettingsRow settings) => [
        for (var weekday = 1; weekday <= 7; weekday++) targetMinutesForWeekday(settings, weekday),
      ].fold(0, (sum, minutes) => sum + minutes);

  @override
  void didUpdateWidget(_WeeklyInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Same rationale as _PerWeekdayInput: only overwrite the field when the
    // stored total actually changed, never on every rebuild.
    final oldMinutes = _weeklyMinutesOf(oldWidget.settings);
    final newMinutes = _weeklyMinutesOf(widget.settings);
    if (oldMinutes != newMinutes) {
      _weeklyController.text = minutesToHoursText(newMinutes);
    }
  }

  @override
  void dispose() {
    _weeklyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          key: const ValueKey('workTimeWeekly'),
          enabled: widget.enabled,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          controller: _weeklyController,
          decoration: InputDecoration(
            labelText: l10n.settingsWorkTimeWeeklyHours,
            isDense: true,
            suffixText: l10n.settingsWorkTimeHoursSuffix,
          ),
          onSubmitted: (text) {
            final minutes = hoursTextToMinutes(text);
            if (minutes != null && minutes >= 0) widget.onChanged(minutes, _workDays);
          },
        ),
        const SizedBox(height: 12),
        Text(l10n.settingsWorkTimeWorkDays, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var weekday = 1; weekday <= 7; weekday++)
              FilterChip(
                label: Text(weekdayName(context, weekday)),
                selected: _workDays.contains(weekday),
                onSelected: widget.enabled
                    ? (selected) {
                        setState(() {
                          selected ? _workDays.add(weekday) : _workDays.remove(weekday);
                        });
                        widget.onChanged(_weeklyMinutesOf(widget.settings), _workDays);
                      }
                    : null,
              ),
          ],
        ),
      ],
    );
  }
}
