import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/di/app_settings_provider.dart';
import '../../core/di/sync_providers.dart';
import '../../data/drift/database.dart';
import '../../l10n/app_localizations.dart';
import '../reports/balance_calculations.dart' show targetMinutesForWeekday;
import 'settings_editor_support.dart';
import 'weekly_target_distribution.dart';
import 'work_time_format.dart';

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

class _WorkTimeTargetsEditorState extends ConsumerState<WorkTimeTargetsEditor>
    with SettingsWriteGuard {
  /// The mode the user picked this session, overriding the stored value
  /// until the settings stream catches up. A `SegmentedButton` must flip
  /// instantly on tap; waiting for the write's round trip through the
  /// database would make it feel unresponsive, and the settings stream can
  /// otherwise lag a frame or more behind the tap.
  String? _selectedMode;

  @override
  String saveErrorMessage(AppLocalizations l10n) => l10n.settingsWorkTimeSaveError;

  void _reportInvalidHours() =>
      showMessage(AppLocalizations.of(context).settingsWorkTimeInvalidHours);

  /// Flips the visible mode immediately (a segmented button must not wait on
  /// a database round trip) and writes the change through in the
  /// background. The stored value's only job is remembering the choice for
  /// next time the screen opens -- no calculation reads it -- so nothing is
  /// lost if the write settles a moment after the UI already switched.
  void _setMode(String mode) {
    setState(() => _selectedMode = mode);
    unawaited(
      guardedWrite(() async {
        final writes = await ref.read(syncedWritesProvider.future);
        await writes.updateAppSettings(targetInputMode: mode);
      }),
    );
  }

  Future<bool> _setDayMinutes(int weekday, int minutes) {
    return guardedWrite(() async {
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

  Future<bool> _setWeekly(int weeklyMinutes, Set<int> workDays) {
    return guardedWrite(() async {
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
          onSelectionChanged: busy
              ? null
              : (selection) => _setMode(selection.first ? 'perWeek' : 'perWeekday'),
        ),
        const SizedBox(height: 16),
        if (isWeekly)
          _WeeklyInput(
            settings: settings,
            workDays: workDays,
            chipsEnabled: !busy,
            onChanged: _setWeekly,
            onInvalidInput: _reportInvalidHours,
          )
        else
          _PerWeekdayInput(
            settings: settings,
            onChanged: _setDayMinutes,
            onInvalidInput: _reportInvalidHours,
          ),
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

/// Seven day fields, one per weekday. Stateful (not a plain
/// StatelessWidget) because it owns a [TextEditingController] per field:
/// this widget rebuilds on every emission of the settings stream, and a
/// controller built fresh in `build()` would reset the field text on each
/// rebuild -- including while the user is mid-keystroke in it.
///
/// The fields stay enabled while a write is in flight, unlike the chips and
/// the mode toggle: disabling a focused field takes its focus away, which
/// would break tabbing from one day to the next -- the very gesture that
/// commits the previous field.
class _PerWeekdayInput extends StatefulWidget {
  const _PerWeekdayInput({
    required this.settings,
    required this.onChanged,
    required this.onInvalidInput,
  });

  final AppSettingsRow settings;
  final Future<bool> Function(int weekday, int minutes) onChanged;
  final VoidCallback onInvalidInput;

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

  /// What each field was last saved as, indexed by `weekday - 1`. Enter and
  /// the focus loss that follows it are two commit paths over one value,
  /// and the settings stream has not come back round between them -- so
  /// [widget.settings] alone cannot tell the second commit that the first
  /// already happened.
  late final List<int> _committed = [
    for (var weekday = 1; weekday <= 7; weekday++)
      targetMinutesForWeekday(widget.settings, weekday),
  ];

  @override
  void didUpdateWidget(_PerWeekdayInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only push a stored value into its controller when that value actually
    // changed -- otherwise every rebuild (e.g. another field's write
    // settling) would reset the cursor and overwrite whatever the user is
    // currently typing.
    for (var weekday = 1; weekday <= 7; weekday++) {
      final oldMinutes = targetMinutesForWeekday(oldWidget.settings, weekday);
      final newMinutes = targetMinutesForWeekday(widget.settings, weekday);
      if (oldMinutes != newMinutes) {
        setTextPreservingCaret(_controllers[weekday - 1], minutesToHoursText(newMinutes));
        _committed[weekday - 1] = newMinutes;
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

  /// Persists what the field for [weekday] currently reads, if that is a
  /// new and usable figure. Empty text is left alone rather than read as
  /// zero: a zero target renders as an empty field, so every pass through
  /// an untouched free day would otherwise be a write. Text that is not a
  /// non-negative number is reported to the user instead of dropped.
  void _commit(int weekday) {
    final text = _controllers[weekday - 1].text.trim();
    if (text.isEmpty) return;
    final minutes = hoursTextToMinutes(text);
    if (minutes == null || minutes < 0) {
      widget.onInvalidInput();
      return;
    }
    final index = weekday - 1;
    if (minutes == _committed[index]) return;
    final previous = _committed[index];
    _committed[index] = minutes;
    // Put back when the write did not go through, or a value that failed
    // to save could never be retried from this field again.
    unawaited(
      widget.onChanged(weekday, minutes).then((saved) {
        if (!saved) _committed[index] = previous;
      }),
    );
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
                // The day name is the field's label, so it is announced
                // there (below) rather than a second time as loose text.
                Expanded(
                  child: ExcludeSemantics(child: Text(weekdayName(context, weekday))),
                ),
                SizedBox(
                  width: 120,
                  child: Semantics(
                    label: weekdayName(context, weekday),
                    child: CommitOnFocusLoss(
                      onCommit: () => _commit(weekday),
                      child: TextField(
                        key: ValueKey('workTimeTarget$weekday'),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        controller: _controllers[weekday - 1],
                        decoration: InputDecoration(
                          isDense: true,
                          suffixText: l10n.settingsWorkTimeHoursSuffix,
                        ),
                        onSubmitted: (_) => _commit(weekday),
                      ),
                    ),
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
    required this.chipsEnabled,
    required this.onChanged,
    required this.onInvalidInput,
  });

  final AppSettingsRow settings;
  final Set<int> workDays;
  final bool chipsEnabled;
  final Future<bool> Function(int weeklyMinutes, Set<int> workDays) onChanged;
  final VoidCallback onInvalidInput;

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

  /// The weekly total as last saved -- the same role [_committed] plays
  /// for the seven day fields.
  late int _committedWeekly = _weeklyMinutesOf(widget.settings);

  int _weeklyMinutesOf(AppSettingsRow settings) => [
        for (var weekday = 1; weekday <= 7; weekday++) targetMinutesForWeekday(settings, weekday),
      ].fold(0, (sum, minutes) => sum + minutes);

  /// The weekly figure as the field currently reads it, falling back to the
  /// stored sum when it holds nothing usable. A chip toggle redistributes
  /// this, and it must be what the user can see: distributing the stored
  /// sum instead would write a total the field contradicts, and because
  /// [didUpdateWidget] only refreshes the field when the stored sum
  /// changes, the screen would go on showing the figure that was never
  /// saved.
  int get _weeklyMinutesOnScreen {
    final typed = hoursTextToMinutes(_weeklyController.text.trim());
    if (typed == null || typed < 0) return _weeklyMinutesOf(widget.settings);
    return typed;
  }

  @override
  void didUpdateWidget(_WeeklyInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Same rationale as _PerWeekdayInput: only overwrite the field when the
    // stored total actually changed, never on every rebuild.
    final oldMinutes = _weeklyMinutesOf(oldWidget.settings);
    final newMinutes = _weeklyMinutesOf(widget.settings);
    if (oldMinutes != newMinutes) {
      setTextPreservingCaret(_weeklyController, minutesToHoursText(newMinutes));
      _committedWeekly = newMinutes;
    }
  }

  @override
  void dispose() {
    _weeklyController.dispose();
    super.dispose();
  }

  /// Same contract as `_PerWeekdayInputState._commit`: empty is left alone,
  /// unusable text is reported, and an unchanged figure is not rewritten.
  void _commit() {
    final text = _weeklyController.text.trim();
    if (text.isEmpty) return;
    final minutes = hoursTextToMinutes(text);
    if (minutes == null || minutes < 0) {
      widget.onInvalidInput();
      return;
    }
    if (minutes == _committedWeekly) return;
    _save(minutes, _workDays);
  }

  /// Records [minutes] as saved before the write returns, for the reason
  /// given on [_committedWeekly], and puts the old figure back if it did
  /// not go through.
  void _save(int minutes, Set<int> workDays) {
    final previous = _committedWeekly;
    _committedWeekly = minutes;
    unawaited(
      widget.onChanged(minutes, workDays).then((saved) {
        if (!saved) _committedWeekly = previous;
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CommitOnFocusLoss(
          onCommit: _commit,
          child: TextField(
            key: const ValueKey('workTimeWeekly'),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            controller: _weeklyController,
            decoration: InputDecoration(
              labelText: l10n.settingsWorkTimeWeeklyHours,
              isDense: true,
              suffixText: l10n.settingsWorkTimeHoursSuffix,
            ),
            onSubmitted: (_) => _commit(),
          ),
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
                onSelected: widget.chipsEnabled
                    ? (selected) {
                        setState(() {
                          selected ? _workDays.add(weekday) : _workDays.remove(weekday);
                        });
                        _save(_weeklyMinutesOnScreen, _workDays);
                      }
                    : null,
              ),
          ],
        ),
      ],
    );
  }
}
