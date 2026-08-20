import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/core/di/database_provider.dart';
import 'package:hickory/core/di/jira_providers.dart';
import 'package:hickory/core/di/sync_providers.dart';
import 'package:hickory/data/drift/database.dart';
import 'package:hickory/data/sync/sync_log_writer.dart';
import 'package:hickory/data/sync/synced_writes.dart';
import 'package:hickory/features/jira/jira_sync_service.dart';
import 'package:mocktail/mocktail.dart';

class MockJiraSyncService extends Mock implements JiraSyncService {}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late Directory syncRoot;
  late SyncedWrites writes;
  late MockJiraSyncService service;
  late int syncRuns;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    syncRoot = Directory.systemTemp.createTempSync('hickory_jira_auto_sync_test_');
    writes = SyncedWrites(
      db: db,
      logWriter: SyncLogWriter(syncRoot: syncRoot, deviceId: 'dev_a'),
    );
    service = MockJiraSyncService();
    // Counted by hand rather than with verify(), so a run can be *waited
    // for* instead of slept for -- the whole suite runs several files in
    // parallel and a fixed sleep is a flaky assertion under load.
    syncRuns = 0;
    when(service.syncNow).thenAnswer((_) async {
      syncRuns++;
      return const JiraSyncResult(created: 0, updated: 0, deleted: 0, failed: 0);
    });
  });

  tearDown(() async {
    await db.close();
    if (syncRoot.existsSync()) syncRoot.deleteSync(recursive: true);
  });

  Future<void> waitForSyncRuns(int expected) async {
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (DateTime.now().isBefore(deadline) && syncRuns < expected) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  /// Activates the auto-sync exactly like the app does by watching it, with
  /// a debounce short enough to keep the test fast.
  ProviderContainer activate({JiraSyncService? jiraService}) {
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        syncedWritesProvider.overrideWith((ref) async => writes),
        jiraSyncServiceProvider.overrideWith((ref) async => jiraService),
        jiraAutoSyncDebounceProvider.overrideWithValue(const Duration(milliseconds: 20)),
      ],
    );
    addTearDown(container.dispose);
    container.listen(jiraAutoSyncProvider, (_, _) {});
    return container;
  }

  test('reconciles once at startup, without any user action', () async {
    activate(jiraService: service);

    await waitForSyncRuns(1);
    expect(syncRuns, 1);
  });

  test('reconciles again after an entry is written', () async {
    activate(jiraService: service);
    await waitForSyncRuns(1);

    final entry = await writes.startEntry(deviceId: 'dev_a', description: 'Booked work');
    await writes.stopEntry(entry.id);

    await waitForSyncRuns(2);
    expect(syncRuns, greaterThan(1));
  });

  test('does nothing while Jira is not configured', () async {
    activate();

    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(syncRuns, 0);
  });
}
