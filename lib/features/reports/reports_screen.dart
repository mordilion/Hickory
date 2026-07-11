import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/app_settings_provider.dart';
import '../../core/format/date_format.dart';
import '../../core/format/duration_format.dart';
import '../../core/theme/hickory_colors.dart';
import '../../data/drift/database.dart';
import '../../l10n/app_localizations.dart';
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
    final l10n = AppLocalizations.of(context);
    final settings = ref.read(appSettingsProvider).value;
    final csv = entriesToCsv(
      entries,
      projects,
      l10n: l10n,
      dateFormatStyle: settings.dateStyle,
      timeFormatStyle: settings.timeStyle,
    );
    final path = await FilePicker.saveFile(
      dialogTitle: l10n.reportsExportCsv,
      fileName: 'hickory-export.csv',
      type: FileType.custom,
      allowedExtensions: ['csv'],
      bytes: Uint8List.fromList(utf8.encode(csv)),
    );
    if (!mounted) return;
    setState(() => _exportStatus = path == null ? null : l10n.reportsExportedTo(path));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final entriesAsync = ref.watch(reportEntriesProvider);
    final projectsAsync = ref.watch(reportProjectsProvider);
    final tokens = HickoryColors.of(context);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.reportsTitle, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _presetChip(l10n.reportsThisWeek, ReportRangePreset.thisWeek, tokens),
              _presetChip(l10n.reportsThisMonth, ReportRangePreset.thisMonth, tokens),
              _presetChip(l10n.reportsLast30Days, ReportRangePreset.last30Days, tokens),
              _presetChip(l10n.reportsAll, ReportRangePreset.all, tokens),
              ActionChip(
                label: Text(l10n.reportsCustomRange),
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
                error: (e, _) => Center(child: Text(l10n.reportsError(e.toString()))),
              ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text(l10n.reportsError(e.toString()))),
            ),
          ),
          if (_exportStatus != null) ...[
            const SizedBox(height: 8),
            Text(_exportStatus!, style: Theme.of(context).textTheme.bodySmall),
          ],
        ],
      ),
    );
  }

  Widget _presetChip(String label, ReportRangePreset preset, HickoryColors tokens) {
    final selected = _selectedPreset == preset;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      selectedColor: tokens.navActiveIcon.withValues(alpha: 0.22),
      onSelected: (_) => _selectPreset(preset),
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
    final l10n = AppLocalizations.of(context);
    final totals = totalsByProject(entries, projects, noProjectLabel: l10n.commonNoProject);
    final totalDuration = totals.fold<Duration>(Duration.zero, (sum, t) => sum + t.duration);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              l10n.reportsTotal(formatDuration(totalDuration)),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            FilledButton.icon(
              onPressed: entries.isEmpty ? null : onExport,
              icon: const Icon(Icons.download),
              label: Text(l10n.reportsExportCsv),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: totals.isEmpty
              ? Center(child: Text(l10n.reportsEmptyRange))
              : ListView.builder(
                  itemCount: totals.length,
                  itemBuilder: (context, index) {
                    final total = totals[index];
                    final amount = total.amountCents == null
                        ? null
                        : '${(total.amountCents! / 100).toStringAsFixed(2)} ${total.currency ?? ''}';
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      shape: const StadiumBorder(),
                      child: ListTile(
                        shape: const StadiumBorder(),
                        title: Text(total.projectName),
                        subtitle: amount == null ? null : Text(amount),
                        trailing: Text(formatDuration(total.duration)),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
