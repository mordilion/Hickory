import 'package:csv/csv.dart';

import '../../core/format/date_format.dart';
import '../../data/drift/database.dart';
import '../../data/drift/time_entry_extensions.dart';
import '../../l10n/app_localizations.dart';

/// One row per finished entry, in chronological order. Amounts follow the
/// same billable-project-with-hourly-rate rule as [totalsByProject]. Column
/// headers and the billable yes/no values follow [l10n] (callers without a
/// BuildContext can use `lookupAppLocalizations`).
String entriesToCsv(
  List<TimeEntry> entries,
  List<Project> projects, {
  required AppLocalizations l10n,
  DateFormatStyle dateFormatStyle = defaultDateFormatStyle,
  TimeFormatStyle timeFormatStyle = defaultTimeFormatStyle,
}) {
  final projectsById = {for (final p in projects) p.id: p};
  final rows = <List<dynamic>>[
    [
      l10n.csvHeaderDate,
      l10n.csvHeaderStart,
      l10n.csvHeaderEnd,
      l10n.csvHeaderDurationHours,
      l10n.csvHeaderProject,
      l10n.csvHeaderDescription,
      l10n.csvHeaderBillable,
      l10n.csvHeaderAmount,
      l10n.csvHeaderCurrency,
    ],
  ];

  for (final entry in entries) {
    final endAt = entry.endAt;
    if (endAt == null) continue;
    final project = entry.projectId == null ? null : projectsById[entry.projectId];
    final duration = entry.workedDuration;
    final hours = duration.inMinutes / 60;
    final billable = project?.billable ?? false;
    final rateCents = project?.hourlyRateCents;
    final amount = (billable && rateCents != null) ? (rateCents * hours / 100) : null;

    rows.add([
      formatDate(entry.startAt, dateFormatStyle),
      formatTime(entry.startAt, timeFormatStyle),
      formatTime(endAt, timeFormatStyle),
      hours.toStringAsFixed(2),
      project?.name ?? '',
      entry.description ?? '',
      billable ? l10n.csvYes : l10n.csvNo,
      amount?.toStringAsFixed(2) ?? '',
      project?.currency ?? '',
    ]);
  }

  return const CsvEncoder().convert(rows);
}
