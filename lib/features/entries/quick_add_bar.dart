import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/app_settings_provider.dart';
import '../../core/di/device_id_provider.dart';
import '../../core/di/sync_providers.dart';
import '../../core/format/date_format.dart';
import '../../core/format/quick_add_durations.dart';
import '../../core/theme/hickory_colors.dart';
import '../../core/widgets/gradient_buttons.dart';
import '../../l10n/app_localizations.dart';
import '../jira/widgets/jira_ticket_field.dart';
import '../projects/project_form_dialog.dart';
import '../projects/projects_providers.dart';
import 'entry_time_range.dart';

/// Pinned above [EntriesList] on the Timer tab; creates manual entries for
/// any day in as few taps as possible via inline start/end date+time
/// buttons plus duration chips. Replaces the old FAB. See
/// docs/superpowers/specs/2026-08-03-quick-entry-redesign-design.md.
class QuickAddBar extends ConsumerStatefulWidget {
  const QuickAddBar({super.key});

  @override
  ConsumerState<QuickAddBar> createState() => _QuickAddBarState();
}

class _QuickAddBarState extends ConsumerState<QuickAddBar> {
  final _descriptionController = TextEditingController();
  String? _projectId;
  String? _jiraTicketKey;
  late DateTime _startAt;
  late DateTime _endAt;
  Duration _lastAppliedDuration = const Duration(minutes: 30);

  /// True once the user has explicitly picked a duration chip or nudged a
  /// date or time button since the last reset. While false, [_startAt]/
  /// [_endAt] are a stale snapshot from whenever the bar last reset (e.g.
  /// hours ago on a desktop app left open) rather than the live default —
  /// [_displayStartAt]/[_displayEndAt] recompute against "now" instead of
  /// trusting them, and [_submit] refreshes the stored values before writing.
  bool _rangeTouched = false;

  DateTime get _displayEndAt => _rangeTouched ? _endAt : DateTime.now();
  DateTime get _displayStartAt =>
      _rangeTouched ? _startAt : _displayEndAt.subtract(_lastAppliedDuration);

  @override
  void initState() {
    super.initState();
    _resetTimeRange(const Duration(minutes: 30));
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  void _resetTimeRange(Duration duration) {
    final now = DateTime.now();
    _endAt = now;
    _startAt = now.subtract(duration);
    _lastAppliedDuration = duration;
  }

  void _applyDuration(int minutes) {
    setState(() {
      _resetTimeRange(Duration(minutes: minutes));
      _rangeTouched = true;
    });
  }

  Future<void> _pickTime({required bool isStart}) async {
    final initial = isStart ? _displayStartAt : _displayEndAt;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null || !mounted) return;
    final combined = DateTime(
      initial.year,
      initial.month,
      initial.day,
      time.hour,
      time.minute,
    );
    final freshStart = _displayStartAt;
    final freshEnd = _displayEndAt;
    setState(() {
      _rangeTouched = true;
      if (!isStart) {
        _startAt = freshStart;
        _endAt = combined;
        return;
      }
      _startAt = combined;
      _endAt = endFollowingStart(
        previousStartAt: freshStart,
        previousEndAt: freshEnd,
        newStartAt: combined,
      );
    });
  }

  Future<void> _pickDate({required bool isStart}) async {
    final initial = isStart ? _displayStartAt : _displayEndAt;
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (date == null || !mounted) return;
    final combined = DateTime(
      date.year,
      date.month,
      date.day,
      initial.hour,
      initial.minute,
    );
    final freshStart = _displayStartAt;
    final freshEnd = _displayEndAt;
    setState(() {
      _rangeTouched = true;
      if (!isStart) {
        _startAt = freshStart;
        _endAt = combined;
        return;
      }
      _startAt = combined;
      _endAt = endFollowingStart(
        previousStartAt: freshStart,
        previousEndAt: freshEnd,
        newStartAt: combined,
      );
    });
  }

  Future<void> _submit() async {
    if (!_rangeTouched) _resetTimeRange(_lastAppliedDuration);
    if (_endAt.isBefore(_startAt)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context).entriesEndBeforeStartError,
          ),
        ),
      );
      return;
    }
    final deviceId = await ref.read(deviceIdProvider.future);
    final writes = await ref.read(syncedWritesProvider.future);
    final descriptionText = _descriptionController.text.trim();
    final description = descriptionText.isEmpty ? null : descriptionText;
    await writes.createManualEntry(
      deviceId: deviceId,
      startAt: _startAt,
      endAt: _endAt,
      projectId: _projectId,
      description: description,
      jiraTicketKey: _jiraTicketKey,
    );
    if (!mounted) return;
    _descriptionController.clear();
    setState(() {
      _resetTimeRange(const Duration(minutes: 30));
      _rangeTouched = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final projectsAsync = ref.watch(activeProjectsProvider);
    final settings = ref.watch(appSettingsProvider).value;
    final dateStyle = settings.dateStyle;
    final timeStyle = settings.timeStyle;
    final languageCode = Localizations.localeOf(context).languageCode;
    final durations = settings.quickAddDurations;
    final tokens = HickoryColors.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _descriptionController,
              decoration: InputDecoration(
                labelText: l10n.entriesDescriptionLabel,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: projectsAsync.when(
                    data: (projects) => DropdownButtonFormField<String?>(
                      initialValue: _projectId,
                      decoration: InputDecoration(
                        labelText: l10n.entriesProjectLabel,
                      ),
                      items: [
                        DropdownMenuItem<String?>(
                          value: null,
                          child: Text(l10n.commonNoProject),
                        ),
                        ...projects.map(
                          (p) => DropdownMenuItem<String?>(
                            value: p.id,
                            child: Text(p.name),
                          ),
                        ),
                      ],
                      onChanged: (value) => setState(() => _projectId = value),
                    ),
                    loading: () => const LinearProgressIndicator(),
                    error: (e, _) => Text(l10n.entriesError(e.toString())),
                  ),
                ),
                IconButton(
                  tooltip: l10n.timerNewProjectTooltip,
                  onPressed: () => showProjectFormDialog(context, ref),
                  icon: const Icon(Icons.add_box_outlined),
                ),
              ],
            ),
            const SizedBox(height: 12),
            JiraTicketField(
              initialValue: _jiraTicketKey,
              onChanged: (value) => setState(() => _jiraTicketKey = value),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final minutes in durations)
                  ActionChip(
                    label: Text(l10n.quickAddDurationChipLabel(minutes)),
                    onPressed: () => _applyDuration(minutes),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                TextButton(
                  onPressed: () => _pickDate(isStart: true),
                  child: Text(
                    formatDate(_displayStartAt, dateStyle, languageCode),
                  ),
                ),
                TextButton(
                  onPressed: () => _pickTime(isStart: true),
                  child: Text(formatTime(_displayStartAt, timeStyle)),
                ),
                const Text('–'),
                TextButton(
                  onPressed: () => _pickDate(isStart: false),
                  child: Text(
                    formatDate(_displayEndAt, dateStyle, languageCode),
                  ),
                ),
                TextButton(
                  onPressed: () => _pickTime(isStart: false),
                  child: Text(formatTime(_displayEndAt, timeStyle)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Same GradientPillButton treatment as the Timer card's Start
            // button (see TimerScreen): the two are the same commitment in
            // their respective modes, so they get the same full-width pill
            // rather than the small round icon button this used to be.
            GradientPillButton(
              label: l10n.quickAddSubmitLabel,
              icon: Icons.add,
              gradient: tokens.primaryGradient,
              foregroundColor: tokens.onPrimaryGradient,
              onPressed: _submit,
            ),
          ],
        ),
      ),
    );
  }
}
