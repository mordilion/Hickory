import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/data/drift/database.dart';
import 'package:hickory/data/drift/tables/jira_worklogs_table.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  test('upsert creates a pending row with no jiraWorklogId yet', () async {
    await db.jiraWorklogsDao.upsert(JiraWorklogsCompanion.insert(id: 'entry_1'));

    final row = await db.jiraWorklogsDao.getForEntry('entry_1');
    expect(row, isNotNull);
    expect(row!.status, JiraWorklogStatus.pending);
    expect(row.jiraWorklogId, isNull);
  });

  test('upsert on an existing id updates it in place', () async {
    await db.jiraWorklogsDao.upsert(JiraWorklogsCompanion.insert(id: 'entry_1'));
    await db.jiraWorklogsDao.upsert(
      JiraWorklogsCompanion.insert(
        id: 'entry_1',
        jiraWorklogId: const Value('10001'),
        syncedTicketKey: const Value('PROJ-1'),
        status: const Value(JiraWorklogStatus.synced),
        syncedAt: Value(DateTime.utc(2026, 7, 12)),
      ),
    );

    final rows = await db.jiraWorklogsDao.getAll();
    expect(rows, hasLength(1));
    expect(rows.single.jiraWorklogId, '10001');
    expect(rows.single.status, JiraWorklogStatus.synced);
  });

  test('deleteForEntry removes the tracking row', () async {
    await db.jiraWorklogsDao.upsert(JiraWorklogsCompanion.insert(id: 'entry_1'));
    await db.jiraWorklogsDao.deleteForEntry('entry_1');

    expect(await db.jiraWorklogsDao.getForEntry('entry_1'), isNull);
  });

  test('a time entry can carry an optional jiraTicketKey', () async {
    final entry = await db.timeEntriesDao.startEntry(deviceId: 'dev_a');
    expect(entry.jiraTicketKey, isNull);
  });
}
