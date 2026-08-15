import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/app_settings_provider.dart';
import '../../core/di/device_id_provider.dart';
import '../../core/di/sync_providers.dart';
import '../../core/format/date_format.dart';
import '../../data/drift/database.dart';
import '../../l10n/app_localizations.dart';
import '../jira/widgets/jira_ticket_field.dart';
import '../projects/projects_providers.dart';

Future<void> showManualEntryDialog(
  BuildContext context,
  WidgetRef ref, {
  TimeEntry? existing,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => _ManualEntryDialog(existing: existing),
  );
}

class _ManualEntryDialog extends ConsumerStatefulWidget {
  const _ManualEntryDialog({this.existing});

  final TimeEntry? existing;

  @override
  ConsumerState<_ManualEntryDialog> createState() => _ManualEntryDialogState();
}

class _ManualEntryDialogState extends ConsumerState<_ManualEntryDialog> {
  late final TextEditingController _descriptionController;
  late DateTime _startAt;
  late DateTime _endAt;
  String? _projectId;
  String? _jiraTicketKey;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _descriptionController = TextEditingController(
      text: existing?.description ?? '',
    );
    _startAt =
        existing?.startAt.toLocal() ??
        DateTime.now().subtract(const Duration(hours: 1));
    _endAt = existing?.endAt?.toLocal() ?? DateTime.now();
    _projectId = existing?.projectId;
    _jiraTicketKey = existing?.jiraTicketKey;
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickDate({required bool isStart}) async {
    final initial = isStart ? _startAt : _endAt;
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (date == null || !mounted) return;
    setState(() {
      final combined = DateTime(
        date.year,
        date.month,
        date.day,
        initial.hour,
        initial.minute,
      );
      if (isStart) {
        _startAt = combined;
      } else {
        _endAt = combined;
      }
    });
  }

  Future<void> _pickTime({required bool isStart}) async {
    final initial = isStart ? _startAt : _endAt;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null || !mounted) return;
    setState(() {
      final combined = DateTime(
        initial.year,
        initial.month,
        initial.day,
        time.hour,
        time.minute,
      );
      if (isStart) {
        _startAt = combined;
      } else {
        _endAt = combined;
      }
    });
  }

  Future<void> _delete() async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.entriesDeleteConfirmTitle),
        content: Text(l10n.entriesDeleteConfirmMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.commonDelete),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final writes = await ref.read(syncedWritesProvider.future);
    await writes.deleteEntry(widget.existing!.id);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _save() async {
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
    final writes = await ref.read(syncedWritesProvider.future);
    final description = _descriptionController.text.trim().isEmpty
        ? null
        : _descriptionController.text.trim();
    final existing = widget.existing;
    if (existing == null) {
      final deviceId = await ref.read(deviceIdProvider.future);
      await writes.createManualEntry(
        deviceId: deviceId,
        startAt: _startAt,
        endAt: _endAt,
        projectId: _projectId,
        description: description,
        jiraTicketKey: _jiraTicketKey,
      );
    } else {
      await writes.updateEntry(
        existing.id,
        startAt: Value(_startAt.toUtc()),
        endAt: Value(_endAt.toUtc()),
        projectId: Value(_projectId),
        description: Value(description),
        jiraTicketKey: Value(_jiraTicketKey),
      );
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final projectsAsync = ref.watch(activeProjectsProvider);
    final settings = ref.watch(appSettingsProvider).value;
    final dateStyle = settings.dateStyle;
    final timeStyle = settings.timeStyle;
    final languageCode = Localizations.localeOf(context).languageCode;

    return AlertDialog(
      title: Text(
        widget.existing == null
            ? l10n.entriesManualEntryTitle
            : l10n.entriesEditEntryTitle,
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _descriptionController,
              decoration: InputDecoration(
                labelText: l10n.entriesDescriptionLabel,
              ),
            ),
            const SizedBox(height: 12),
            projectsAsync.when(
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
            const SizedBox(height: 12),
            JiraTicketField(
              initialValue: _jiraTicketKey,
              onChanged: (value) => setState(() => _jiraTicketKey = value),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: Text(l10n.entriesStartLabel)),
                // Flexible + Wrap (rather than the buttons sitting directly
                // in the Row) lets the date/time pair drop to a second line
                // instead of forcing a hard RenderFlex overflow when a long
                // date format + verbose time format leave too little room
                // next to the label at a narrow dialog width.
                Flexible(
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      TextButton(
                        onPressed: () => _pickDate(isStart: true),
                        child: Text(
                          formatDate(_startAt, dateStyle, languageCode),
                        ),
                      ),
                      TextButton(
                        onPressed: () => _pickTime(isStart: true),
                        child: Text(formatTime(_startAt, timeStyle)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(child: Text(l10n.entriesEndLabel)),
                Flexible(
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      TextButton(
                        onPressed: () => _pickDate(isStart: false),
                        child: Text(
                          formatDate(_endAt, dateStyle, languageCode),
                        ),
                      ),
                      TextButton(
                        onPressed: () => _pickTime(isStart: false),
                        child: Text(formatTime(_endAt, timeStyle)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actions: [
        if (widget.existing != null)
          TextButton(
            onPressed: _delete,
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: Text(l10n.commonDelete),
          )
        else
          const SizedBox.shrink(),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.commonCancel),
            ),
            const SizedBox(width: 8),
            FilledButton(onPressed: _save, child: Text(l10n.commonSave)),
          ],
        ),
      ],
    );
  }
}
