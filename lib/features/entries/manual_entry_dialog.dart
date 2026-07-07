import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/device_id_provider.dart';
import '../../core/di/sync_providers.dart';
import '../../data/drift/database.dart';
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

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _descriptionController = TextEditingController(text: existing?.description ?? '');
    _startAt = existing?.startAt.toLocal() ?? DateTime.now().subtract(const Duration(hours: 1));
    _endAt = existing?.endAt?.toLocal() ?? DateTime.now();
    _projectId = existing?.projectId;
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickDateTime({required bool isStart}) async {
    final initial = isStart ? _startAt : _endAt;
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null) return;
    final combined = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    setState(() {
      if (isStart) {
        _startAt = combined;
      } else {
        _endAt = combined;
      }
    });
  }

  Future<void> _save() async {
    if (_endAt.isBefore(_startAt)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ende muss nach dem Start liegen.')),
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
      );
    } else {
      await writes.updateEntry(
        existing.id,
        startAt: Value(_startAt.toUtc()),
        endAt: Value(_endAt.toUtc()),
        projectId: Value(_projectId),
        description: Value(description),
      );
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final projectsAsync = ref.watch(activeProjectsProvider);

    return AlertDialog(
      title: Text(widget.existing == null ? 'Manueller Eintrag' : 'Eintrag bearbeiten'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _descriptionController,
              decoration: const InputDecoration(labelText: 'Beschreibung'),
            ),
            const SizedBox(height: 12),
            projectsAsync.when(
              data: (projects) => DropdownButtonFormField<String?>(
                initialValue: _projectId,
                decoration: const InputDecoration(labelText: 'Projekt'),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('Kein Projekt')),
                  ...projects.map(
                    (p) => DropdownMenuItem<String?>(value: p.id, child: Text(p.name)),
                  ),
                ],
                onChanged: (value) => setState(() => _projectId = value),
              ),
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => Text('Fehler: $e'),
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Start'),
              subtitle: Text(_startAt.toString()),
              onTap: () => _pickDateTime(isStart: true),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Ende'),
              subtitle: Text(_endAt.toString()),
              onTap: () => _pickDateTime(isStart: false),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        FilledButton(onPressed: _save, child: const Text('Speichern')),
      ],
    );
  }
}
