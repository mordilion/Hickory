import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/core/di/absence_providers.dart';
import 'package:hickory/core/di/app_settings_provider.dart';
import 'package:hickory/core/di/device_id_provider.dart';
import 'package:hickory/core/di/sync_providers.dart';
import 'package:hickory/data/drift/database.dart';
import 'package:hickory/data/drift/tables/absences_table.dart';
import 'package:hickory/data/sync/sync_log_writer.dart';
import 'package:hickory/data/sync/synced_writes.dart';
import 'package:hickory/features/absences/absence_bar.dart';
import 'package:hickory/l10n/app_localizations.dart';

import '../../support/app_settings_fixture.dart';

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
    syncRoot = Directory.systemTemp.createTempSync('hickory_absence_bar_test_');
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

  // All seven weekdays carry a target so the form's "today" default is
  // always a work day, regardless of which day of the week the suite
  // happens to run on. Weekend skipping already has its own dedicated
  // coverage in absence_days_test.dart.
  final everyDayTarget = appSettingsFixture(
    absenceTrackingEnabled: true,
    targetMinutesMonday: 480,
    targetMinutesTuesday: 480,
    targetMinutesWednesday: 480,
    targetMinutesThursday: 480,
    targetMinutesFriday: 480,
    targetMinutesSaturday: 480,
    targetMinutesSunday: 480,
  );

  Widget makeApp({List<AbsenceType> types = const []}) => ProviderScope(
        overrides: [
          appSettingsProvider.overrideWith((ref) => Stream.value(everyDayTarget)),
          absenceTypesProvider.overrideWith((ref) => Stream.value(types)),
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
          home: const Scaffold(body: SingleChildScrollView(child: AbsenceBar())),
        ),
      );

  AbsenceType vacation() => AbsenceType(
        id: 'type-1',
        name: 'Urlaub',
        paid: true,
        sortOrder: 0,
        deviceId: 'd',
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
      );

  testWidgets('without any type it points at the settings instead of a form', (tester) async {
    await tester.pumpWidget(makeApp());
    await tester.pumpAndSettle();

    expect(find.text('Lege zuerst in den Einstellungen einen Abwesenheitstyp an.'), findsOneWidget);
    expect(find.text('Eintragen'), findsNothing);
  });

  testWidgets('a full-day absence is written for the chosen day', (tester) async {
    await tester.pumpWidget(makeApp(types: [vacation()]));
    await tester.pumpAndSettle();

    await tester.runAsync(() async {
      await tester.tap(find.text('Eintragen'));
      // tester.tap() dispatches the pointer event but does not itself pump
      // a frame, and the button's onPressed (and the real file write it
      // starts) is not guaranteed to run until one does — see
      // absence_types_editor_test.dart for the same pattern.
      await tester.pump();
      await waitFor(() async => (await db.select(db.absences).get()).isNotEmpty);
    });
    await tester.pump();

    final rows = await db.select(db.absences).get();
    expect(rows, hasLength(1), reason: 'the form defaults to a single day');
    expect(rows.single.absenceTypeId, 'type-1');
    expect(rows.single.portion, absencePortionFullDay);
    expect(rows.single.startAt, isNull);
    // The single day is the form's default and so the commonest message
    // there is: it has to read as German, not as "1 Tage".
    expect(find.text('1 Tag eingetragen.'), findsOneWidget);
  });

  testWidgets('choosing the time-range extent reveals the two time fields', (tester) async {
    await tester.pumpWidget(makeApp(types: [vacation()]));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('absenceStartTime')), findsNothing);
    expect(
      find.text('Umfang'),
      findsOneWidget,
      reason: 'the portion control needs a visible label, not just the segment names',
    );

    await tester.tap(find.text('Zeitraum'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('absenceStartTime')), findsOneWidget);
    expect(find.byKey(const ValueKey('absenceEndTime')), findsOneWidget);
  });

  // showTimePicker's dial cannot sensibly be tapped in a widget test, so
  // this drives its keyboard-entry mode instead. [hour] has to be 1..12:
  // the test platform reports a 12-hour clock, so the dialog's own field
  // rejects anything above 12 even though the form's buttons render the
  // picked time as 24-hour.
  Future<void> pickTime(
    WidgetTester tester, {
    required String fieldKey,
    required String hour,
    required String minute,
  }) async {
    await tester.tap(find.byKey(ValueKey(fieldKey)));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.keyboard_outlined));
    await tester.pumpAndSettle();
    final fields = find.descendant(
      of: find.byType(TimePickerDialog),
      matching: find.byType(TextField),
    );
    await tester.enterText(fields.first, hour);
    await tester.enterText(fields.last, minute);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
  }

  testWidgets('an end time before the start pulls the start back with it', (tester) async {
    await tester.pumpWidget(makeApp(types: [vacation()]));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Zeitraum'));
    await tester.pumpAndSettle();
    expect(find.text('Von: 09:00'), findsOneWidget);

    await pickTime(tester, fieldKey: 'absenceEndTime', hour: '08', minute: '00');

    // Without the clamp the row would be written with endAt before
    // startAt, which absenceMinutes scores as zero while the snackbar
    // still reports the absence as recorded.
    expect(find.text('Bis: 08:00'), findsOneWidget);
    expect(find.text('Von: 08:00'), findsOneWidget);
  });

  testWidgets('a start time after the end pushes the end along with it', (tester) async {
    await tester.pumpWidget(makeApp(types: [vacation()]));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Zeitraum'));
    await tester.pumpAndSettle();
    expect(find.text('Bis: 11:00'), findsOneWidget);

    await pickTime(tester, fieldKey: 'absenceStartTime', hour: '11', minute: '30');

    expect(find.text('Von: 11:30'), findsOneWidget);
    expect(find.text('Bis: 11:30'), findsOneWidget);
  });

  testWidgets('a half-day absence stores the portion, not a minute figure', (tester) async {
    await tester.pumpWidget(makeApp(types: [vacation()]));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Halbtags'));
    await tester.pumpAndSettle();

    await tester.runAsync(() async {
      await tester.tap(find.text('Eintragen'));
      await tester.pump();
      await waitFor(() async => (await db.select(db.absences).get()).isNotEmpty);
    });
    await tester.pump();

    final rows = await db.select(db.absences).get();
    expect(rows.single.portion, absencePortionHalfDay);
    expect(rows.single.startAt, isNull, reason: 'a half day derives its length from the target');
  });

  testWidgets('a time range that ends when it starts is refused, not reported as saved', (
    tester,
  ) async {
    await tester.pumpWidget(makeApp(types: [vacation()]));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Zeitraum'));
    await tester.pumpAndSettle();

    // Pulls the start up to the end. The clamp keeps the two in order but
    // cannot make them a span: 11:00 to 11:00 is no absence at all.
    await pickTime(tester, fieldKey: 'absenceStartTime', hour: '11', minute: '00');
    expect(find.text('Von: 11:00'), findsOneWidget);
    expect(find.text('Bis: 11:00'), findsOneWidget);

    late List<Absence> rows;
    await tester.runAsync(() async {
      await tester.tap(find.text('Eintragen'));
      await tester.pump();
      await Future.delayed(const Duration(milliseconds: 100));
      rows = await db.select(db.absences).get();
    });
    await tester.pump();

    expect(rows, isEmpty, reason: 'a range of no length must not become a row');
    expect(find.text('Das Ende muss nach dem Beginn liegen.'), findsOneWidget);
  });
}
