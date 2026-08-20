import '../../data/drift/database.dart';
import '../../data/drift/tables/jira_worklogs_table.dart';
import '../../data/drift/tables/personio_attendances_table.dart';

/// One entry whose last push to Jira or Personio failed, with the message
/// that push stored. [error] is null when the row carries none — an older
/// row, or state received from another device before the message.
typedef FailedPush = ({TimeEntry entry, String? error});

/// Joins [entries] with the failures a sync service recorded, newest entry
/// first. [errorsByEntryId] holds one key per *failed* entry (its stored
/// message, or null), which keeps this function independent of Jira's and
/// Personio's separate row types.
///
/// A failure without a matching entry is dropped: a tracking row outlives
/// its entry on purpose, so it can still push the delete, and there is
/// nothing to show the user for one.
List<FailedPush> failedPushes(
  List<TimeEntry> entries,
  Map<String, String?> errorsByEntryId,
) {
  final failed = [
    for (final entry in entries)
      if (errorsByEntryId.containsKey(entry.id))
        (entry: entry, error: errorsByEntryId[entry.id]),
  ];
  failed.sort((a, b) => b.entry.startAt.compareTo(a.entry.startAt));
  return failed;
}

/// The stored message per entry whose last Jira push failed, ready for
/// [failedPushes]. A row on `pendingDelete` is left out even when it carries
/// an error: a failed delete keeps that status so the delete retries, and its
/// entry is normally gone locally, so there is nothing to show for it.
Map<String, String?> jiraFailures(Map<String, JiraWorklogRow> worklogs) => {
  for (final worklog in worklogs.values)
    if (worklog.status == JiraWorklogStatus.error) worklog.id: worklog.lastError,
};

/// The Personio counterpart of [jiraFailures].
Map<String, String?> personioFailures(
  Map<String, PersonioAttendanceRow> attendances,
) => {
  for (final attendance in attendances.values)
    if (attendance.status == PersonioAttendanceStatus.error)
      attendance.id: attendance.lastError,
};
