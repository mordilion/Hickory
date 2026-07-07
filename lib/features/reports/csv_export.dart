import 'package:csv/csv.dart';

import '../../core/format/date_format.dart';
import '../../data/drift/database.dart';

/// One row per finished entry, in chronological order. Amounts follow the
/// same billable-project-with-hourly-rate rule as [totalsByProject].
String entriesToCsv(List<TimeEntry> entries, List<Project> projects) {
  final projectsById = {for (final p in projects) p.id: p};
  final rows = <List<dynamic>>[
    [
      'Datum',
      'Start',
      'Ende',
      'Dauer (Std)',
      'Projekt',
      'Beschreibung',
      'Abrechenbar',
      'Betrag',
      'Währung',
    ],
  ];

  for (final entry in entries) {
    final endAt = entry.endAt;
    if (endAt == null) continue;
    final project = entry.projectId == null ? null : projectsById[entry.projectId];
    final duration = endAt.difference(entry.startAt);
    final hours = duration.inMinutes / 60;
    final billable = project?.billable ?? false;
    final rateCents = project?.hourlyRateCents;
    final amount = (billable && rateCents != null) ? (rateCents * hours / 100) : null;

    rows.add([
      formatDate(entry.startAt),
      formatTime(entry.startAt),
      formatTime(endAt),
      hours.toStringAsFixed(2),
      project?.name ?? '',
      entry.description ?? '',
      billable ? 'ja' : 'nein',
      amount?.toStringAsFixed(2) ?? '',
      project?.currency ?? '',
    ]);
  }

  return const CsvEncoder().convert(rows);
}
