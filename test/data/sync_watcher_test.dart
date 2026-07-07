import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/data/drift/database.dart';
import 'package:hickory/data/sync/sync_ingestor.dart';
import 'package:hickory/data/sync/sync_log_writer.dart';
import 'package:hickory/data/sync/synced_writes.dart';
import 'package:storage_access/storage_access.dart';

// Plain test() (not testWidgets): runs as a normal fast Dart VM test.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  test(
    'a filesystem watcher on the shared folder propagates a write from one '
    'device to another without an explicit manual sync call',
    () async {
      final syncRoot = Directory.systemTemp.createTempSync('hickory_watch_test_');
      addTearDown(() {
        if (syncRoot.existsSync()) syncRoot.deleteSync(recursive: true);
      });

      final dbA = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(dbA.close);
      final writesA = SyncedWrites(
        db: dbA,
        logWriter: SyncLogWriter(syncRoot: syncRoot, deviceId: 'dev_a'),
      );

      final dbB = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(dbB.close);
      final ingestorB = SyncIngestor(db: dbB, syncRoot: syncRoot);

      // dev_b watches the shared folder exactly like the real app does via
      // syncWatcherProvider, just without the Riverpod plumbing around it.
      final folderProvider = SyncFolderProvider();
      final watchSubscription = folderProvider
          .watch(syncRoot.path, debounce: const Duration(milliseconds: 50))
          .listen((_) => ingestorB.syncNow());
      addTearDown(watchSubscription.cancel);

      // DirectoryWatcher does an async initial scan before it's truly
      // "live"; changes made during that window can be folded into its
      // baseline instead of reported as events (a documented watcher
      // limitation, which is exactly why the app also offers a manual
      // "sync now" as a fallback). Give it a moment to finish starting up
      // so this test exercises the realistic case — a change arriving
      // while the watcher is actively running, not in its first instant.
      await Future<void>.delayed(const Duration(milliseconds: 500));

      // dev_a writes a project; dev_b only ever learns about it through the
      // file that appears on disk under the shared folder.
      final project = await writesA.createProject(name: 'Watched Project', colorHex: '#5B8DEF');

      // Poll dbB until the watcher has reacted. This is exercising a real
      // OS filesystem-change notification, not a fake clock, so some
      // wall-clock delay is expected; the bounded loop fails fast once the
      // deadline passes instead of hanging indefinitely.
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      var seenProjects = const <Project>[];
      while (DateTime.now().isBefore(deadline) && seenProjects.isEmpty) {
        seenProjects = await dbB.select(dbB.projects).get();
        if (seenProjects.isEmpty) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      }

      expect(seenProjects, hasLength(1));
      expect(seenProjects.single.id, project.id);
      expect(seenProjects.single.name, 'Watched Project');
    },
    timeout: const Timeout(Duration(seconds: 20)),
  );
}
