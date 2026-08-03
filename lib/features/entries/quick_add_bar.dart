import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/app_settings_provider.dart';
import '../../core/di/device_id_provider.dart';
import '../../core/di/sync_providers.dart';
import '../../core/format/date_format.dart';
import '../../core/format/quick_add_durations.dart';
import '../../l10n/app_localizations.dart';
import '../jira/widgets/jira_ticket_field.dart';
import '../projects/projects_providers.dart';
import 'manual_entry_dialog.dart';

/// Pinned above [EntriesList] on the Timer tab; creates today's manual
/// entries in as few taps as possible (duration chips instead of the full
/// dialog's two date+time pickers). Replaces the old FAB — anything the bar
/// can't do (a different day, exact timestamps) is reached via its "more"
/// icon, which opens the existing full dialog prefilled with the bar's
/// current description/project. See
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
  bool _jiraExpanded = false;
  late DateTime _startAt;
  late DateTime _endAt;

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
  }

  void _applyDuration(int minutes) {
    setState(() => _resetTimeRange(Duration(minutes: minutes)));
  }

  Future<void> _pickTime({required bool isStart}) async {
    final initial = isStart ? _startAt : _endAt;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(initial));
    if (time == null || !mounted) return;
    final now = DateTime.now();
    final combined = DateTime(now.year, now.month, now.day, time.hour, time.minute);
    setState(() {
      if (isStart) {
        _startAt = combined;
      } else {
        _endAt = combined;
      }
    });
  }

  Future<void> _submit() async {
    if (_endAt.isBefore(_startAt)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).entriesEndBeforeStartError)),
      );
      return;
    }
    final deviceId = await ref.read(deviceIdProvider.future);
    final writes = await ref.read(syncedWritesProvider.future);
    final description = _descriptionController.text.trim().isEmpty
        ? null
        : _descriptionController.text.trim();
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
    setState(() => _resetTimeRange(const Duration(minutes: 30)));
  }

  void _openFullDialog() {
    final description = _descriptionController.text.trim();
    showManualEntryDialog(
      context,
      ref,
      initialDescription: description.isEmpty ? null : description,
      initialProjectId: _projectId,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final projectsAsync = ref.watch(activeProjectsProvider);
    final settings = ref.watch(appSettingsProvider).value;
    final timeStyle = settings.timeStyle;
    final durations = settings.quickAddDurations;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _descriptionController,
                    decoration: InputDecoration(labelText: l10n.entriesDescriptionLabel, isDense: true),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 140,
                  child: projectsAsync.when(
                    data: (projects) => DropdownButtonFormField<String?>(
                      initialValue: _projectId,
                      isDense: true,
                      isExpanded: true,
                      decoration: InputDecoration(labelText: l10n.entriesProjectLabel, isDense: true),
                      items: [
                        DropdownMenuItem<String?>(value: null, child: Text(l10n.commonNoProject)),
                        ...projects.map(
                          (p) => DropdownMenuItem<String?>(value: p.id, child: Text(p.name)),
                        ),
                      ],
                      onChanged: (value) => setState(() => _projectId = value),
                    ),
                    loading: () => const LinearProgressIndicator(),
                    error: (e, _) => Text(l10n.entriesError(e.toString())),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (final minutes in durations)
                  ActionChip(
                    label: Text(l10n.quickAddDurationChipLabel(minutes)),
                    onPressed: () => _applyDuration(minutes),
                  ),
                TextButton(
                  onPressed: () => _pickTime(isStart: true),
                  child: Text(formatTime(_startAt, timeStyle)),
                ),
                const Text('–'),
                TextButton(
                  onPressed: () => _pickTime(isStart: false),
                  child: Text(formatTime(_endAt, timeStyle)),
                ),
                IconButton(
                  tooltip: l10n.quickAddJiraTooltip,
                  onPressed: () => setState(() => _jiraExpanded = !_jiraExpanded),
                  icon: const Icon(Icons.confirmation_number_outlined),
                ),
                IconButton(
                  tooltip: l10n.quickAddMoreTooltip,
                  onPressed: _openFullDialog,
                  icon: const Icon(Icons.calendar_month_outlined),
                ),
                IconButton.filled(
                  tooltip: l10n.quickAddSubmitTooltip,
                  onPressed: _submit,
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
            if (_jiraExpanded) ...[
              const SizedBox(height: 8),
              JiraTicketField(
                initialValue: _jiraTicketKey,
                onChanged: (value) => setState(() => _jiraTicketKey = value),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
