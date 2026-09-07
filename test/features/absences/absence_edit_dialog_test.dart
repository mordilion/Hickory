import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/core/di/absence_providers.dart';
import 'package:hickory/core/di/app_settings_provider.dart';
import 'package:hickory/core/format/date_format.dart';
import 'package:hickory/data/drift/database.dart';
import 'package:hickory/data/drift/tables/absences_table.dart';
import 'package:hickory/features/absences/absence_edit_dialog.dart';
import 'package:hickory/l10n/app_localizations.dart';

import '../../support/app_settings_fixture.dart';

void main() {
  AbsenceType type(String id, String name) => AbsenceType(
        id: id,
        name: name,
        paid: true,
        sortOrder: 0,
        deviceId: 'd',
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
      );

  Absence absence({
    String portion = absencePortionFullDay,
    String? halfDayPart,
    DateTime? startAt,
    DateTime? endAt,
    String? note,
  }) => Absence(
        id: 'absence-1',
        date: DateTime(2026, 9, 7),
        absenceTypeId: 'type-1',
        portion: portion,
        halfDayPart: halfDayPart,
        startAt: startAt,
        endAt: endAt,
        note: note,
        deviceId: 'd',
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
      );

  /// Mounts the dialog and hands back a getter for whatever it pops with.
  /// Pushed from a button rather than shown directly, so the pop has a
  /// route to return to and the result is observable; the getter is read
  /// after the interaction the test is about.
  Future<AbsenceEdit? Function()> showEditor(
    WidgetTester tester,
    Absence row, {
    List<AbsenceType> types = const [],
  }) async {
    AbsenceEdit? result;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          absenceTypesProvider.overrideWith((ref) => Stream.value(types)),
          appSettingsProvider.overrideWith(
            (ref) => Stream.value(appSettingsFixture(dateFormat: 'de', timeFormat: '12h')),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('de'),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  result = await showDialog<AbsenceEdit>(
                    context: context,
                    builder: (_) => AbsenceEditDialog(absence: row),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return () => result;
  }

  testWidgets('keeps the note and the extent it was opened with', (tester) async {
    await showEditor(
      tester,
      absence(portion: absencePortionHalfDay, note: 'Arzt'),
      types: [type('type-1', 'Urlaub')],
    );

    expect(find.text('Arzt'), findsOneWidget);
    expect(find.text('Urlaub'), findsOneWidget);
    // The first of the two: the extent, above the half-of-the-day control
    // that a half day brings with it.
    final segments = tester.widget<SegmentedButton<String>>(
      find.byType(SegmentedButton<String>).first,
    );
    expect(segments.selected, {absencePortionHalfDay});
  });

  testWidgets('refuses a range that ends when it starts and stays open', (tester) async {
    await showEditor(
      tester,
      absence(
        portion: absencePortionRange,
        startAt: DateTime(2026, 9, 7, 9).toUtc(),
        endAt: DateTime(2026, 9, 7, 9).toUtc(),
      ),
      types: [type('type-1', 'Urlaub')],
    );

    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();

    expect(find.text('Das Ende muss nach dem Beginn liegen.'), findsOneWidget);
    expect(
      find.byType(AbsenceEditDialog),
      findsOneWidget,
      reason: 'a refused save must not close the dialog and lose the edit',
    );
  });

  testWidgets('clears the time range when a range becomes a whole day', (tester) async {
    AbsenceEdit? result;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          absenceTypesProvider.overrideWith(
            (ref) => Stream.value([type('type-1', 'Urlaub')]),
          ),
          appSettingsProvider.overrideWith(
            (ref) => Stream.value(appSettingsFixture(dateFormat: 'de', timeFormat: '12h')),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('de'),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  result = await showDialog<AbsenceEdit>(
                    context: context,
                    builder: (_) => AbsenceEditDialog(
                      absence: absence(
                        portion: absencePortionRange,
                        startAt: DateTime(2026, 9, 7, 9).toUtc(),
                        endAt: DateTime(2026, 9, 7, 11).toUtc(),
                      ),
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Ganztags'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();

    expect(result?.portion, absencePortionFullDay);
    expect(
      result?.startAt,
      isNull,
      reason: 'a whole day carries no time range, and the stored one must go',
    );
    expect(result?.endAt, isNull);
  });

  testWidgets('renders the day and the range in the configured format', (tester) async {
    await showEditor(
      tester,
      absence(
        portion: absencePortionRange,
        startAt: DateTime(2026, 9, 7, 9).toUtc(),
        endAt: DateTime(2026, 9, 7, 11).toUtc(),
      ),
      types: [type('type-1', 'Urlaub')],
    );

    // The same settings the form that recorded it reads, and the day it
    // belongs to spelled out -- the dialog cannot move it, so it says
    // which day is being corrected instead of leaving that to memory.
    expect(
      find.text(formatDate(DateTime(2026, 9, 7), DateFormatStyle.de, 'de')),
      findsOneWidget,
    );
    expect(find.text('9:00 AM'), findsOneWidget);
    expect(find.text('11:00 AM'), findsOneWidget);
    expect(find.byType(OutlinedButton), findsNothing);
  });

  testWidgets('offers the other half of the day to a half-day absence', (tester) async {
    final result = await showEditor(
      tester,
      absence(portion: absencePortionHalfDay, halfDayPart: absenceHalfDayMorning),
      types: [type('type-1', 'Urlaub')],
    );

    await tester.tap(find.text('Nachmittag'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();

    expect(result()?.halfDayPart, absenceHalfDayAfternoon);
  });
}
