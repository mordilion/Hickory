import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/core/di/app_settings_provider.dart';
import 'package:hickory/core/di/break_rule_tiers_provider.dart';
import 'package:hickory/core/di/device_id_provider.dart';
import 'package:hickory/core/di/sync_providers.dart';
import 'package:hickory/data/drift/database.dart';
import 'package:hickory/data/sync/sync_log_writer.dart';
import 'package:hickory/data/sync/synced_writes.dart';
import 'package:hickory/features/settings/break_rule_tiers_editor.dart';
import 'package:hickory/l10n/app_localizations.dart';

// NOTE: SyncedWrites' real SyncLogWriter performs real file I/O
// (File.writeAsString) when logging each event. flutter_test's
// TestWidgetsFlutterBinding does not service real (non-fake-clock) async
// I/O unless it runs inside WidgetTester.runAsync -- outside of runAsync,
// an awaited real file write never completes, hanging the caller forever.
// Every tap that triggers a SyncedWrites call is therefore wrapped in
// runAsync together with the poll that waits for its effect, and the poll
// itself uses a real Future.delayed (not tester.pump, which drives a fake
// clock that has no bearing on real I/O completion).
Future<void> pumpUntilTrue(
  Future<bool> Function() condition, {
  int maxTries = 50,
}) async {
  for (var i = 0; i < maxTries; i++) {
    if (await condition()) {
      // The DB write (what condition() observes) completes before the sync
      // log's trailing file write (SyncLogWriter.appendEvent), which is
      // awaited afterward in the same call chain. Give it a moment to
      // finish inside this runAsync scope too, so it doesn't race the
      // test's tearDown (which deletes the temp sync root).
      await Future.delayed(const Duration(milliseconds: 50));
      return;
    }
    await Future.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  late AppDatabase db;
  late Directory syncRoot;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    syncRoot = Directory.systemTemp.createTempSync('hickory_break_rule_settings_test_');
  });

  tearDown(() async {
    await db.close();
    // On Windows the OS can transiently keep the sync-log file handle open
    // for a moment after SyncLogWriter's real write completes (observed
    // with antivirus/indexing); retry briefly rather than fail the test on
    // an unrelated cleanup race. The final attempt is unguarded: if the
    // lock genuinely never clears, that's worth surfacing as a real test
    // failure instead of silently leaving the temp directory behind.
    const maxRetries = 5;
    for (var attempt = 0; attempt < maxRetries; attempt++) {
      if (!syncRoot.existsSync()) return;
      try {
        syncRoot.deleteSync(recursive: true);
        return;
      } on FileSystemException {
        if (attempt == maxRetries - 1) rethrow;
        await Future.delayed(const Duration(milliseconds: 100));
      }
    }
  });

  Widget makeApp({
    List<BreakRuleTier> tiers = const [],
    bool countPausedTimeAsBreak = false,
  }) => ProviderScope(
        overrides: [
          breakRuleTiersProvider.overrideWith((ref) => Stream.value(tiers)),
          appSettingsProvider.overrideWith(
            (ref) => Stream.value(
              AppSettingsRow(
                id: 'default',
                dateFormat: 'iso',
                timeFormat: '24h',
                quickAddDurationsMinutes: '15,30,45,60',
                countPausedTimeAsBreak: countPausedTimeAsBreak,
                updatedAt: DateTime.utc(2026, 1, 1),
              ),
            ),
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
          locale: const Locale('en'),
          home: const Scaffold(body: BreakRuleTiersEditor()),
        ),
      );

  testWidgets('tapping the Germany preset creates its two tiers', (tester) async {
    await tester.pumpWidget(makeApp());
    await tester.pumpAndSettle();

    await tester.runAsync(() async {
      await tester.tap(find.text('Germany'));
      await pumpUntilTrue(() async => (await db.select(db.breakRuleTiers).get()).length == 2);
    });

    final tiers = await db.select(db.breakRuleTiers).get();
    tiers.sort((a, b) => a.afterMinutes.compareTo(b.afterMinutes));
    expect(tiers.map((t) => t.afterMinutes), [360, 540]);
    expect(tiers.map((t) => t.requiredBreakMinutes), [30, 45]);
  });

  testWidgets('tapping a preset replaces any existing tiers rather than adding to them', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 1, 1);
    await tester.pumpWidget(
      makeApp(
        tiers: [
          BreakRuleTier(
            id: 'old',
            afterMinutes: 120,
            requiredBreakMinutes: 10,
            deviceId: 'device-1',
            createdAt: now,
            updatedAt: now,
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.runAsync(() async {
      await tester.tap(find.text('Austria'));
      await pumpUntilTrue(() async {
        final rows = await db.select(db.breakRuleTiers).get();
        return rows.length == 1 && rows.single.afterMinutes == 360;
      });
    });

    final tiers = await db.select(db.breakRuleTiers).get();
    expect(tiers, hasLength(1));
    expect(tiers.single.afterMinutes, 360);
  });

  testWidgets('tapping None clears all tiers', (tester) async {
    final now = DateTime.utc(2026, 1, 1);
    await tester.pumpWidget(
      makeApp(
        tiers: [
          BreakRuleTier(
            id: 'old',
            afterMinutes: 360,
            requiredBreakMinutes: 30,
            deviceId: 'device-1',
            createdAt: now,
            updatedAt: now,
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.runAsync(() async {
      await tester.tap(find.text('None'));
      await pumpUntilTrue(() async => (await db.select(db.breakRuleTiers).get()).isEmpty);
    });

    expect(await db.select(db.breakRuleTiers).get(), isEmpty);
  });

  testWidgets('renders tier thresholds as hours/minutes, not a clock time', (tester) async {
    final now = DateTime.utc(2026, 1, 1);
    await tester.pumpWidget(
      makeApp(
        tiers: [
          BreakRuleTier(
            id: 'tier-1',
            afterMinutes: 390, // 6h 30m
            requiredBreakMinutes: 45,
            deviceId: 'device-1',
            createdAt: now,
            updatedAt: now,
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('6h 30m'), findsOneWidget);
    expect(find.textContaining('45m'), findsOneWidget);
    // A clock-time rendering of 390 worked minutes would read "06:30".
    expect(find.textContaining('06:30'), findsNothing);
  });

  testWidgets('removing a tier deletes it', (tester) async {
    final now = DateTime.utc(2026, 1, 1);
    await tester.pumpWidget(
      makeApp(
        tiers: [
          BreakRuleTier(
            id: 'tier-1',
            afterMinutes: 360,
            requiredBreakMinutes: 30,
            deviceId: 'device-1',
            createdAt: now,
            updatedAt: now,
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.runAsync(() async {
      await tester.tap(find.byIcon(Icons.delete_outline));
      await pumpUntilTrue(() async => (await db.select(db.breakRuleTiers).get()).isEmpty);
    });

    expect(await db.select(db.breakRuleTiers).get(), isEmpty);
  });

  testWidgets('adding a tier via the dialog persists it', (tester) async {
    await tester.pumpWidget(makeApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add rule'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, '300');
    await tester.enterText(find.byType(TextField).last, '20');

    await tester.runAsync(() async {
      await tester.tap(find.text('Save'));
      // The dialog's Navigator.pop() (which resolves showDialog's Future
      // and lets _add's write continuation run) needs a frame to settle.
      await tester.pump();
      await pumpUntilTrue(() async => (await db.select(db.breakRuleTiers).get()).isNotEmpty);
    });

    final tiers = await db.select(db.breakRuleTiers).get();
    expect(tiers, hasLength(1));
    expect(tiers.single.afterMinutes, 300);
    expect(tiers.single.requiredBreakMinutes, 20);
  });

  testWidgets('entering a non-numeric value shows an inline error and keeps the dialog open', (
    tester,
  ) async {
    await tester.pumpWidget(makeApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add rule'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'abc');
    await tester.enterText(find.byType(TextField).last, '20');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    // The dialog is still open (Save didn't pop it) and shows the error
    // as the field's own errorText, not a SnackBar hidden behind the
    // modal barrier.
    expect(find.text('Add rule'), findsOneWidget);
    expect(find.text('Please enter valid minute values.'), findsWidgets);
    expect(await db.select(db.breakRuleTiers).get(), isEmpty);
  });

  testWidgets('renders the switch already on when countPausedTimeAsBreak is true', (tester) async {
    await tester.pumpWidget(makeApp(countPausedTimeAsBreak: true));
    await tester.pumpAndSettle();

    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isTrue,
    );
  });

  testWidgets('toggling "Include pause-button time" persists the setting', (tester) async {
    await tester.pumpWidget(makeApp());
    await tester.pumpAndSettle();

    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isFalse,
    );

    await tester.runAsync(() async {
      await tester.tap(find.text('Include pause-button time'));
      await pumpUntilTrue(() async {
        final rows = await db.select(db.appSettings).get();
        return rows.isNotEmpty && rows.single.countPausedTimeAsBreak;
      });
    });

    final rows = await db.select(db.appSettings).get();
    expect(rows.single.countPausedTimeAsBreak, isTrue);
  });
}
