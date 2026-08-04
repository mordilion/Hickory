import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/core/di/app_settings_provider.dart';
import 'package:hickory/core/di/device_id_provider.dart';
import 'package:hickory/core/di/jira_providers.dart';
import 'package:hickory/core/di/sync_providers.dart';
import 'package:hickory/data/drift/database.dart';
import 'package:hickory/data/sync/sync_log_writer.dart';
import 'package:hickory/data/sync/synced_writes.dart';
import 'package:hickory/features/entries/entries_list.dart';
import 'package:hickory/features/entries/quick_add_bar.dart';
import 'package:hickory/features/projects/projects_providers.dart';
import 'package:hickory/features/timer/timer_providers.dart';
import 'package:hickory/l10n/app_localizations.dart';

Future<void> pumpUntilTrue(
  WidgetTester tester,
  Future<bool> Function() condition, {
  int maxTries = 50,
}) async {
  for (var i = 0; i < maxTries; i++) {
    if (await condition()) return;
    await tester.pump(const Duration(milliseconds: 10));
  }
}

void main() {
  late AppDatabase db;
  late Directory syncRoot;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    syncRoot = Directory.systemTemp.createTempSync('hickory_quick_add_test_');
  });

  tearDown(() async {
    await db.close();
    if (syncRoot.existsSync()) syncRoot.deleteSync(recursive: true);
  });

  // activeProjectsProvider/appSettingsProvider/allEntriesProvider/
  // jiraWorklogsByEntryIdProvider are overridden with static streams rather
  // than derived from a real drift database, so the mounted widget tree
  // never subscribes to a live drift QueryStream. A widget test that does
  // subscribe to one hits a known flutter_test false positive ("A Timer is
  // still pending...", flutter/flutter#144472) at teardown -- already
  // documented as a project-wide constraint in
  // docs/superpowers/plans/2026-07-07-electric-violet-redesign.md ("Avoid
  // adding new testWidgets tests that pump a widget tree wired to real
  // Riverpod providers with live timers/streams"), which hit the same issue
  // and chose to avoid it rather than work around it. deviceIdProvider and
  // syncedWritesProvider stay real (backed by the in-memory db) since
  // they're one-shot Futures, not live streams, so the write path is still
  // genuinely exercised. To verify a created entry actually shows up under
  // EntriesList's "Today" header (not just that it landed in the database),
  // [entries] is passed in and the whole tree is remounted with the updated
  // list after a write -- mirroring entries_list_test.dart's own technique
  // -- rather than watching a live stream.
  Widget makeApp({List<TimeEntry> entries = const []}) => ProviderScope(
        overrides: [
          activeProjectsProvider.overrideWith((ref) => Stream.value(const [])),
          allEntriesProvider.overrideWith((ref) => Stream.value(entries)),
          jiraWorklogsByEntryIdProvider.overrideWith((ref) => Stream.value(const {})),
          appSettingsProvider.overrideWith(
            (ref) => Stream.value(
              AppSettingsRow(
                id: 'default',
                dateFormat: 'iso',
                timeFormat: '24h',
                quickAddDurationsMinutes: '15,30,45,60',
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
          home: Scaffold(
            body: Column(children: [const QuickAddBar(), Expanded(child: EntriesList())]),
          ),
        ),
      );

  testWidgets(
    'tapping a duration chip then submit creates an entry visible under Today',
    (tester) async {
      await tester.pumpWidget(makeApp());
      await tester.pumpAndSettle();

      expect(find.text('No entries yet.'), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, 'Standup');
      await tester.tap(find.text('30 min'));
      await tester.pump();
      await tester.tap(find.byTooltip('Add entry'));
      await tester.pump();

      await pumpUntilTrue(
        tester,
        () async => (await db.select(db.timeEntries).get()).isNotEmpty,
      );

      final createdEntries = await db.select(db.timeEntries).get();
      expect(createdEntries, hasLength(1));
      expect(createdEntries.single.description, 'Standup');
      expect(createdEntries.single.endAt, isNotNull);
      expect(
        createdEntries.single.endAt!.difference(createdEntries.single.startAt),
        const Duration(minutes: 30),
      );

      // Fully unmount, then remount fresh with the newly written entry, so
      // EntriesList (a static Stream.value override, never a live drift
      // stream -- see the makeApp doc comment) reflects it under today's
      // group header. A clean unmount/remount (rather than relying on
      // ProviderScope.overrides updating in place) sidesteps any ambiguity
      // in how Riverpod re-subscribes a StreamProvider override across a
      // widget rebuild.
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      await tester.pumpWidget(makeApp(entries: createdEntries));
      await tester.pumpAndSettle();

      final entryInList = find.descendant(
        of: find.byType(EntriesList),
        matching: find.text('Standup'),
      );
      expect(entryInList, findsOneWidget);
      expect(find.textContaining('Today'), findsOneWidget);
    },
  );

  testWidgets(
    'submitting without touching a duration chip or time button still writes '
    'a range ending near now (not a stale initState-time snapshot)',
    (tester) async {
      // This does not simulate hours of real wall-clock time passing before
      // submit (QuickAddBar uses DateTime.now() directly, not an injectable
      // clock, so flutter_test's fake-async pump clock can't advance it) --
      // it only guards the default/untouched path stays correct. The
      // _rangeTouched refresh in _submit() is exercised either way, since
      // the flag is false here too; a true staleness regression would need
      // a clock abstraction, out of scope for this fix.
      await tester.pumpWidget(makeApp());
      await tester.pumpAndSettle();

      final beforeSubmit = DateTime.now();
      await tester.enterText(find.byType(TextField).first, 'No chip tapped');
      await tester.tap(find.byTooltip('Add entry'));
      await tester.pump();

      await pumpUntilTrue(
        tester,
        () async => (await db.select(db.timeEntries).get()).isNotEmpty,
      );

      final created = (await db.select(db.timeEntries).get()).single;
      expect(created.description, 'No chip tapped');
      expect(
        created.endAt!.difference(beforeSubmit).inSeconds.abs(),
        lessThan(5),
        reason: 'end time should be close to submit time, not a stale snapshot',
      );
    },
  );

  testWidgets('tapping the Jira icon reveals the Jira ticket field', (tester) async {
    await tester.pumpWidget(makeApp());
    await tester.pumpAndSettle();

    expect(find.text('Jira ticket'), findsNothing);
    await tester.tap(find.byTooltip('Link Jira ticket'));
    await tester.pumpAndSettle();
    expect(find.text('Jira ticket'), findsOneWidget);
  });

  testWidgets('tapping the new-project icon opens the new-project dialog', (tester) async {
    await tester.pumpWidget(makeApp());
    await tester.pumpAndSettle();

    expect(find.text('New project'), findsNothing);
    await tester.tap(find.byTooltip('New project'));
    await tester.pumpAndSettle();
    expect(find.text('New project'), findsOneWidget);
  });

  testWidgets(
    'tapping the more icon opens the full dialog prefilled with the current description',
    (tester) async {
      await tester.pumpWidget(makeApp());
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'Retro');
      await tester.tap(find.byTooltip('More options'));
      await tester.pumpAndSettle();

      expect(find.text('Manual entry'), findsOneWidget);
      // Scoped to the dialog, not a bare find.text('Retro') -- the bar's own
      // description field behind the dialog still reads "Retro" too, so an
      // unscoped assertion would pass even if the dialog itself were never
      // actually prefilled.
      final retroInDialog = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Retro'),
      );
      expect(retroInDialog, findsOneWidget);
    },
  );
}
