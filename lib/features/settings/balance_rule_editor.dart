import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/di/app_settings_provider.dart';
import '../../core/di/sync_providers.dart';
import '../../l10n/app_localizations.dart';
import 'settings_editor_support.dart';
import 'work_time_format.dart';

/// Settings editor for what happens to the flex-time balance at the yearly
/// cutoff. The rule is only written once it is complete: a mode without a
/// cutoff date, or a carry-over without any bound, would leave
/// `lastCutoffOnOrBefore` guessing, so the editor keeps an incomplete
/// selection local (never sent to [SyncedWrites]) and tells the user which
/// piece is still missing instead of persisting a half-rule.
class BalanceRuleEditor extends ConsumerStatefulWidget {
  const BalanceRuleEditor({super.key});

  @override
  ConsumerState<BalanceRuleEditor> createState() => _BalanceRuleEditorState();
}

class _BalanceRuleEditorState extends ConsumerState<BalanceRuleEditor>
    with SettingsWriteGuard {
  /// Local overrides for fields the user has touched this session but
  /// that have not (yet) formed a complete, persisted rule. Null means
  /// "use the stored value" — cleared as soon as a write for that value
  /// succeeds, since the settings stream then carries it.
  String? _pendingMode;
  int? _pendingDay;
  int? _pendingMonth;
  int? _pendingMaxMinutes;
  int? _pendingMinMinutes;

  @override
  String saveErrorMessage(AppLocalizations l10n) => l10n.settingsBalanceSaveError;

  void _reportInvalidHours() =>
      showMessage(AppLocalizations.of(context).settingsWorkTimeInvalidHours);

  void _clearPending() {
    setState(() {
      _pendingMode = null;
      _pendingDay = null;
      _pendingMonth = null;
      _pendingMaxMinutes = null;
      _pendingMinMinutes = null;
    });
  }

  /// Records a locally-chosen field and re-evaluates whether the rule as a
  /// whole is now complete enough to persist.
  void _applyChange({int? day, int? month, int? maxMinutes, int? minMinutes}) {
    setState(() {
      if (day != null) _pendingDay = day;
      if (month != null) _pendingMonth = month;
      if (maxMinutes != null) _pendingMaxMinutes = maxMinutes;
      if (minMinutes != null) _pendingMinMinutes = minMinutes;
    });
    _maybePersist();
  }

  /// Writes the rule only once it is complete. Every mode other than
  /// `none` needs a full cutoff -- day *and* month -- and `carryOver`
  /// needs at least one bound on top of that. Nothing is defaulted: a
  /// cutoff the user never picked would reset or clamp the balance on a
  /// date of the app's choosing, and a month without a day is no more of a
  /// choice than no date at all. Anything short of complete stays local
  /// and the missing piece is surfaced in the UI instead.
  void _maybePersist() {
    final settings = ref.read(appSettingsProvider).value;
    if (settings == null) return;
    final mode = _pendingMode ?? settings.balanceResetMode;
    if (mode == 'none') return;

    final day = _pendingDay ?? settings.balanceResetDay;
    final month = _pendingMonth ?? settings.balanceResetMonth;
    if (day == null || month == null) return;

    final maxMinutes = _pendingMaxMinutes ?? settings.carryOverMaxMinutes;
    final minMinutes = _pendingMinMinutes ?? settings.carryOverMinMinutes;
    if (mode == 'carryOver' && maxMinutes == null && minMinutes == null) return;

    unawaited(
      _persist(
        mode: mode,
        day: day,
        month: month,
        maxMinutes: maxMinutes,
        minMinutes: minMinutes,
      ),
    );
  }

  Future<void> _persist({
    required String mode,
    required int day,
    required int month,
    int? maxMinutes,
    int? minMinutes,
  }) {
    return guardedWrite(() async {
      final writes = await ref.read(syncedWritesProvider.future);
      await writes.updateAppSettings(
        balanceResetMode: mode,
        balanceResetDay: Value(day),
        balanceResetMonth: Value(month),
        carryOverMaxMinutes: Value(maxMinutes),
        carryOverMinMinutes: Value(minMinutes),
      );
      if (mounted) _clearPending();
    });
  }

  /// "No cutoff" is the only mode that is complete on its own, so it is
  /// written straight away and clears the stale cutoff and bounds rather
  /// than leaving them around for a later mode switch to pick back up.
  Future<void> _persistNone() {
    return guardedWrite(() async {
      final writes = await ref.read(syncedWritesProvider.future);
      await writes.updateAppSettings(
        balanceResetMode: 'none',
        balanceResetDay: const Value(null),
        balanceResetMonth: const Value(null),
        carryOverMaxMinutes: const Value(null),
        carryOverMinMinutes: const Value(null),
      );
      if (mounted) _clearPending();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final settings = ref.watch(appSettingsProvider).value;
    if (settings == null) return const Center(child: CircularProgressIndicator());

    final mode = _pendingMode ?? settings.balanceResetMode;
    final day = _pendingDay ?? settings.balanceResetDay;
    final month = _pendingMonth ?? settings.balanceResetMonth;
    final maxMinutes = _pendingMaxMinutes ?? settings.carryOverMaxMinutes;
    final minMinutes = _pendingMinMinutes ?? settings.carryOverMinMinutes;
    // Both halves, matching what _maybePersist demands: a month on its own
    // is not a cutoff, so the warning has to stay up until the day is
    // picked too.
    final cutoffChosen = day != null && month != null;
    final boundChosen = maxMinutes != null || minMinutes != null;
    final localeName = Localizations.localeOf(context).toLanguageTag();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.settingsBalanceTitle, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(l10n.settingsBalanceDescription, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 12),
        // A dropdown, not RadioListTile: that widget's groupValue/onChanged
        // API is deprecated in the Flutter version this repo pins, and
        // nothing in lib/ uses it. DropdownButtonFormField matches
        // general_settings_screen.dart, which is the house pattern here.
        DropdownButtonFormField<String>(
          key: const ValueKey('balanceMode'),
          initialValue: mode,
          isDense: true,
          // Each dropdown carries its own label: without one a screen
          // reader announces only the selected value ("January, dropdown")
          // and never says which of the three fields it belongs to.
          decoration: InputDecoration(labelText: l10n.settingsBalanceTitle, isDense: true),
          items: [
            DropdownMenuItem(value: 'none', child: Text(l10n.settingsBalanceModeNone)),
            DropdownMenuItem(value: 'resetToZero', child: Text(l10n.settingsBalanceModeReset)),
            DropdownMenuItem(value: 'carryOver', child: Text(l10n.settingsBalanceModeCarryOver)),
          ],
          onChanged: busy
              ? null
              : (selected) {
                  if (selected == null) return;
                  if (selected == 'none') {
                    unawaited(_persistNone());
                    return;
                  }
                  setState(() => _pendingMode = selected);
                  _maybePersist();
                },
        ),
        if (mode != 'none') ...[
          const SizedBox(height: 8),
          Text(l10n.settingsBalanceCutoff, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  key: const ValueKey('balanceCutoffMonth'),
                  initialValue: month,
                  decoration: InputDecoration(
                    labelText: l10n.settingsBalanceCutoffMonth,
                    isDense: true,
                  ),
                  items: [
                    for (var candidate = 1; candidate <= 12; candidate++)
                      DropdownMenuItem(
                        value: candidate,
                        child: Text(DateFormat.MMMM(localeName).format(DateTime(2024, candidate))),
                      ),
                  ],
                  onChanged: busy
                      ? null
                      : (selected) {
                          if (selected == null) return;
                          _applyChange(month: selected);
                        },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<int>(
                  key: const ValueKey('balanceCutoffDay'),
                  initialValue: day,
                  decoration: InputDecoration(
                    labelText: l10n.settingsBalanceCutoffDay,
                    isDense: true,
                  ),
                  items: [
                    for (var candidate = 1; candidate <= 31; candidate++)
                      DropdownMenuItem(value: candidate, child: Text('$candidate')),
                  ],
                  onChanged: busy
                      ? null
                      : (selected) {
                          if (selected == null) return;
                          _applyChange(day: selected);
                        },
                ),
              ),
            ],
          ),
          if (!cutoffChosen) ...[
            const SizedBox(height: 8),
            Text(
              l10n.settingsBalanceCutoffMissing,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
        if (mode == 'carryOver') ...[
          const SizedBox(height: 12),
          _CarryOverBoundsInput(
            maxMinutes: maxMinutes,
            minMinutes: minMinutes,
            onMaxChanged: (minutes) => _applyChange(maxMinutes: minutes),
            onMinChanged: (minutes) => _applyChange(minMinutes: minutes),
            onInvalidInput: _reportInvalidHours,
          ),
          if (cutoffChosen && !boundChosen) ...[
            const SizedBox(height: 8),
            Text(
              l10n.settingsBalanceBoundMissing,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ],
    );
  }
}

/// The two carry-over bound fields. Stateful (not built inline) because it
/// owns a [TextEditingController] per field: the parent rebuilds on every
/// emission of the settings stream, and a controller built fresh in
/// `build()` would reset the field text on each rebuild -- including while
/// the user is mid-keystroke in it. Same shape as `_WeeklyInputState` in
/// work_time_targets_editor.dart, down to committing on focus loss as well
/// as on submit.
class _CarryOverBoundsInput extends StatefulWidget {
  const _CarryOverBoundsInput({
    required this.maxMinutes,
    required this.minMinutes,
    required this.onMaxChanged,
    required this.onMinChanged,
    required this.onInvalidInput,
  });

  final int? maxMinutes;

  /// Stored as a negative number of minutes (or null); displayed to the
  /// user as its positive magnitude in hours.
  final int? minMinutes;

  /// Called with whole minutes: positive for the upper bound, negative for
  /// the lower one, matching how each is stored.
  final ValueChanged<int> onMaxChanged;
  final ValueChanged<int> onMinChanged;
  final VoidCallback onInvalidInput;

  @override
  State<_CarryOverBoundsInput> createState() => _CarryOverBoundsInputState();
}

class _CarryOverBoundsInputState extends State<_CarryOverBoundsInput> {
  late final TextEditingController _maxController = TextEditingController(
    text: minutesToHoursText(widget.maxMinutes ?? 0),
  );
  late final TextEditingController _minController = TextEditingController(
    text: minutesToHoursText((widget.minMinutes ?? 0).abs()),
  );

  /// What each bound was last saved as. Enter and the focus loss that
  /// follows it are two commit paths over one value, and neither the
  /// settings stream nor the parent's pending state has necessarily come
  /// back round between them -- so the incoming [widget] values alone
  /// cannot tell the second commit that the first already happened.
  late int? _committedMax = widget.maxMinutes;
  late int? _committedMin = widget.minMinutes;

  @override
  void didUpdateWidget(_CarryOverBoundsInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only push a stored value into its controller when that value
    // actually changed -- otherwise every rebuild (e.g. the other bound's
    // write settling) would reset the cursor and overwrite whatever the
    // user is currently typing.
    if (oldWidget.maxMinutes != widget.maxMinutes) {
      _maxController.text = minutesToHoursText(widget.maxMinutes ?? 0);
      _committedMax = widget.maxMinutes;
    }
    if (oldWidget.minMinutes != widget.minMinutes) {
      _minController.text = minutesToHoursText((widget.minMinutes ?? 0).abs());
      _committedMin = widget.minMinutes;
    }
  }

  @override
  void dispose() {
    _maxController.dispose();
    _minController.dispose();
    super.dispose();
  }

  /// Parses a bound field into a non-negative magnitude in minutes, or
  /// null when there is nothing to commit. Empty text is left alone (an
  /// unset bound renders as an empty field, so leaving one untouched must
  /// not write anything); anything else that is not a non-negative number
  /// is reported to the user rather than dropped, which is what used to
  /// happen to a typo here.
  int? _magnitudeOf(TextEditingController controller) {
    final text = controller.text.trim();
    if (text.isEmpty) return null;
    final minutes = hoursTextToMinutes(text);
    if (minutes == null || minutes < 0) {
      widget.onInvalidInput();
      return null;
    }
    return minutes;
  }

  void _commitMax() {
    final minutes = _magnitudeOf(_maxController);
    if (minutes == null || minutes == _committedMax) return;
    _committedMax = minutes;
    widget.onMaxChanged(minutes);
  }

  void _commitMin() {
    final minutes = _magnitudeOf(_minController);
    if (minutes == null || -minutes == _committedMin) return;
    _committedMin = -minutes;
    widget.onMinChanged(-minutes);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CommitOnFocusLoss(
          onCommit: _commitMax,
          child: TextField(
            key: const ValueKey('carryOverMax'),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            controller: _maxController,
            decoration: InputDecoration(labelText: l10n.settingsBalanceCarryOverMax, isDense: true),
            onSubmitted: (_) => _commitMax(),
          ),
        ),
        const SizedBox(height: 8),
        CommitOnFocusLoss(
          onCommit: _commitMin,
          child: TextField(
            key: const ValueKey('carryOverMin'),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            controller: _minController,
            decoration: InputDecoration(labelText: l10n.settingsBalanceCarryOverMin, isDense: true),
            onSubmitted: (_) => _commitMin(),
          ),
        ),
      ],
    );
  }
}
