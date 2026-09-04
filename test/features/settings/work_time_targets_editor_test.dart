import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/core/di/app_settings_provider.dart';
import 'package:hickory/core/di/device_id_provider.dart';
import 'package:hickory/core/di/sync_providers.dart';
import 'package:hickory/data/drift/database.dart';
import 'package:hickory/data/sync/sync_log_writer.dart';
import 'package:hickory/data/sync/synced_writes.dart';
import 'package:hickory/features/settings/work_time_targets_editor.dart';
import 'package:hickory/l10n/app_localizations.dart';

import '../../support/app_settings_fixture.dart';

// SyncedWrites' real SyncLogWriter does real file I/O, which flutter_test's
// binding only services inside WidgetTester.runAsync -- outside of it an
// awaited write never completes and hangs the test forever. The same is
// true of a drift query against the real, in-memory `db` (its executor's
// async plumbing needs the real event loop too), so every read or write
// that touches `db` -- not just the interaction that triggers the write --
// runs inside runAsync, together with the poll that waits for the write's
// effect. The trap is documented in full at
// test/features/settings/break_rule_tiers_editor_test.dart:17.
//
// appSettingsProvider itself is overridden with a frozen fixture stream
// rather than routed through a real appDatabaseProvider: a widget that
// ref.watch()es a genuine drift stream gets torn down by flutter_test's
// automatic end-of-test widget reset before drift's own debounced
// stream-close timer fires, which both trips flutter_test's
// "Timer still pending" invariant and then deadlocks tearDown's
// `db.close()` waiting on that same timer. Every write in this file still
// goes to the real, in-memory `db` through a real SyncedWrites -- the
// tests assert against that database, not against the frozen fixture.
Future<void> waitFor(Future<bool> Function() condition, {int maxTries = 50}) async {
  for (var attempt = 0; attempt < maxTries; attempt++) {
    if (await condition()) {
      // The DB write completes before the sync log's trailing file write,
      // which is awaited afterwards in the same chain; let it finish inside
      // this runAsync scope so it cannot race tearDown's directory delete.
      await Future.delayed(const Duration(milliseconds: 50));
      return;
    }
    await Future.delayed(const Duration(milliseconds: 10));
  }
}

Directory makeSyncRoot(String prefix) => Directory.systemTemp.createTempSync(prefix);

Future<void> removeSyncRoot(Directory syncRoot) async {
  // Windows can transiently hold the log file open after the write returns;
  // retry briefly rather than fail on an unrelated cleanup race.
  for (var attempt = 0; attempt < 5; attempt++) {
    if (!syncRoot.existsSync()) return;
    try {
      syncRoot.deleteSync(recursive: true);
      return;
    } on FileSystemException {
      if (attempt == 4) rethrow;
      await Future.delayed(const Duration(milliseconds: 100));
    }
  }
}

void main() {
  late AppDatabase db;
  late Directory syncRoot;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    syncRoot = makeSyncRoot('hickory_work_time_targets_test_');
  });

  tearDown(() async {
    await db.close();
    await removeSyncRoot(syncRoot);
  });

  Widget makeApp({AppSettingsRow? settings}) => ProviderScope(
        overrides: [
          appSettingsProvider.overrideWith(
            (ref) => Stream.value(settings ?? appSettingsFixture()),
          ),
          deviceIdProvider.overrideWith((ref) async => 'device-1'),
          syncedWritesProvider.overrideWith(
            (ref) async => SyncedWrites(
              db: db,
              logWriter: SyncLogWriter(syncRoot: syncRoot, deviceId: 'device-1'),
            ),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('de'),
          home: const Scaffold(body: SingleChildScrollView(child: WorkTimeTargetsEditor())),
        ),
      );

  testWidgets('starts in per-weekday mode with seven fields', (tester) async {
    await tester.pumpWidget(makeApp());
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNWidgets(7));
  });

  testWidgets('entering a daily target writes it to the database', (tester) async {
    await tester.pumpWidget(makeApp());
    await tester.pumpAndSettle();

    // enterText only sets the field's text (no async I/O consequence), so it
    // stays outside runAsync; receiveAction is what fires onSubmitted and
    // starts the real write, so it -- like every submit gesture in this
    // file -- runs inside runAsync together with the poll that awaits it.
    await tester.enterText(find.byKey(const ValueKey('workTimeTarget1')), '8');
    late AppSettingsRow row;
    await tester.runAsync(() async {
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await waitFor(
        () async => (await db.appSettingsDao.watchSettings().first).targetMinutesMonday == 480,
      );
      // Read the final row inside runAsync too: a drift query against the
      // real `db` needs the real event loop just like the write did, so
      // this would hang (not just fail) if run afterwards in the test's
      // normal fake-async zone.
      row = await db.appSettingsDao.watchSettings().first;
    });

    expect(row.targetMinutesMonday, 480);
  });

  testWidgets('weekly mode shows one field and the work-day toggles', (tester) async {
    await tester.pumpWidget(makeApp());
    await tester.pumpAndSettle();

    await tester.runAsync(() async {
      await tester.tap(find.text('Pro Woche'));
      await waitFor(
        () async =>
            (await db.appSettingsDao.watchSettings().first).targetInputMode == 'perWeek',
      );
    });
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsOneWidget);
    expect(find.byType(FilterChip), findsNWidgets(7));
  });

  testWidgets('a weekly target is distributed across the selected work days', (tester) async {
    await tester.pumpWidget(
      makeApp(
        settings: appSettingsFixture(
          targetInputMode: 'perWeek',
          targetMinutesMonday: 300,
          targetMinutesTuesday: 300,
          targetMinutesWednesday: 300,
          targetMinutesThursday: 300,
          targetMinutesFriday: 300,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const ValueKey('workTimeWeekly')), '40');
    late AppSettingsRow row;
    await tester.runAsync(() async {
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await waitFor(
        () async => (await db.appSettingsDao.watchSettings().first).targetMinutesMonday == 480,
      );
      row = await db.appSettingsDao.watchSettings().first;
    });

    expect(row.targetMinutesMonday, 480);
    expect(row.targetMinutesFriday, 480);
    expect(row.targetMinutesSaturday, 0);
  });
}
