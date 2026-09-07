import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/core/di/app_settings_provider.dart';
import 'package:hickory/core/di/balance_adjustment_providers.dart';
import 'package:hickory/core/di/database_provider.dart';
import 'package:hickory/core/di/device_id_provider.dart';
import 'package:hickory/core/di/sync_providers.dart';
import 'package:hickory/data/drift/database.dart';
import 'package:hickory/data/sync/sync_log_writer.dart';
import 'package:hickory/data/sync/synced_writes.dart';
import 'package:hickory/features/reports/balance_adjustment_dialog.dart';
import 'package:hickory/l10n/app_localizations.dart';

import '../../support/app_settings_fixture.dart';

void main() {
  late AppDatabase db;
  late Directory syncRoot;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    syncRoot = Directory.systemTemp.createTempSync('hickory_adjustment_dialog_test_');
  });

  tearDown(() async {
    await db.close();
    if (syncRoot.existsSync()) syncRoot.deleteSync(recursive: true);
  });

  Future<void> waitFor(Future<bool> Function() condition) async {
    for (var attempt = 0; attempt < 50; attempt++) {
      if (await condition()) {
        await Future.delayed(const Duration(milliseconds: 50));
        return;
      }
      await Future.delayed(const Duration(milliseconds: 10));
    }
  }

  /// Opens the dialog over a button, so the pop it performs has a route to
  /// return to. The corrections it lists come from a frozen fixture rather
  /// than the live DAO stream: a drift stream watched by a widget deadlocks
  /// flutter_test's teardown, while the writes below still go to the real
  /// in-memory database and are asserted there.
  Future<void> openDialog(
    WidgetTester tester, {
    List<BalanceAdjustment> existing = const [],
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          // The dialog reads the date format from here. Left live it
          // would watch a real drift stream from inside a widget, which
          // deadlocks flutter_test's teardown against drift's own
          // debounced stream-close timer.
          appSettingsProvider.overrideWith((ref) => Stream.value(appSettingsFixture())),
          balanceAdjustmentsProvider.overrideWith((ref) => Stream.value(existing)),
          deviceIdProvider.overrideWith((ref) async => 'device-1'),
          syncedWritesProvider.overrideWith(
            (ref) async => SyncedWrites(
              db: db,
              logWriter: SyncLogWriter(syncRoot: syncRoot, deviceId: 'device-1'),
            ),
          ),
        ],
        child: MaterialApp(
          locale: const Locale('de'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => Consumer(
                builder: (context, ref, _) => TextButton(
                  onPressed: () => showBalanceAdjustmentsDialog(context, ref),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  BalanceAdjustment adjustment(int deltaMinutes, {String? note}) => BalanceAdjustment(
        id: 'adj-1',
        date: DateTime(2026, 9, 7),
        deltaMinutes: deltaMinutes,
        note: note,
        deviceId: 'd',
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
      );

  testWidgets('records a correction as signed hours', (tester) async {
    await openDialog(tester);

    await tester.enterText(find.byKey(const ValueKey('adjustmentHours')), '-3,5');
    await tester.enterText(find.byKey(const ValueKey('adjustmentNote')), 'ausgezahlt');

    late List<BalanceAdjustment> rows;
    await tester.runAsync(() async {
      await tester.tap(find.text('Hinzufügen'));
      await tester.pump();
      await waitFor(() async => (await db.select(db.balanceAdjustments).get()).isNotEmpty);
      rows = await db.select(db.balanceAdjustments).get();
    });
    await tester.pump();

    expect(rows.single.deltaMinutes, -210);
    expect(rows.single.note, 'ausgezahlt');
  });

  testWidgets('refuses text that is not a number instead of saving a zero', (tester) async {
    await openDialog(tester);

    await tester.enterText(find.byKey(const ValueKey('adjustmentHours')), 'drei');
    await tester.tap(find.text('Hinzufügen'));
    await tester.pumpAndSettle();

    expect(find.text('Bitte eine Stundenzahl ungleich null eingeben.'), findsOneWidget);
    expect(await db.select(db.balanceAdjustments).get(), isEmpty);
  });

  testWidgets('refuses a correction of zero hours', (tester) async {
    await openDialog(tester);

    await tester.enterText(find.byKey(const ValueKey('adjustmentHours')), '0');
    await tester.tap(find.text('Hinzufügen'));
    await tester.pumpAndSettle();

    expect(find.text('Bitte eine Stundenzahl ungleich null eingeben.'), findsOneWidget);
    expect(await db.select(db.balanceAdjustments).get(), isEmpty);
  });

  testWidgets('lists the corrections that exist, signed and with their note', (tester) async {
    await openDialog(tester, existing: [adjustment(-210, note: 'ausgezahlt')]);

    expect(find.text('-3:30'), findsOneWidget);
    expect(find.textContaining('ausgezahlt'), findsOneWidget);
  });

  testWidgets('says so when there is no correction yet', (tester) async {
    await openDialog(tester);

    expect(find.text('Noch keine Korrekturen erfasst.'), findsOneWidget);
  });
}
