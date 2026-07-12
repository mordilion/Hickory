import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/data/drift/database.dart';
import 'package:hickory/data/drift/tables/jira_worklogs_table.dart';
import 'package:hickory/data/sync/sync_log_writer.dart';
import 'package:hickory/data/sync/synced_writes.dart';

void main() {
  late AppDatabase db;
  late SyncedWrites writes;
  late Directory syncRoot;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    syncRoot = Directory.systemTemp.createTempSync('hickory_jira_test_');
    writes = SyncedWrites(
      db: db,
      logWriter: SyncLogWriter(syncRoot: syncRoot, deviceId: 'dev_a'),
    );
  });

  tearDown(() async {
    await db.close();
    if (syncRoot.existsSync()) syncRoot.deleteSync(recursive: true);
  });

  test('createManualEntry persists the optional jiraTicketKey', () async {
    final entry = await writes.createManualEntry(
      deviceId: 'dev_a',
      startAt: DateTime.utc(2026, 7, 7, 9),
      endAt: DateTime.utc(2026, 7, 7, 10),
      jiraTicketKey: 'PROJ-42',
    );

    expect(entry.jiraTicketKey, 'PROJ-42');
  });

  test('deleteEntry marks a pushed worklog pendingDelete instead of removing it', () async {
    final entry = await writes.createManualEntry(
      deviceId: 'dev_a',
      startAt: DateTime.utc(2026, 7, 7, 9),
      endAt: DateTime.utc(2026, 7, 7, 10),
      jiraTicketKey: 'PROJ-42',
    );
    await writes.upsertJiraWorklogState(
      JiraWorklogRow(
        id: entry.id,
        syncedTicketKey: 'PROJ-42',
        jiraWorklogId: '10001',
        status: JiraWorklogStatus.synced,
        lastError: null,
        syncedAt: DateTime.utc(2026, 7, 7, 10),
      ),
    );

    await writes.deleteEntry(entry.id);

    final remainingEntry =
        await (db.select(db.timeEntries)..where((t) => t.id.equals(entry.id))).getSingleOrNull();
    expect(remainingEntry, isNull);

    final worklog = await db.jiraWorklogsDao.getForEntry(entry.id);
    expect(worklog, isNotNull);
    expect(worklog!.status, JiraWorklogStatus.pendingDelete);
  });

  test('deleteEntry removes the tracking row outright if it was never pushed', () async {
    final entry = await writes.createManualEntry(
      deviceId: 'dev_a',
      startAt: DateTime.utc(2026, 7, 7, 9),
      endAt: DateTime.utc(2026, 7, 7, 10),
      jiraTicketKey: 'PROJ-42',
    );
    await writes.upsertJiraWorklogState(
      JiraWorklogRow(
        id: entry.id,
        syncedTicketKey: null,
        jiraWorklogId: null,
        status: JiraWorklogStatus.error,
        lastError: 'network error',
        syncedAt: null,
      ),
    );

    await writes.deleteEntry(entry.id);

    expect(await db.jiraWorklogsDao.getForEntry(entry.id), isNull);
  });
}
