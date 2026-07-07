import '../../data/drift/database.dart';

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
/// grouped under a null key / "Kein Projekt"), computing a billable amount
/// wherever the project is billable and has an hourly rate. Sorted by
/// duration, longest first.
List<ProjectTotal> totalsByProject(List<TimeEntry> entries, List<Project> projects) {
  final projectsById = {for (final p in projects) p.id: p};
  final durationByProject = <String?, Duration>{};

  for (final entry in entries) {
    final endAt = entry.endAt;
    if (endAt == null) continue;
    final duration = endAt.difference(entry.startAt);
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
        projectName: project?.name ?? 'Kein Projekt',
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
    final endAt = entry.endAt;
    if (endAt == null) continue;
    final local = entry.startAt.toLocal();
    final day = DateTime(local.year, local.month, local.day);
    final duration = endAt.difference(entry.startAt);
    totals.update(day, (existing) => existing + duration, ifAbsent: () => duration);
  }
  return totals;
}
