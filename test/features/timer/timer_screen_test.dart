import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/core/di/app_settings_provider.dart';
import 'package:hickory/core/di/break_rule_tiers_provider.dart';
import 'package:hickory/core/di/database_provider.dart';
import 'package:hickory/core/di/device_id_provider.dart';
import 'package:hickory/core/di/jira_providers.dart';
import 'package:hickory/data/sync/auto_sync_trigger.dart';
import 'package:hickory/core/di/sync_providers.dart';
import 'package:hickory/core/theme/app_theme.dart';
import 'package:hickory/core/widgets/gradient_buttons.dart';
import 'package:hickory/data/drift/database.dart';
import 'package:hickory/data/sync/sync_log_writer.dart';
import 'package:hickory/data/sync/synced_writes.dart';
import 'package:hickory/features/projects/projects_providers.dart';
import 'package:hickory/features/timer/timer_providers.dart';
import 'package:hickory/features/timer/timer_screen.dart';
import 'package:hickory/l10n/app_localizations.dart';

void main() {
  late AppDatabase db;
  late Directory syncRoot;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    syncRoot = Directory.systemTemp.createTempSync('hickory_timer_screen_test_');
  });

  tearDown(() async {
    await db.close();
    if (syncRoot.existsSync()) syncRoot.deleteSync(recursive: true);
  });

  // Same static-override pattern used throughout this codebase's other
  // widget tests (see quick_add_bar_test.dart) to avoid subscribing to a
  // live drift-backed StreamProvider, which hits a known flutter_test
  // false positive at teardown (flutter/flutter#144472).
  // Building the overrides list inline (rather than extracting it to a
  // separately-typed helper) avoids naming `List<Override>` explicitly --
  // riverpod 3.x's `Override` type isn't part of its public export surface,
  // so a standalone `List<Override>` declaration doesn't compile here even
  // though `ProviderScope.overrides` itself is typed that way internally.
  Widget makeApp({TimeEntry? running}) => ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          runningEntryProvider.overrideWith((ref) => Stream.value(running)),
          allEntriesProvider.overrideWith((ref) => Stream.value(const [])),
          activeProjectsProvider.overrideWith((ref) => Stream.value(const [])),
          jiraWorklogsByEntryIdProvider.overrideWith((ref) => Stream.value(const {})),
          // TimerScreen activates the background Jira reconciliation for the
          // app's lifetime. A no-op trigger keeps it out of the test: the
          // real one would reach the live database and leave its debounce
          // timer pending past the end of the test.
          jiraAutoSyncProvider.overrideWithValue(AutoSyncTrigger(() async {})),
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
          syncedWritesProvider.overrideWith(
            (ref) async => SyncedWrites(
              db: db,
              logWriter: SyncLogWriter(syncRoot: syncRoot, deviceId: 'device-1'),
            ),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: const Scaffold(body: TimerScreen()),
        ),
      );

  TimeEntry runningEntry() {
    final now = DateTime.now().toUtc();
    return TimeEntry(
      id: 'running-1',
      projectId: null,
      description: null,
      startAt: now,
      endAt: null,
      pausedAt: null,
      totalPausedSeconds: 0,
      billableOverride: null,
      source: 'manual',
      deviceId: 'device-1',
      jiraTicketKey: null,
      createdAt: now,
      updatedAt: now,
    );
  }

  testWidgets('defaults to Timer mode: start card shown, quick-add bar absent', (tester) async {
    await tester.pumpWidget(makeApp());
    await tester.pumpAndSettle();

    expect(find.text('Start'), findsOneWidget);
    expect(find.text('Add entry'), findsNothing);
  });

  testWidgets(
    'the quick-add submit button is styled exactly like the timer Start button',
    (tester) async {
      await tester.pumpWidget(makeApp());
      await tester.pumpAndSettle();

      // Timer and Manual mode never render at the same time, so the two
      // buttons have to be captured across the mode switch rather than
      // compared side by side in one tree.
      final start = tester.widget<GradientPillButton>(
        find.widgetWithText(GradientPillButton, 'Start'),
      );

      await tester.tap(find.text('Manual'));
      await tester.pumpAndSettle();

      final submit = tester.widget<GradientPillButton>(
        find.widgetWithText(GradientPillButton, 'Add entry'),
      );

      expect(submit.gradient, start.gradient);
      expect(submit.foregroundColor, start.foregroundColor);
      // The glyph is the one intentional difference: same button, different
      // action.
      expect(start.icon, Icons.play_arrow);
      expect(submit.icon, Icons.add);
    },
  );

  testWidgets('tapping Manual (no running entry) swaps to the quick-add bar', (tester) async {
    await tester.pumpWidget(makeApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Manual'));
    await tester.pumpAndSettle();

    expect(find.text('Add entry'), findsOneWidget);
    expect(find.text('What are you working on?'), findsNothing);
  });

  testWidgets('with a running entry, Manual is disabled and Timer mode stays forced', (tester) async {
    await tester.pumpWidget(makeApp(running: runningEntry()));
    await tester.pumpAndSettle();

    // _TimerTabMode is private to timer_screen.dart, so this test can't
    // reference SegmentedButton<_TimerTabMode> by generic type -- it only
    // asserts on the resulting behavior (disabled segments don't respond to
    // taps), not on the widget's internal `enabled` flag directly.
    await tester.tap(find.text('Manual'), warnIfMissed: false);
    await tester.pumpAndSettle();

    // _RunningCard is still showing (its Stop button, a stable marker
    // independent of the live elapsed-time text) and the quick-add bar
    // never appeared.
    expect(find.text('Stop'), findsOneWidget);
    expect(find.text('Add entry'), findsNothing);
  });
}
