import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/data/drift/database.dart';
import 'package:hickory/data/sync/sync_log_writer.dart';
import 'package:hickory/data/sync/synced_writes.dart';
import 'package:hickory/features/jira/jira_client.dart';
import 'package:hickory/features/jira/jira_sync_service.dart';
import 'package:mocktail/mocktail.dart';

class MockJiraClient extends Mock implements JiraClient {}

void main() {
  late AppDatabase db;
  late SyncedWrites writes;
  late Directory syncRoot;
  late MockJiraClient client;
  late JiraSyncService service;

  setUpAll(() {
    registerFallbackValue(DateTime.utc(2026, 7, 7));
    registerFallbackValue(Duration.zero);
  });

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    syncRoot = Directory.systemTemp.createTempSync('hickory_jira_sync_test_');
    writes = SyncedWrites(
      db: db,
      logWriter: SyncLogWriter(syncRoot: syncRoot, deviceId: 'dev_a'),
    );
    client = MockJiraClient();
    service = JiraSyncService(db: db, client: client, writes: writes);
  });

  tearDown(() async {
    await db.close();
    if (syncRoot.existsSync()) syncRoot.deleteSync(recursive: true);
  });

  test('creates a worklog for a finished entry with a ticket and no tracking row yet', () async {
    when(
      () => client.createWorklog(
        issueKey: any(named: 'issueKey'),
        timeSpent: any(named: 'timeSpent'),
        startedAt: any(named: 'startedAt'),
        comment: any(named: 'comment'),
      ),
    ).thenAnswer((_) async => '10001');

    final entry = await writes.createManualEntry(
      deviceId: 'dev_a',
      startAt: DateTime.utc(2026, 7, 7, 9),
      endAt: DateTime.utc(2026, 7, 7, 10),
      jiraTicketKey: 'PROJ-1',
      description: 'Design review',
    );

    final result = await service.syncNow();

    expect(result.created, 1);
    expect(result.total, 1);
    final worklog = await db.jiraWorklogsDao.getForEntry(entry.id);
    expect(worklog!.jiraWorklogId, '10001');
    expect(worklog.syncedTicketKey, 'PROJ-1');
    verify(
      () => client.createWorklog(
        issueKey: 'PROJ-1',
        timeSpent: const Duration(hours: 1),
        startedAt: entry.startAt,
        comment: 'Design review',
      ),
    ).called(1);
  });

  test('running (unfinished) entries are skipped', () async {
    await writes.startEntry(deviceId: 'dev_a', jiraTicketKey: 'PROJ-1');

    final result = await service.syncNow();

    expect(result.total, 0);
    verifyNever(
      () => client.createWorklog(
        issueKey: any(named: 'issueKey'),
        timeSpent: any(named: 'timeSpent'),
        startedAt: any(named: 'startedAt'),
        comment: any(named: 'comment'),
      ),
    );
  });

  test('updates the worklog when the entry changed since the last sync', () async {
    when(
      () => client.updateWorklog(
        issueKey: any(named: 'issueKey'),
        worklogId: any(named: 'worklogId'),
        timeSpent: any(named: 'timeSpent'),
        startedAt: any(named: 'startedAt'),
        comment: any(named: 'comment'),
      ),
    ).thenAnswer((_) async {});

    final entry = await writes.createManualEntry(
      deviceId: 'dev_a',
      startAt: DateTime.utc(2026, 7, 7, 9),
      endAt: DateTime.utc(2026, 7, 7, 10),
      jiraTicketKey: 'PROJ-1',
    );
    await writes.upsertJiraWorklogState(
      JiraWorklogRow(
        id: entry.id,
        syncedTicketKey: 'PROJ-1',
        jiraWorklogId: '10001',
        status: 'synced',
        lastError: null,
        syncedAt: DateTime.utc(2020),
      ),
    );

    final result = await service.syncNow();

    expect(result.updated, 1);
    verify(
      () => client.updateWorklog(
        issueKey: 'PROJ-1',
        worklogId: '10001',
        timeSpent: any(named: 'timeSpent'),
        startedAt: entry.startAt,
        comment: any(named: 'comment'),
      ),
    ).called(1);
  });

  test('moves the worklog to the new ticket when jiraTicketKey changes', () async {
    when(
      () => client.deleteWorklog(issueKey: 'PROJ-1', worklogId: '10001'),
    ).thenAnswer((_) async {});
    when(
      () => client.createWorklog(
        issueKey: 'PROJ-2',
        timeSpent: any(named: 'timeSpent'),
        startedAt: any(named: 'startedAt'),
        comment: any(named: 'comment'),
      ),
    ).thenAnswer((_) async => '10002');

    final entry = await writes.createManualEntry(
      deviceId: 'dev_a',
      startAt: DateTime.utc(2026, 7, 7, 9),
      endAt: DateTime.utc(2026, 7, 7, 10),
      jiraTicketKey: 'PROJ-2',
    );
    await writes.upsertJiraWorklogState(
      JiraWorklogRow(
        id: entry.id,
        syncedTicketKey: 'PROJ-1',
        jiraWorklogId: '10001',
        status: 'synced',
        lastError: null,
        syncedAt: DateTime.utc(2020),
      ),
    );

    final result = await service.syncNow();

    expect(result.updated, 1);
    final worklog = await db.jiraWorklogsDao.getForEntry(entry.id);
    expect(worklog!.syncedTicketKey, 'PROJ-2');
    expect(worklog.jiraWorklogId, '10002');
  });

  test('deletes the remote worklog and the tracking row for a pendingDelete entry', () async {
    when(
      () => client.deleteWorklog(issueKey: 'PROJ-1', worklogId: '10001'),
    ).thenAnswer((_) async {});

    final entry = await writes.createManualEntry(
      deviceId: 'dev_a',
      startAt: DateTime.utc(2026, 7, 7, 9),
      endAt: DateTime.utc(2026, 7, 7, 10),
      jiraTicketKey: 'PROJ-1',
    );
    await writes.upsertJiraWorklogState(
      JiraWorklogRow(
        id: entry.id,
        syncedTicketKey: 'PROJ-1',
        jiraWorklogId: '10001',
        status: 'pendingDelete',
        lastError: null,
        syncedAt: null,
      ),
    );

    final result = await service.syncNow();

    expect(result.deleted, 1);
    expect(await db.jiraWorklogsDao.getForEntry(entry.id), isNull);
  });

  test('a failed create is recorded with status error and counted as failed', () async {
    when(
      () => client.createWorklog(
        issueKey: any(named: 'issueKey'),
        timeSpent: any(named: 'timeSpent'),
        startedAt: any(named: 'startedAt'),
        comment: any(named: 'comment'),
      ),
    ).thenThrow(JiraApiException('boom'));

    final entry = await writes.createManualEntry(
      deviceId: 'dev_a',
      startAt: DateTime.utc(2026, 7, 7, 9),
      endAt: DateTime.utc(2026, 7, 7, 10),
      jiraTicketKey: 'PROJ-1',
    );

    final result = await service.syncNow();

    expect(result.failed, 1);
    final worklog = await db.jiraWorklogsDao.getForEntry(entry.id);
    expect(worklog!.status, 'error');
    expect(worklog.lastError, contains('boom'));
  });

  test(
    'a failed pendingDelete stays pendingDelete and is retried on the next sync',
    () async {
      when(
        () => client.deleteWorklog(issueKey: 'PROJ-1', worklogId: '10001'),
      ).thenThrow(JiraApiException('unreachable'));

      final entry = await writes.createManualEntry(
        deviceId: 'dev_a',
        startAt: DateTime.utc(2026, 7, 7, 9),
        endAt: DateTime.utc(2026, 7, 7, 10),
        jiraTicketKey: 'PROJ-1',
      );
      await writes.upsertJiraWorklogState(
        JiraWorklogRow(
          id: entry.id,
          syncedTicketKey: 'PROJ-1',
          jiraWorklogId: '10001',
          status: 'pendingDelete',
          lastError: null,
          syncedAt: null,
        ),
      );

      final firstResult = await service.syncNow();

      expect(firstResult.failed, 1);
      final worklogAfterFailure = await db.jiraWorklogsDao.getForEntry(entry.id);
      expect(worklogAfterFailure!.status, 'pendingDelete');
      expect(worklogAfterFailure.lastError, contains('unreachable'));

      when(
        () => client.deleteWorklog(issueKey: 'PROJ-1', worklogId: '10001'),
      ).thenAnswer((_) async {});

      final secondResult = await service.syncNow();

      expect(secondResult.deleted, 1);
      expect(await db.jiraWorklogsDao.getForEntry(entry.id), isNull);
    },
  );
}
