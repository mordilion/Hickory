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
import 'package:hickory/features/settings/balance_rule_editor.dart';
import 'package:hickory/l10n/app_localizations.dart';

import '../../support/app_settings_fixture.dart';

// SyncedWrites' real SyncLogWriter does real file I/O, which flutter_test's
// binding only services inside WidgetTester.runAsync -- outside of it an
// awaited write never completes and hangs the test forever. The same is
// true of a drift query against the real, in-memory `db`, so every read or
// write that touches `db` runs inside runAsync, together with the poll
// that awaits its effect. The trap is documented in full at
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
    syncRoot = makeSyncRoot('hickory_balance_rule_test_');
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
          home: const Scaffold(body: SingleChildScrollView(child: BalanceRuleEditor())),
        ),
      );

  /// Opens the mode dropdown and picks [label]. No runAsync: choosing a
  /// mode other than "no cutoff" is held locally until the rule is
  /// complete, so nothing is written yet.
  Future<void> chooseMode(WidgetTester tester, String label) async {
    await tester.tap(find.byKey(const ValueKey('balanceMode')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  /// Picks a cutoff. Both halves are always chosen together, because
  /// neither on its own is a cutoff the editor will persist.
  Future<void> chooseCutoff(WidgetTester tester, String month, String day) async {
    await tester.tap(find.byKey(const ValueKey('balanceCutoffMonth')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(month).last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('balanceCutoffDay')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(day).last);
    await tester.pumpAndSettle();
  }

  testWidgets('no cutoff hides the date and the bounds', (tester) async {
    await tester.pumpWidget(makeApp());
    await tester.pumpAndSettle();

    expect(find.text('Stichtag'), findsNothing);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('choosing reset-to-zero reveals the cutoff but no bounds', (tester) async {
    await tester.pumpWidget(makeApp());
    await tester.pumpAndSettle();
    await chooseMode(tester, 'Auf 0 setzen');

    expect(find.text('Stichtag'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('choosing carry-over reveals both bounds', (tester) async {
    await tester.pumpWidget(makeApp());
    await tester.pumpAndSettle();
    await chooseMode(tester, 'Übertrag mit Kappung');

    expect(find.byType(TextField), findsNWidgets(2));
  });

  testWidgets('an incomplete rule is not persisted and says what is missing', (tester) async {
    await tester.pumpWidget(makeApp());
    await tester.pumpAndSettle();
    await chooseMode(tester, 'Auf 0 setzen');

    late AppSettingsRow row;
    await tester.runAsync(() async {
      row = await db.appSettingsDao.watchSettings().first;
    });
    expect(row.balanceResetMode, 'none', reason: 'incomplete rules must not reach the database');
    expect(find.text('Bitte einen Stichtag wählen.'), findsOneWidget);
  });

  testWidgets('picking a cutoff month and day persists the complete rule', (tester) async {
    await tester.pumpWidget(makeApp());
    await tester.pumpAndSettle();
    await chooseMode(tester, 'Auf 0 setzen');

    late AppSettingsRow row;
    await tester.runAsync(() async {
      await chooseCutoff(tester, 'Juli', '7');
      await waitFor(
        () async => (await db.appSettingsDao.watchSettings().first).balanceResetMonth == 7,
      );
      row = await db.appSettingsDao.watchSettings().first;
    });
    expect(row.balanceResetMode, 'resetToZero');
    expect(row.balanceResetMonth, 7);
    expect(row.balanceResetDay, 7);
  });

  testWidgets('a cutoff month without a day is not persisted', (tester) async {
    await tester.pumpWidget(makeApp());
    await tester.pumpAndSettle();
    await chooseMode(tester, 'Auf 0 setzen');

    late AppSettingsRow row;
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('balanceCutoffMonth')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Juli').last);
      await tester.pumpAndSettle();
      // There is no write to poll for here -- the point of this test is
      // that none happens. Settle the pumps and give any (wrongly) started
      // write a moment to land before asserting it did not.
      await Future.delayed(const Duration(milliseconds: 200));
      row = await db.appSettingsDao.watchSettings().first;
    });
    expect(
      row.balanceResetMode,
      'none',
      reason: 'half a cutoff must not be completed with a day the user never picked',
    );
    expect(find.text('Bitte einen Stichtag wählen.'), findsOneWidget);
  });

  testWidgets('carry-over with a cutoff but no bound is not persisted', (tester) async {
    await tester.pumpWidget(makeApp());
    await tester.pumpAndSettle();
    await chooseMode(tester, 'Übertrag mit Kappung');

    late AppSettingsRow row;
    await tester.runAsync(() async {
      await chooseCutoff(tester, 'Juli', '7');
      await Future.delayed(const Duration(milliseconds: 200));
      row = await db.appSettingsDao.watchSettings().first;
    });
    expect(
      row.balanceResetMode,
      'none',
      reason: 'a carry-over with a cutoff but no bound must not reach the database',
    );
    expect(find.text('Bitte mindestens eine Grenze angeben.'), findsOneWidget);
  });

  testWidgets('a carry-over bound without a cutoff is not persisted', (tester) async {
    await tester.pumpWidget(makeApp());
    await tester.pumpAndSettle();
    await chooseMode(tester, 'Übertrag mit Kappung');

    await tester.enterText(find.byKey(const ValueKey('carryOverMax')), '5');
    late AppSettingsRow row;
    await tester.runAsync(() async {
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await Future.delayed(const Duration(milliseconds: 200));
      row = await db.appSettingsDao.watchSettings().first;
    });
    expect(
      row.balanceResetMode,
      'none',
      reason: 'a bound alone must not silently pick 1 January as the cutoff',
    );
    expect(row.balanceResetMonth, null);
    expect(row.balanceResetDay, null);
    expect(find.text('Bitte einen Stichtag wählen.'), findsOneWidget);
  });

  testWidgets('a carry-over minimum bound persists as a negative number', (tester) async {
    await tester.pumpWidget(makeApp());
    await tester.pumpAndSettle();
    await chooseMode(tester, 'Übertrag mit Kappung');

    late AppSettingsRow row;
    await tester.runAsync(() async {
      await chooseCutoff(tester, 'Juli', '7');
    });
    await tester.enterText(find.byKey(const ValueKey('carryOverMin')), '2');
    await tester.runAsync(() async {
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await waitFor(
        () async => (await db.appSettingsDao.watchSettings().first).carryOverMinMinutes == -120,
      );
      row = await db.appSettingsDao.watchSettings().first;
    });
    expect(
      row.carryOverMinMinutes,
      -120,
      reason: 'the deficit bound is entered as a positive magnitude but stored negative',
    );
  });

  testWidgets('a bound typed and then left by moving focus still reaches the database', (
    tester,
  ) async {
    await tester.pumpWidget(makeApp());
    await tester.pumpAndSettle();
    await chooseMode(tester, 'Übertrag mit Kappung');

    late AppSettingsRow row;
    await tester.runAsync(() async {
      await chooseCutoff(tester, 'Juli', '7');
    });
    await tester.enterText(find.byKey(const ValueKey('carryOverMax')), '5');
    await tester.runAsync(() async {
      // No Enter anywhere: moving to the next field is all the user does.
      await tester.tap(find.byKey(const ValueKey('carryOverMin')));
      await tester.pumpAndSettle();
      await waitFor(
        () async => (await db.appSettingsDao.watchSettings().first).carryOverMaxMinutes == 300,
      );
      row = await db.appSettingsDao.watchSettings().first;
    });
    expect(row.carryOverMaxMinutes, 300);
    expect(row.balanceResetMode, 'carryOver');
  });

  testWidgets('a failed write is reported instead of being swallowed', (tester) async {
    // A plain file where the sync log needs its `entries` directory: the
    // settings row is written, the log append then throws, and the editor
    // goes on showing a selection the user's other devices will never see
    // unless it says so.
    File('${syncRoot.path}/entries').createSync();

    await tester.pumpWidget(
      makeApp(
        settings: appSettingsFixture(
          balanceResetMode: 'carryOver',
          balanceResetDay: 1,
          balanceResetMonth: 1,
          carryOverMaxMinutes: 300,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('balanceMode')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kein Stichtag').last);
      await tester.pumpAndSettle();
      await Future.delayed(const Duration(milliseconds: 500));
    });
    await tester.pumpAndSettle();

    expect(find.text('Das Zeitkonto konnte nicht gespeichert werden.'), findsOneWidget);
  });

  testWidgets('switching from a configured carry-over to none clears cutoff and bounds', (
    tester,
  ) async {
    await tester.pumpWidget(
      makeApp(
        settings: appSettingsFixture(
          balanceResetMode: 'carryOver',
          balanceResetDay: 1,
          balanceResetMonth: 1,
          carryOverMaxMinutes: 300,
          carryOverMinMinutes: -120,
        ),
      ),
    );
    await tester.pumpAndSettle();

    late AppSettingsRow row;
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('balanceMode')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kein Stichtag').last);
      await waitFor(
        () async => (await db.appSettingsDao.watchSettings().first).balanceResetMode == 'none',
      );
      row = await db.appSettingsDao.watchSettings().first;
    });
    expect(row.balanceResetMode, 'none');
    expect(row.balanceResetDay, null, reason: 'switching to none clears the stale cutoff day');
    expect(row.balanceResetMonth, null, reason: 'switching to none clears the stale cutoff month');
    expect(row.carryOverMaxMinutes, null, reason: 'switching to none clears the stale max bound');
    expect(row.carryOverMinMinutes, null, reason: 'switching to none clears the stale min bound');
  });
}
