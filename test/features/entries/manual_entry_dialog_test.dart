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

  testWidgets('tapping the start-date button opens a date picker', (tester) async {
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

    // Row order in the dialog: [Start label][start date][start time], then
    // [End label][end date][end time] -- TextButton index 0 is start-date.
    await tester.tap(find.byType(TextButton).first);
    await tester.pumpAndSettle();

    expect(find.byType(DatePickerDialog), findsOneWidget);
  });

  testWidgets(
    'picking a start time preserves a start date other than today '
    '(regression: _pickTime must not hardcode DateTime.now()\'s date)',
    (tester) async {
      // startAt is "now minus an hour", i.e. today -- the picker's initial
      // month page will contain today, letting us navigate to an adjacent
      // day within the same page (see targetDay below).
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

      final startDateLabelBeforePick =
          ((tester.widget(find.byType(TextButton).first) as TextButton).child! as Text).data;

      // Navigate the calendar to a day that is NOT today, staying within the
      // same month page (no month-navigation needed) and within the
      // picker's lastDate bound (now + 1 day): pick yesterday, or tomorrow
      // if today is the 1st of the month.
      final now = DateTime.now();
      final targetDay = now.day > 1 ? now.day - 1 : now.day + 1;

      await tester.tap(find.byType(TextButton).first);
      await tester.pumpAndSettle();
      expect(find.byType(DatePickerDialog), findsOneWidget);

      // Scope to the dialog: a bare find.text(day) could also ambiguously
      // match multiple calendar cells (header vs. grid) while it's open.
      await tester.tap(
        find.descendant(
          of: find.byType(DatePickerDialog),
          matching: find.text(targetDay.toString()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      final startDateLabelAfterDatePick =
          ((tester.widget(find.byType(TextButton).first) as TextButton).child! as Text).data;
      expect(
        startDateLabelAfterDatePick,
        isNot(startDateLabelBeforePick),
        reason: 'picking a non-today day should change the displayed start date',
      );

      // Now pick the start time via its own pre-filled default. This is the
      // actual regression check: if _pickTime combined the picked time with
      // DateTime.now()'s date instead of the button's initial date, the
      // start date would silently snap back to today here.
      await tester.tap(find.byType(TextButton).at(1));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      final startDateLabelAfterTimePick =
          ((tester.widget(find.byType(TextButton).first) as TextButton).child! as Text).data;
      expect(
        startDateLabelAfterTimePick,
        startDateLabelAfterDatePick,
        reason: 'picking a time must not reset the start date back to today',
      );
    },
  );

  testWidgets(
    'picking a start date preserves the already-set start time',
    (tester) async {
      final entry = await tester.runAsync(
        () => writes.createManualEntry(
          deviceId: 'device-1',
          startAt: DateTime(2026, 7, 1, 9, 30),
          endAt: DateTime(2026, 7, 1, 10, 30),
          description: 'Standup',
        ),
      );

      await tester.pumpWidget(makeApp([entry!]));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Standup'));
      await tester.pumpAndSettle();

      // TextButton index 1 is start-time; confirm its pre-filled label first.
      final startTimeButton = tester.widget<TextButton>(find.byType(TextButton).at(1));
      final startTimeLabelBefore = (startTimeButton.child! as Text).data;

      // Pick a start date and accept the pre-filled initialDate (today isn't
      // relevant here -- the point is confirming a date doesn't reset time).
      await tester.tap(find.byType(TextButton).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      final startTimeLabelAfter =
          ((tester.widget(find.byType(TextButton).at(1)) as TextButton).child! as Text).data;
      expect(startTimeLabelAfter, startTimeLabelBefore);
    },
  );

  testWidgets(
    'picking a start date pulls the end date onto the same day, keeping the end time',
    (tester) async {
      // Fixed timestamps (not "now"): the assertion is about the end date
      // landing on the picked start date, so both sides must be pinned.
      final entry = await tester.runAsync(
        () => writes.createManualEntry(
          deviceId: 'device-1',
          startAt: DateTime(2026, 7, 1, 9, 30),
          endAt: DateTime(2026, 7, 1, 10, 30),
          description: 'Standup',
        ),
      );

      await tester.pumpWidget(makeApp([entry!]));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Standup'));
      await tester.pumpAndSettle();

      // 0: start-date, 1: start-time, 2: end-date, 3: end-time.
      String label(int index) =>
          ((tester.widget(find.byType(TextButton).at(index)) as TextButton).child! as Text).data!;

      final startDateBefore = label(0);
      final endTimeBefore = label(3);

      // Navigate to the 2nd of July 2026 -- same calendar page as the entry's
      // own date, so no month navigation is needed, and a day the end is not
      // on yet (it starts on the 1st).
      await tester.tap(find.byType(TextButton).first);
      await tester.pumpAndSettle();
      expect(find.byType(DatePickerDialog), findsOneWidget);
      await tester.tap(
        find.descendant(of: find.byType(DatePickerDialog), matching: find.text('2')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(label(0), isNot(startDateBefore), reason: 'start date should have moved to the 2nd');
      expect(
        label(2),
        label(0),
        reason: 'end date should follow the picked start date onto the same day',
      );
      expect(label(3), endTimeBefore, reason: 'the end time itself must not change');
    },
  );

  testWidgets(
    'picking a start time shifts the end time by the same amount, preserving the duration',
    (tester) async {
      final entry = await tester.runAsync(
        () => writes.createManualEntry(
          deviceId: 'device-1',
          startAt: DateTime(2026, 7, 1, 9, 30),
          endAt: DateTime(2026, 7, 1, 10, 0),
          description: 'Standup',
        ),
      );

      await tester.pumpWidget(makeApp([entry!]));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Standup'));
      await tester.pumpAndSettle();

      String label(int index) =>
          ((tester.widget(find.byType(TextButton).at(index)) as TextButton).child! as Text).data!;

      expect(label(1), '09:30');
      expect(label(3), '10:00');

      // Confirming the time picker's pre-filled default would prove nothing (a
      // zero-length shift is indistinguishable from no wiring at all -- see the
      // feature memory's note on this), so switch the picker into text-input
      // mode and type a genuinely different start time. 10:45 stays inside the
      // 1-12 hour field the picker shows under this test's 'en' locale (a
      // 24-hour value like 14 fails its validator, leaving the dialog open and
      // the time unchanged) and keeps the pre-filled AM period, so no period
      // toggle is needed.
      await tester.tap(find.byType(TextButton).at(1));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Switch to text input mode'));
      await tester.pumpAndSettle();

      // Scope to the picker: a bare find.byType(TextField) would hit the
      // description field of the dialog underneath first.
      final pickerFields = find.descendant(
        of: find.byType(TimePickerDialog),
        matching: find.byType(TextField),
      );
      await tester.enterText(pickerFields.at(0), '10');
      await tester.enterText(pickerFields.at(1), '45');
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(label(1), '10:45');
      expect(
        label(3),
        '11:15',
        reason: 'the end should move with the start, keeping the 30-minute duration',
      );
    },
  );
}
