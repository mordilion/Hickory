import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/core/di/absence_providers.dart';
import 'package:hickory/core/di/app_settings_provider.dart';
import 'package:hickory/core/di/database_provider.dart';
import 'package:hickory/core/di/device_id_provider.dart';
import 'package:hickory/core/di/sync_providers.dart';
import 'package:hickory/data/drift/database.dart';
import 'package:hickory/data/drift/tables/absences_table.dart';
import 'package:hickory/data/sync/sync_log_writer.dart';
import 'package:hickory/data/sync/synced_writes.dart';
import 'package:hickory/features/settings/absence_types_editor.dart';
import 'package:hickory/l10n/app_localizations.dart';

import '../../support/app_settings_fixture.dart';

// SyncedWrites' real SyncLogWriter does real file I/O, which flutter_test's
// binding only services inside WidgetTester.runAsync -- outside it an
// awaited write never returns and the test hangs. See
// test/features/settings/break_rule_tiers_editor_test.dart:17.
//
// appDatabaseProvider is overridden so the delete path's one-shot
// AbsencesDao.countByType read hits the same in-memory database the writes
// land in. absenceTypesProvider is overridden with a frozen fixture rather
// than left to read the live drift stream: drift's debounced stream close
// leaves a pending timer, and tearDown's db.close() then waits forever for
// flutter_test to service it outside runAsync. Every test therefore asserts
// against the database, not the widget's own (frozen) list.
Future<void> waitFor(Future<bool> Function() condition, {int maxTries = 50}) async {
  for (var attempt = 0; attempt < maxTries; attempt++) {
    if (await condition()) {
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
    syncRoot = Directory.systemTemp.createTempSync('hickory_absence_types_test_');
  });

  tearDown(() async {
    await db.close();
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
  });

  Widget makeApp({bool enabled = true, List<AbsenceType> types = const []}) => ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          absenceTypesProvider.overrideWith((ref) => Stream.value(types)),
          appSettingsProvider.overrideWith(
            (ref) => Stream.value(appSettingsFixture(absenceTrackingEnabled: enabled)),
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
          home: const Scaffold(body: SingleChildScrollView(child: AbsenceTypesEditor())),
        ),
      );

  testWidgets('the standard-types button creates four types', (tester) async {
    await tester.pumpWidget(makeApp());
    await tester.pumpAndSettle();

    await tester.runAsync(() async {
      await tester.tap(find.text('Standardtypen anlegen'));
      // tester.tap() dispatches the pointer events but does not itself
      // pump a frame; the control's callback is not guaranteed to run
      // (and the ref.read()s inside it resolve) until one does, and that
      // only reliably happens once this is not the first testWidgets in
      // the file to reach a runAsync write. Without this pump the write
      // silently stalls past this test's own polling window and only
      // finishes once some later pump (e.g. the next test's) happens to
      // trigger it -- see waitFor's use below and on every other write in
      // this file.
      await tester.pump();
      await waitFor(() async => (await db.absenceTypesDao.getAllTypes()).length == 4);
    });
    await tester.pump();

    final types = await db.absenceTypesDao.getAllTypes();
    expect(types.map((t) => t.name), containsAll(['Urlaub', 'Krank', 'Feiertag']));
    expect(
      types.firstWhere((t) => t.name == 'Unbezahlter Urlaub').paid,
      isFalse,
      reason: 'the standard set must cover both paid states',
    );
  });

  testWidgets('the standard-types button disappears once a type exists', (tester) async {
    final type = await db.absenceTypesDao.createType(
      deviceId: 'd', name: 'Urlaub', paid: true, sortOrder: 0,
    );
    await tester.pumpWidget(makeApp(types: [type]));
    await tester.pumpAndSettle();

    expect(find.text('Standardtypen anlegen'), findsNothing);
  });

  testWidgets('a type in use cannot be deleted and the count is shown', (tester) async {
    final type = await db.absenceTypesDao.createType(
      deviceId: 'd', name: 'Urlaub', paid: true, sortOrder: 0,
    );
    await db.absencesDao.createAbsence(
      deviceId: 'd',
      date: DateTime(2026, 9, 7),
      absenceTypeId: type.id,
      portion: absencePortionFullDay,
    );
    await tester.pumpWidget(makeApp(types: [type]));
    await tester.pumpAndSettle();

    await tester.runAsync(() async {
      await tester.tap(find.byKey(ValueKey('deleteAbsenceType-${type.id}')));
      await Future.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();

    expect(await db.absenceTypesDao.getAllTypes(), hasLength(1));
    // Singular: one absence is the commonest case there is, and "1 Tagen"
    // is not German.
    expect(find.text('Wird von 1 Tag verwendet und kann nicht gelöscht werden.'), findsOneWidget);
  });

  testWidgets('an unused type is deleted', (tester) async {
    final type = await db.absenceTypesDao.createType(
      deviceId: 'd', name: 'Urlaub', paid: true, sortOrder: 0,
    );
    await tester.pumpWidget(makeApp(types: [type]));
    await tester.pumpAndSettle();

    await tester.runAsync(() async {
      await tester.tap(find.byKey(ValueKey('deleteAbsenceType-${type.id}')));
      // See the comment on the standard-types test above.
      await tester.pump();
      await waitFor(() async => (await db.absenceTypesDao.getAllTypes()).isEmpty);
    });
    await tester.pump();

    expect(await db.absenceTypesDao.getAllTypes(), isEmpty);
  });

  testWidgets('moving a type down renumbers the list', (tester) async {
    final first = await db.absenceTypesDao.createType(
      deviceId: 'd', name: 'Urlaub', paid: true, sortOrder: 0,
    );
    final second = await db.absenceTypesDao.createType(
      deviceId: 'd', name: 'Krank', paid: true, sortOrder: 1,
    );
    await tester.pumpWidget(makeApp(types: [first, second]));
    await tester.pumpAndSettle();

    await tester.runAsync(() async {
      await tester.tap(find.byKey(ValueKey('moveAbsenceTypeDown-${first.id}')));
      // See the comment on the standard-types test above.
      await tester.pump();
      await waitFor(() async {
        final types = await db.absenceTypesDao.getAllTypes();
        return types.isNotEmpty && types.first.id == second.id;
      });
    });
    await tester.pump();

    final types = await db.absenceTypesDao.getAllTypes();
    expect(types.map((t) => t.name), ['Krank', 'Urlaub']);
  });

  testWidgets('the switch writes the stored flag', (tester) async {
    await tester.pumpWidget(makeApp(enabled: false));
    await tester.pumpAndSettle();

    await tester.runAsync(() async {
      await tester.tap(find.byType(SwitchListTile));
      // See the comment on the standard-types test above.
      await tester.pump();
      // A one-shot select, not watchSettings().first: a Stream-based watch
      // query, subscribed and cancelled repeatedly in a poll loop, leaves
      // this test order-dependent -- it hangs whenever another test in
      // this file already ran, even though the write it is polling for
      // completes fine on its own (verified by isolating this test).
      await waitFor(
        () async =>
            (await db.select(db.appSettings).getSingleOrNull())?.absenceTrackingEnabled ??
            false,
      );
    });

    final row = await db.select(db.appSettings).getSingleOrNull();
    expect(row?.absenceTrackingEnabled, isTrue);
  });
}
