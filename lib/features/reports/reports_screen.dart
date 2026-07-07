import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format/duration_format.dart';
import '../../data/drift/database.dart';
import 'csv_export.dart';
import 'report_calculations.dart';
import 'reports_providers.dart';

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  ReportRangePreset? _selectedPreset = ReportRangePreset.thisMonth;
  String? _exportStatus;

  void _selectPreset(ReportRangePreset preset) {
    setState(() => _selectedPreset = preset);
    ref.read(reportRangeProvider.notifier).state = rangeForPreset(preset);
  }

  Future<void> _selectCustomRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 1),
      initialDateRange: ref.read(reportRangeProvider),
    );
    if (picked == null) return;
    setState(() => _selectedPreset = null);
    // showDateRangePicker's end date is inclusive-at-midnight; our range end
    // is exclusive, so push it one day forward to include the whole day.
    ref.read(reportRangeProvider.notifier).state = DateTimeRange(
      start: DateTime(picked.start.year, picked.start.month, picked.start.day),
      end: DateTime(
        picked.end.year,
        picked.end.month,
        picked.end.day,
      ).add(const Duration(days: 1)),
    );
  }

  Future<void> _exportCsv(List<TimeEntry> entries, List<Project> projects) async {
    final csv = entriesToCsv(entries, projects);
    final path = await FilePicker.saveFile(
      dialogTitle: 'CSV exportieren',
      fileName: 'hickory-export.csv',
      type: FileType.custom,
      allowedExtensions: ['csv'],
      bytes: Uint8List.fromList(utf8.encode(csv)),
    );
    if (!mounted) return;
    setState(() => _exportStatus = path == null ? null : 'Exportiert nach: $path');
  }

  @override
  Widget build(BuildContext context) {
    final entriesAsync = ref.watch(reportEntriesProvider);
    final projectsAsync = ref.watch(reportProjectsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Reports')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('Diese Woche'),
                  selected: _selectedPreset == ReportRangePreset.thisWeek,
                  onSelected: (_) => _selectPreset(ReportRangePreset.thisWeek),
                ),
                ChoiceChip(
                  label: const Text('Dieser Monat'),
                  selected: _selectedPreset == ReportRangePreset.thisMonth,
                  onSelected: (_) => _selectPreset(ReportRangePreset.thisMonth),
                ),
                ChoiceChip(
                  label: const Text('Letzte 30 Tage'),
                  selected: _selectedPreset == ReportRangePreset.last30Days,
                  onSelected: (_) => _selectPreset(ReportRangePreset.last30Days),
                ),
                ChoiceChip(
                  label: const Text('Alle'),
                  selected: _selectedPreset == ReportRangePreset.all,
                  onSelected: (_) => _selectPreset(ReportRangePreset.all),
                ),
                ActionChip(
                  label: const Text('Benutzerdefiniert…'),
                  onPressed: _selectCustomRange,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: entriesAsync.when(
                data: (entries) => projectsAsync.when(
                  data: (projects) => _ReportBody(
                    entries: entries,
                    projects: projects,
                    onExport: () => _exportCsv(entries, projects),
                  ),
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Center(child: Text('Fehler: $e')),
                ),
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Fehler: $e')),
              ),
            ),
            if (_exportStatus != null) ...[
              const SizedBox(height: 8),
              Text(_exportStatus!, style: Theme.of(context).textTheme.bodySmall),
            ],
          ],
        ),
      ),
    );
  }
}

class _ReportBody extends StatelessWidget {
  const _ReportBody({required this.entries, required this.projects, required this.onExport});

  final List<TimeEntry> entries;
  final List<Project> projects;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    final totals = totalsByProject(entries, projects);
    final totalDuration = totals.fold<Duration>(Duration.zero, (sum, t) => sum + t.duration);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Gesamt: ${formatDuration(totalDuration)}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            FilledButton.icon(
              onPressed: entries.isEmpty ? null : onExport,
              icon: const Icon(Icons.download),
              label: const Text('CSV exportieren'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: totals.isEmpty
              ? const Center(child: Text('Keine Einträge in diesem Zeitraum.'))
              : ListView.builder(
                  itemCount: totals.length,
                  itemBuilder: (context, index) {
                    final total = totals[index];
                    final amount = total.amountCents == null
                        ? null
                        : '${(total.amountCents! / 100).toStringAsFixed(2)} ${total.currency ?? ''}';
                    return ListTile(
                      title: Text(total.projectName),
                      subtitle: amount == null ? null : Text(amount),
                      trailing: Text(formatDuration(total.duration)),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
