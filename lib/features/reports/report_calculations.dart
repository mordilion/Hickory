import '../../data/drift/database.dart';
import '../../data/drift/time_entry_extensions.dart';

/// Pure calculation, no DB/Flutter dependency beyond the drift row types —
/// straightforward to unit test with plain in-memory lists.
class ProjectTotal {
  const ProjectTotal({
    required this.projectId,
    required this.projectName,
    required this.duration,
    required this.billable,
    this.amountCents,
    this.currency,
  });

  final String? projectId;
  final String projectName;
  final Duration duration;
  final bool billable;

  /// Rounded cents; null if the project isn't billable or has no rate set.
  final int? amountCents;
  final String? currency;
}

/// Sums finished entries' durations by project (entries with no project are
/// grouped under a null key, named [noProjectLabel] — pass the localized
/// text; the default keeps today's German for callers that don't care),
/// computing a billable amount wherever the project is billable and has an
/// hourly rate. Sorted by duration, longest first.
List<ProjectTotal> totalsByProject(
  List<TimeEntry> entries,
  List<Project> projects, {
  String noProjectLabel = 'Kein Projekt',
}) {
  final projectsById = {for (final p in projects) p.id: p};
  final durationByProject = <String?, Duration>{};

  for (final entry in entries) {
    if (entry.endAt == null) continue;
    final duration = entry.workedDuration;
    durationByProject.update(
      entry.projectId,
      (existing) => existing + duration,
      ifAbsent: () => duration,
    );
  }

  final totals = <ProjectTotal>[];
  durationByProject.forEach((projectId, duration) {
    final project = projectId == null ? null : projectsById[projectId];
    final billable = project?.billable ?? false;
    final rateCents = project?.hourlyRateCents;
    final amountCents =
        (billable && rateCents != null) ? (rateCents * duration.inMinutes / 60).round() : null;
    totals.add(
      ProjectTotal(
        projectId: projectId,
        projectName: project?.name ?? noProjectLabel,
        duration: duration,
        billable: billable,
        amountCents: amountCents,
        currency: project?.currency,
      ),
    );
  });

  totals.sort((a, b) => b.duration.compareTo(a.duration));
  return totals;
}

/// Total duration per calendar day (local time).
Map<DateTime, Duration> totalsByDay(List<TimeEntry> entries) {
  final totals = <DateTime, Duration>{};
  for (final entry in entries) {
    if (entry.endAt == null) continue;
    final local = entry.startAt.toLocal();
    final day = DateTime(local.year, local.month, local.day);
    final duration = entry.workedDuration;
    totals.update(day, (existing) => existing + duration, ifAbsent: () => duration);
  }
  return totals;
}
