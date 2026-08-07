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
import 'report_filter_dialog.dart';
import 'report_view_controller.dart';
import 'report_view_state.dart';
import 'reports_providers.dart';

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  String? _exportStatus;

  Future<void> _selectCustomRange(DateTimeRange currentRange) async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 1),
      initialDateRange: currentRange,
    );
    if (picked == null) return;
    // showDateRangePicker's end date is inclusive-at-midnight; our range end
    // is exclusive, so push it one day forward to include the whole day.
    final range = DateTimeRange(
      start: DateTime(picked.start.year, picked.start.month, picked.start.day),
      end: DateTime(
        picked.end.year,
        picked.end.month,
        picked.end.day,
      ).add(const Duration(days: 1)),
    );
    await ref.read(reportViewControllerProvider.notifier).setCustomRange(range);
  }

  Future<void> _exportCsv(
    List<TimeEntry> entries,
    List<Project> projects,
  ) async {
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
    setState(
      () => _exportStatus = path == null ? null : l10n.reportsExportedTo(path),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final viewAsync = ref.watch(reportViewControllerProvider);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.reportsTitle,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 12),
          Expanded(
            child: viewAsync.when(
              data: (viewState) => _ReportRangeAndBody(
                viewState: viewState,
                exportStatus: _exportStatus,
                onSelectCustomRange: () => _selectCustomRange(viewState.range),
                onExport: _exportCsv,
              ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) =>
                  Center(child: Text(l10n.reportsError(e.toString()))),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReportRangeAndBody extends ConsumerWidget {
  const _ReportRangeAndBody({
    required this.viewState,
    required this.exportStatus,
    required this.onSelectCustomRange,
    required this.onExport,
  });

  final ReportViewState viewState;
  final String? exportStatus;
  final VoidCallback onSelectCustomRange;
  final Future<void> Function(List<TimeEntry> entries, List<Project> projects)
  onExport;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final tokens = HickoryColors.of(context);
    final entriesAsync = ref.watch(reportEntriesProvider(viewState.range));
    final projectsAsync = ref.watch(reportProjectsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _presetChip(
                    context,
                    ref,
                    l10n.reportsToday,
                    ReportRangePreset.today,
                    tokens,
                  ),
                  _presetChip(
                    context,
                    ref,
                    l10n.reportsYesterday,
                    ReportRangePreset.yesterday,
                    tokens,
                  ),
                  _presetChip(
                    context,
                    ref,
                    l10n.reportsThisWeek,
                    ReportRangePreset.thisWeek,
                    tokens,
                  ),
                  _presetChip(
                    context,
                    ref,
                    l10n.reportsThisMonth,
                    ReportRangePreset.thisMonth,
                    tokens,
                  ),
                  _presetChip(
                    context,
                    ref,
                    l10n.reportsLast30Days,
                    ReportRangePreset.last30Days,
                    tokens,
                  ),
                  _presetChip(
                    context,
                    ref,
                    l10n.reportsAll,
                    ReportRangePreset.all,
                    tokens,
                  ),
                  ActionChip(
                    label: Text(l10n.reportsCustomRange),
                    onPressed: onSelectCustomRange,
                  ),
                ],
              ),
            ),
            Badge(
              label: Text('${viewState.activeFilterCount}'),
              isLabelVisible: viewState.activeFilterCount > 0,
              child: IconButton(
                icon: const Icon(Icons.filter_list),
                tooltip: l10n.reportsFilterTooltip,
                onPressed: () {
                  final projects = projectsAsync.value;
                  if (projects == null) return;
                  showDialog<void>(
                    context: context,
                    builder: (_) => ReportFilterDialog(projects: projects),
                  );
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Expanded(
          child: entriesAsync.when(
            data: (entries) => projectsAsync.when(
              data: (projects) {
                final filtered = filterEntries(
                  entries,
                  projects,
                  projectIds: viewState.projectIds,
                  billableFilter: viewState.billableFilter,
                );
                return _ReportBody(
                  entries: filtered,
                  projects: projects,
                  hasActiveFilters: viewState.activeFilterCount > 0,
                  onExport: () => onExport(filtered, projects),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) =>
                  Center(child: Text(l10n.reportsError(e.toString()))),
            ),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) =>
                Center(child: Text(l10n.reportsError(e.toString()))),
          ),
        ),
        if (exportStatus != null) ...[
          const SizedBox(height: 8),
          Text(exportStatus!, style: Theme.of(context).textTheme.bodySmall),
        ],
      ],
    );
  }

  Widget _presetChip(
    BuildContext context,
    WidgetRef ref,
    String label,
    ReportRangePreset preset,
    HickoryColors tokens,
  ) {
    final selected = viewState.preset == preset;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      selectedColor: tokens.navActiveIcon.withValues(alpha: 0.22),
      onSelected: (_) =>
          ref.read(reportViewControllerProvider.notifier).setPreset(preset),
    );
  }
}

class _ReportBody extends StatelessWidget {
  const _ReportBody({
    required this.entries,
    required this.projects,
    required this.hasActiveFilters,
    required this.onExport,
  });

  final List<TimeEntry> entries;
  final List<Project> projects;
  final bool hasActiveFilters;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final totals = totalsByProject(
      entries,
      projects,
      noProjectLabel: l10n.commonNoProject,
    );
    final totalDuration = totals.fold<Duration>(
      Duration.zero,
      (sum, t) => sum + t.duration,
    );

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
              ? Center(
                  child: Text(
                    hasActiveFilters
                        ? l10n.reportsEmptyFiltered
                        : l10n.reportsEmptyRange,
                  ),
                )
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
