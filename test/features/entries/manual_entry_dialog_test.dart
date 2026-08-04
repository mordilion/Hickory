import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/core/di/app_settings_provider.dart';
import 'package:hickory/core/di/break_rule_tiers_provider.dart';
import 'package:hickory/core/di/device_id_provider.dart';
import 'package:hickory/core/di/jira_providers.dart';
import 'package:hickory/core/di/sync_providers.dart';
import 'package:hickory/data/drift/database.dart';
import 'package:hickory/data/sync/sync_log_writer.dart';
import 'package:hickory/data/sync/synced_writes.dart';
import 'package:hickory/features/entries/entries_list.dart';
import 'package:hickory/features/projects/projects_providers.dart';
import 'package:hickory/features/timer/timer_providers.dart';
import 'package:hickory/l10n/app_localizations.dart';

void main() {
  late AppDatabase db;
  late Directory syncRoot;
  late SyncedWrites writes;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    syncRoot = Directory.systemTemp.createTempSync('hickory_manual_entry_dialog_test_');
    writes = SyncedWrites(
      db: db,
      logWriter: SyncLogWriter(syncRoot: syncRoot, deviceId: 'device-1'),
    );
  });

  tearDown(() async {
    await db.close();
    if (syncRoot.existsSync()) syncRoot.deleteSync(recursive: true);
  });

  // See quick_add_bar_test.dart's makeApp doc comment: providers other than
  // deviceIdProvider/syncedWritesProvider are static Stream.value overrides
  // rather than real drift streams, to avoid a known flutter_test false
  // positive with live QueryStreams at teardown.
  Widget makeApp(List<TimeEntry> entries) => ProviderScope(
        overrides: [
          allEntriesProvider.overrideWith((ref) => Stream.value(entries)),
          activeProjectsProvider.overrideWith((ref) => Stream.value(const [])),
          jiraWorklogsByEntryIdProvider.overrideWith((ref) => Stream.value(const {})),
          breakRuleTiersProvider.overrideWith((ref) => Stream.value(const [])),
          appSettingsProvider.overrideWith(
            (ref) => Stream.value(
              AppSettingsRow(
                id: 'default',
                dateFormat: 'iso',
                timeFormat: '24h',
                quickAddDurationsMinutes: '15,30,45,60',
                countPausedTimeAsBreak: false,
                updatedAt: DateTime.utc(2026, 1, 1),
              ),
            ),
          ),
          deviceIdProvider.overrideWith((ref) async => 'device-1'),
          syncedWritesProvider.overrideWith((ref) async => writes),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: const Scaffold(body: EntriesList()),
        ),
      );

  testWidgets('deleting an entry, after confirming, removes it and closes the dialog', (
    tester,
  ) async {
    // A bare `await writes.createManualEntry(...)` here would never resolve:
    // AutomatedTestWidgetsFlutterBinding only drains the microtask queue
    // during pump() calls, and this line runs before any pump() exists to do
    // that. SyncLogWriter.appendEvent's real file write needs the genuine
    // event loop, which tester.runAsync provides.
    final entry = await tester.runAsync(
      () => writes.createManualEntry(
        deviceId: 'device-1',
        startAt: DateTime.now().subtract(const Duration(hours: 1)),
        endAt: DateTime.now(),
        description: 'Standup',
      ),
    );

    await tester.pumpWidget(makeApp([entry!]));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Standup'));
    await tester.pumpAndSettle();
    expect(find.text('Edit entry'), findsOneWidget);

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    final confirmDialog = find.ancestor(
      of: find.text('Delete entry?'),
      matching: find.byType(AlertDialog),
    );
    expect(confirmDialog, findsOneWidget);

    // _delete() does real file I/O (SyncedWrites.deleteEntry -> the sync
    // log write, which lands *after* the row is already gone from the DB)
    // before it pops the dialog; tapping alone starts it but the fake test
    // zone never services that I/O's completion on its own. Poll for the
    // dialog actually closing -- not just the DB row disappearing, which
    // races ahead of the pending pop() -- pumping each cycle so the tree
    // reflects it.
    await tester.runAsync(() async {
      await tester.tap(find.descendant(of: confirmDialog, matching: find.text('Delete')));
      for (var i = 0; i < 100; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await tester.pump();
        if (find.text('Edit entry').evaluate().isEmpty) break;
      }
    });
    await tester.pumpAndSettle();

    expect(find.text('Edit entry'), findsNothing);
    expect(await db.select(db.timeEntries).get(), isEmpty);
  });

  testWidgets('canceling the delete confirmation keeps the entry and the dialog open', (
    tester,
  ) async {
    final entry = await tester.runAsync(
      () => writes.createManualEntry(
        deviceId: 'device-1',
        startAt: DateTime.now().subtract(const Duration(hours: 1)),
        endAt: DateTime.now(),
        description: 'Standup',
      ),
    );

    await tester.pumpWidget(makeApp([entry!]));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Standup'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    final confirmDialog = find.ancestor(
      of: find.text('Delete entry?'),
      matching: find.byType(AlertDialog),
    );
    await tester.tap(find.descendant(of: confirmDialog, matching: find.text('Cancel')));
    await tester.pumpAndSettle();

    expect(find.text('Delete entry?'), findsNothing);
    expect(find.text('Edit entry'), findsOneWidget);
    expect(await db.select(db.timeEntries).get(), hasLength(1));
  });
}
