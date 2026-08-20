import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/data/drift/database.dart';
import 'package:hickory/data/drift/tables/jira_worklogs_table.dart';
import 'package:hickory/data/drift/tables/personio_attendances_table.dart';
import 'package:hickory/features/sync/failed_pushes.dart';

TimeEntry _entry({required String id, required DateTime startAt}) => TimeEntry(
  id: id,
  projectId: null,
  description: 'Entry $id',
  startAt: startAt,
  endAt: startAt.add(const Duration(hours: 1)),
  pausedAt: null,
  totalPausedSeconds: 0,
  billableOverride: null,
  source: 'manual',
  deviceId: 'device-1',
  jiraTicketKey: null,
  createdAt: DateTime.utc(2026, 1, 1),
  updatedAt: DateTime.utc(2026, 1, 1),
);

JiraWorklogRow _worklog({required String id, required String status, String? lastError}) =>
    JiraWorklogRow(
      id: id,
      syncedTicketKey: null,
      jiraWorklogId: null,
      status: status,
      lastError: lastError,
      syncedAt: null,
    );

PersonioAttendanceRow _attendance({
  required String id,
  required String status,
  String? lastError,
}) => PersonioAttendanceRow(
  id: id,
  personioAttendanceId: null,
  status: status,
  lastError: lastError,
  syncedAt: null,
);

void main() {
  test('pairs each failed entry with its stored error', () {
    final entry = _entry(id: '1', startAt: DateTime(2026, 8, 20, 9));

    final failed = failedPushes([entry], const {'1': 'Issue does not exist'});

    expect(failed, hasLength(1));
    expect(failed.single.entry.id, '1');
    expect(failed.single.error, 'Issue does not exist');
  });

  test('leaves out entries whose push did not fail', () {
    final failing = _entry(id: '1', startAt: DateTime(2026, 8, 20, 9));
    final fine = _entry(id: '2', startAt: DateTime(2026, 8, 20, 11));

    final failed = failedPushes([failing, fine], const {'1': 'Boom'});

    expect(failed.map((f) => f.entry.id), ['1']);
  });

  test('keeps a failure whose message was never stored', () {
    final entry = _entry(id: '1', startAt: DateTime(2026, 8, 20, 9));

    final failed = failedPushes([entry], const {'1': null});

    expect(failed.single.error, isNull);
  });

  test('drops a failure whose entry no longer exists locally', () {
    // The tracking row deliberately outlives its entry so a delete can still
    // be pushed; there is nothing to show for it in a list of entries.
    final failed = failedPushes(const [], const {'gone': 'Boom'});

    expect(failed, isEmpty);
  });

  test('orders the newest entry first', () {
    final older = _entry(id: 'older', startAt: DateTime(2026, 8, 18, 9));
    final newer = _entry(id: 'newer', startAt: DateTime(2026, 8, 20, 9));

    final failed = failedPushes([older, newer], const {'older': 'a', 'newer': 'b'});

    expect(failed.map((f) => f.entry.id), ['newer', 'older']);
  });

  group('jiraFailures', () {
    test('keeps only the rows that failed, with their message', () {
      final failures = jiraFailures({
        'ok': _worklog(id: 'ok', status: JiraWorklogStatus.synced),
        'bad': _worklog(id: 'bad', status: JiraWorklogStatus.error, lastError: 'Boom'),
      });

      expect(failures, {'bad': 'Boom'});
    });

    test('leaves out a pending delete that failed', () {
      // A failed delete keeps status pendingDelete so the whole delete
      // retries; its entry is usually gone locally, so there is nothing to
      // list. It stays out of the user-facing list on purpose.
      final failures = jiraFailures({
        'gone': _worklog(
          id: 'gone',
          status: JiraWorklogStatus.pendingDelete,
          lastError: 'Boom',
        ),
      });

      expect(failures, isEmpty);
    });
  });

  group('personioFailures', () {
    test('keeps only the rows that failed, with their message', () {
      final failures = personioFailures({
        'ok': _attendance(id: 'ok', status: PersonioAttendanceStatus.synced),
        'bad': _attendance(
          id: 'bad',
          status: PersonioAttendanceStatus.error,
          lastError: 'Overlaps',
        ),
      });

      expect(failures, {'bad': 'Overlaps'});
    });

    test('leaves out a pending delete that failed', () {
      final failures = personioFailures({
        'gone': _attendance(
          id: 'gone',
          status: PersonioAttendanceStatus.pendingDelete,
          lastError: 'Boom',
        ),
      });

      expect(failures, isEmpty);
    });
  });
}
