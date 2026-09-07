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
import 'package:hickory/core/format/date_format.dart';
import 'package:hickory/core/theme/app_theme.dart';
import 'package:hickory/core/widgets/gradient_buttons.dart';
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

  Widget makeApp({List<AbsenceType> types = const [], AppSettingsRow? settings}) => ProviderScope(
        overrides: [
          appSettingsProvider.overrideWith((ref) => Stream.value(settings ?? everyDayTarget)),
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
          // The submit pill reads its gradient from HickoryColors, which
          // only exists as a ThemeExtension on the app's own theme.
          theme: AppTheme.light,
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
    expect(find.text('09:00'), findsOneWidget);

    await pickTime(tester, fieldKey: 'absenceEndTime', hour: '08', minute: '00');

    // Without the clamp the row would be written with endAt before
    // startAt, which absenceMinutes scores as zero while the snackbar
    // still reports the absence as recorded. Both ends now read 08:00,
    // so the two buttons carry the same text.
    expect(find.text('08:00'), findsNWidgets(2));
  });

  testWidgets('a start time after the end pushes the end along with it', (tester) async {
    await tester.pumpWidget(makeApp(types: [vacation()]));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Zeitraum'));
    await tester.pumpAndSettle();
    expect(find.text('11:00'), findsOneWidget);

    await pickTime(tester, fieldKey: 'absenceStartTime', hour: '11', minute: '30');

    expect(find.text('11:30'), findsNWidgets(2));
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
    expect(find.text('11:00'), findsNWidgets(2));

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

  testWidgets('sits in the same card the timer and manual forms use', (tester) async {
    await tester.pumpWidget(makeApp(types: [vacation()]));
    await tester.pumpAndSettle();

    // QuickAddBar and the timer's start card are both Card > Padding(16);
    // a bare column here made the third mode look like a different screen.
    expect(find.byType(Card), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(Card),
        matching: find.byWidgetPredicate(
          (widget) => widget is Padding && widget.padding == const EdgeInsets.all(16),
        ),
      ),
      findsOneWidget,
      reason: 'the form has to sit on the same 16px inset as the other two',
    );
  });

  testWidgets('keeps the card when no type has been created yet', (tester) async {
    await tester.pumpWidget(makeApp());
    await tester.pumpAndSettle();

    expect(find.byType(Card), findsOneWidget);
    expect(find.text('Lege zuerst in den Einstellungen einen Abwesenheitstyp an.'), findsOneWidget);
  });

  testWidgets('shows the extent control centred and without a heading', (tester) async {
    await tester.pumpWidget(makeApp(types: [vacation()]));
    await tester.pumpAndSettle();

    // The three segments say what they are; a label above them only
    // repeated it. It stays as the control's accessible name.
    expect(find.text('Umfang'), findsNothing);
    expect(
      tester
          .widget<Semantics>(
            find.ancestor(
              of: find.byType(SegmentedButton<String>),
              matching: find.byType(Semantics),
            ).first,
          )
          .properties
          .label,
      'Umfang',
    );
    expect(
      find.ancestor(
        of: find.byType(SegmentedButton<String>),
        matching: find.byType(Center),
      ),
      findsOneWidget,
    );
  });

  testWidgets('renders dates and times in the configured format', (tester) async {
    // The other two modes of this tab read the same two settings; this one
    // used intl's locale defaults and a 24-hour clock of its own, so the
    // same moment read differently depending on which mode you were in.
    await tester.pumpWidget(
      makeApp(
        types: [vacation()],
        settings: appSettingsFixture(
          absenceTrackingEnabled: true,
          targetMinutesMonday: 480,
          targetMinutesTuesday: 480,
          targetMinutesWednesday: 480,
          targetMinutesThursday: 480,
          targetMinutesFriday: 480,
          targetMinutesSaturday: 480,
          targetMinutesSunday: 480,
          dateFormat: 'de',
          timeFormat: '12h',
        ),
      ),
    );
    await tester.pumpAndSettle();

    final today = DateTime.now();
    expect(find.text(formatDate(today, DateFormatStyle.de, 'de')), findsWidgets);

    await tester.tap(find.text('Zeitraum'));
    await tester.pumpAndSettle();

    expect(find.text('9:00 AM'), findsOneWidget);
    expect(find.text('11:00 AM'), findsOneWidget);
  });

  testWidgets('uses the same date and time controls as the manual form', (tester) async {
    await tester.pumpWidget(makeApp(types: [vacation()]));
    await tester.pumpAndSettle();

    // QuickAddBar renders its four pickers as bare TextButtons in a Wrap,
    // separated by an en dash. Outlined buttons carrying "Von:"/"Bis:"
    // made the same control look like a different one per mode.
    expect(find.byType(OutlinedButton), findsNothing);
    expect(
      find.descendant(of: find.byType(Wrap), matching: find.byType(TextButton)),
      findsNWidgets(2),
    );
    expect(find.text('–'), findsOneWidget);
    expect(
      find.ancestor(of: find.byType(Wrap), matching: find.byType(Center)),
      findsOneWidget,
      reason: "the pickers sit centred, as they do in the manual form's centred column",
    );
  });

  testWidgets('commits with the same pill button the other two modes use', (tester) async {
    await tester.pumpWidget(makeApp(types: [vacation()]));
    await tester.pumpAndSettle();

    expect(find.byType(GradientPillButton), findsOneWidget);
  });

  testWidgets('a time range offers a from and a to date, like the manual form', (tester) async {
    await tester.pumpWidget(makeApp(types: [vacation()]));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Zeitraum'));
    await tester.pumpAndSettle();

    // date time - date time, the same four controls in the same order as
    // QuickAddBar: an absence over a range reads as one continuous span.
    expect(find.byKey(const ValueKey('absenceStartDate')), findsOneWidget);
    expect(find.byKey(const ValueKey('absenceStartTime')), findsOneWidget);
    expect(find.byKey(const ValueKey('absenceEndDate')), findsOneWidget);
    expect(find.byKey(const ValueKey('absenceEndTime')), findsOneWidget);
  });

  testWidgets('a range inside one day is written with both its times', (tester) async {
    await tester.pumpWidget(makeApp(types: [vacation()]));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Zeitraum'));
    await tester.pumpAndSettle();

    late List<Absence> rows;
    await tester.runAsync(() async {
      await tester.tap(find.text('Eintragen'));
      await tester.pump();
      await waitFor(() async => (await db.select(db.absences).get()).isNotEmpty);
      rows = await db.select(db.absences).get();
    });
    await tester.pump();

    expect(rows, hasLength(1), reason: 'the form defaults to one day');
    expect(rows.single.portion, absencePortionRange);
    expect(rows.single.startAt?.toLocal().hour, 9);
    expect(rows.single.endAt?.toLocal().hour, 11);
  });
}
