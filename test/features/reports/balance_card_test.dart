import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/core/di/absence_providers.dart';
import 'package:hickory/core/di/app_settings_provider.dart';
import 'package:hickory/core/di/balance_adjustment_providers.dart';
import 'package:hickory/data/drift/database.dart';
import 'package:hickory/data/drift/tables/absences_table.dart';
import 'package:hickory/features/reports/balance_card.dart';
import 'package:hickory/features/timer/timer_providers.dart';
import 'package:hickory/l10n/app_localizations.dart';

import '../../support/app_settings_fixture.dart';

// BalanceCard is pure presentation over appSettingsProvider and
// allEntriesProvider, so both are overridden with frozen fixture streams
// here rather than routed through a real appDatabaseProvider: a widget that
// ref.watch()es a genuine drift stream gets torn down by flutter_test's
// automatic end-of-test widget reset before drift's own debounced
// stream-close timer fires, which deadlocks tearDown's `db.close()` waiting
// on that timer (see balance_rule_editor_test.dart for the same trap with
// SyncedWrites' file I/O).
/// A finished entry running [minutes] from 09:00 local time on [day] --
/// same shape as balance_calculations_test.dart's entryOn.
TimeEntry _entryOn(DateTime day, int minutes, {String id = 'e'}) {
  final start = DateTime(day.year, day.month, day.day, 9);
  return TimeEntry(
    id: id,
    startAt: start.toUtc(),
    endAt: start.add(Duration(minutes: minutes)).toUtc(),
    totalPausedSeconds: 0,
    source: 'manual',
    deviceId: 'test',
    createdAt: DateTime.utc(2026, 1, 1),
    updatedAt: DateTime.utc(2026, 1, 1),
  );
}

/// The first Monday of [reference]'s month, so a test can date entries
/// inside the default "this month" range whatever day it runs on.
DateTime _mondayIn(DateTime reference) {
  var day = DateTime(reference.year, reference.month, 1);
  while (day.weekday != DateTime.monday) {
    day = day.add(const Duration(days: 1));
  }
  return day;
}

void main() {
  // 2026-08-31 is a Monday, and in the past relative to any run of this
  // suite -- workTimeBalanceProvider's runningBalance stops at
  // DateTime.now(), so a future-dated entry would silently be excluded and
  // the balance would read 0 regardless of what dayBalances computed.
  final monday = DateTime(2026, 8, 31);

  Future<void> pumpCard(
    WidgetTester tester, {
    AppSettingsRow? settings,
    List<TimeEntry> entries = const [],
    List<Absence> absences = const [],
    List<AbsenceType> absenceTypes = const [],
    List<BalanceAdjustment> adjustments = const [],
    // Suppliers, not bare Streams: a StreamProvider override can be
    // invoked more than once, and re-returning the same single-subscription
    // Stream instance the second time throws "Stream has already been
    // listened to" -- a fresh Stream.error(...) per invocation avoids that.
    Stream<AppSettingsRow> Function()? settingsStream,
    Stream<List<TimeEntry>> Function()? entriesStream,
    Stream<List<Absence>> Function()? absencesStream,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appSettingsProvider.overrideWith(
            (ref) => settingsStream?.call() ?? Stream.value(settings ?? appSettingsFixture()),
          ),
          allEntriesProvider.overrideWith(
            (ref) => entriesStream?.call() ?? Stream.value(entries),
          ),
          absencesProvider.overrideWith(
            (ref) => absencesStream?.call() ?? Stream.value(absences),
          ),
          absenceTypesProvider.overrideWith((ref) => Stream.value(absenceTypes)),
          balanceAdjustmentsProvider.overrideWith((ref) => Stream.value(adjustments)),
        ],
        child: MaterialApp(
          locale: const Locale('de'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: BalanceCard()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// The value shown under one tile's caption. Several tiles can carry the
  /// same figure, so an assertion about one of them names its label.
  Finder tileValue(String label, String value) => find.descendant(
        of: find.ancestor(of: find.text(label), matching: find.byType(Column)).first,
        matching: find.text(value),
      );

  test('formatSignedDuration always carries an explicit sign', () {
    expect(formatSignedDuration(const Duration(minutes: 90)), '+1:30');
    expect(formatSignedDuration(const Duration(minutes: -90)), '-1:30');
    expect(formatSignedDuration(Duration.zero), '+0:00');
  });

  testWidgets('without any target it points at the settings instead of a number', (tester) async {
    await pumpCard(tester);
    expect(find.text('Noch keine Soll-Arbeitszeit hinterlegt.'), findsOneWidget);
  });

  testWidgets('with a target it shows the overall balance', (tester) async {
    await pumpCard(tester, settings: appSettingsFixture(targetMinutesMonday: 480));
    expect(find.text('Saldo gesamt'), findsOneWidget);
    expect(tileValue('Saldo gesamt', '+0:00'), findsOneWidget);
  });

  testWidgets('a worked day is weighed against that weekday\'s target, not just echoed as zero', (
    tester,
  ) async {
    // 9 worked hours against Monday's 480-minute (8h) target: +60 minutes.
    // A stub that always returned Duration.zero would also pass the
    // all-zero-entries test above, so this pins down the actual arithmetic.
    await pumpCard(
      tester,
      settings: appSettingsFixture(targetMinutesMonday: 480),
      entries: [_entryOn(monday, 9 * 60)],
    );
    expect(tileValue('Saldo gesamt', '+1:00'), findsOneWidget);
  });

  testWidgets('a failing entries stream surfaces an error instead of spinning forever', (
    tester,
  ) async {
    // Regression: workTimeBalanceProvider used to read entries/settings via
    // `.isLoading`/`.value`, both of which treat an AsyncError the same as
    // "still loading" (a first-ever error) or silently keep the prior data
    // (an error after a prior success) -- neither reaches the widget's
    // error branch.
    await pumpCard(
      tester,
      settings: appSettingsFixture(targetMinutesMonday: 480),
      entriesStream: () => Stream<List<TimeEntry>>.error(Exception('boom')),
    );
    expect(find.textContaining('boom'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('a failing settings stream surfaces an error instead of spinning forever', (
    tester,
  ) async {
    await pumpCard(
      tester,
      settingsStream: () => Stream<AppSettingsRow>.error(Exception('boom')),
    );
    expect(find.textContaining('boom'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('a failing absences stream is ignored while the feature is off', (tester) async {
    // The one assertion behind workTimeBalanceProvider's conditional gate:
    // with absence tracking off the balance never reads an absence, so a
    // broken absences stream must not take the number down with it.
    await pumpCard(
      tester,
      settings: appSettingsFixture(targetMinutesMonday: 480),
      entries: [_entryOn(monday, 9 * 60)],
      absencesStream: () => Stream<List<Absence>>.error(Exception('boom')),
    );
    expect(find.textContaining('boom'), findsNothing);
    expect(find.text('+1:00'), findsOneWidget);
  });

  testWidgets('a failing absences stream surfaces once the feature is on', (tester) async {
    await pumpCard(
      tester,
      settings: appSettingsFixture(
        absenceTrackingEnabled: true,
        targetMinutesMonday: 480,
      ),
      entries: [_entryOn(monday, 9 * 60)],
      absencesStream: () => Stream<List<Absence>>.error(Exception('boom')),
    );
    expect(find.textContaining('boom'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('a paid full-day absence keeps the balance neutral', (tester) async {
    // Pinned to today, not a fixed calendar date: workTimeBalanceProvider
    // enumerates every work day through DateTime.now(), so a fixed past
    // date would pick up later unexcused weekdays as the suite ages and
    // the expected balance would drift away from zero. Every weekday
    // carries a target so today -- whatever day it is -- is a work day;
    // with no entry at all it would read -8:00 without the absence.
    final today = DateTime.now();
    final day = DateTime(today.year, today.month, today.day);
    await pumpCard(
      tester,
      settings: appSettingsFixture(
        absenceTrackingEnabled: true,
        targetMinutesMonday: 480,
        targetMinutesTuesday: 480,
        targetMinutesWednesday: 480,
        targetMinutesThursday: 480,
        targetMinutesFriday: 480,
        targetMinutesSaturday: 480,
        targetMinutesSunday: 480,
      ),
      // Zero-duration, but still a finished entry: it exists only to place
      // today into dayBalances' enumerated day set, so this test can fail
      // before the absence-wiring exists. Pre-wiring, absences never reach
      // dayBalances at all, so without an entry "today" has no worked time
      // and no absence and is skipped entirely, and the assertion below
      // would pass by vacuity. Zero duration keeps it inert once the
      // wiring is in place: it contributes nothing to the +0:00 total,
      // which then comes entirely from the paid full-day credit cancelling
      // the target.
      entries: [_entryOn(day, 0)],
      absences: [
        Absence(
          id: 'a1',
          date: day,
          absenceTypeId: 'type-1',
          portion: absencePortionFullDay,
          startAt: null,
          endAt: null,
          note: null,
          deviceId: 'd',
          createdAt: DateTime.utc(2026, 1, 1),
          updatedAt: DateTime.utc(2026, 1, 1),
        ),
      ],
      absenceTypes: [
        AbsenceType(
          id: 'type-1',
          name: 'Urlaub',
          paid: true,
          sortOrder: 0,
          deviceId: 'd',
          createdAt: DateTime.utc(2026, 1, 1),
          updatedAt: DateTime.utc(2026, 1, 1),
        ),
      ],
    );

    expect(tileValue('Saldo gesamt', '+0:00'), findsOneWidget);
  });

  testWidgets('shows the range balance, target against actual, and the daily average', (
    tester,
  ) async {
    // The default range is this month, so the two days are dated inside
    // it -- the same month the screen opens on when nothing is stored.
    final now = DateTime.now();
    final firstMonday = _mondayIn(now);
    await pumpCard(
      tester,
      settings: appSettingsFixture(
        targetMinutesMonday: 480,
        targetMinutesTuesday: 480,
      ),
      entries: [
        _entryOn(firstMonday, 540, id: 'a'),
        _entryOn(firstMonday.add(const Duration(days: 1)), 420, id: 'b'),
      ],
    );

    expect(find.text('Im Zeitraum'), findsOneWidget);
    expect(find.text('Soll / Ist'), findsOneWidget);
    expect(find.text('Ø pro Arbeitstag'), findsOneWidget);
    expect(
      find.byType(LinearProgressIndicator),
      findsOneWidget,
      reason: 'target against actual carries a progress bar',
    );
    // Nine hours and seven against two eight-hour days.
    expect(tileValue('Soll / Ist', '16:00 / 16:00'), findsOneWidget);
    expect(tileValue('Ø pro Arbeitstag', '08:00'), findsOneWidget);
  });

  testWidgets('a range without a single work day shows no average', (tester) async {
    await pumpCard(
      tester,
      settings: appSettingsFixture(targetMinutesMonday: 480),
      entries: const [],
    );

    expect(find.text('Ø pro Arbeitstag'), findsOneWidget);
    expect(tileValue('Ø pro Arbeitstag', '–'), findsOneWidget);
  });

  testWidgets('opens the corrections dialog from the block', (tester) async {
    await pumpCard(tester, settings: appSettingsFixture(targetMinutesMonday: 480));

    await tester.tap(find.byKey(const ValueKey('openBalanceAdjustments')));
    await tester.pumpAndSettle();

    expect(find.text('Korrekturen'), findsOneWidget);
  });
}
