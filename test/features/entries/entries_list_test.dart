import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/core/di/app_settings_provider.dart';
import 'package:hickory/core/di/break_rule_tiers_provider.dart';
import 'package:hickory/core/di/jira_providers.dart';
import 'package:hickory/data/drift/database.dart';
import 'package:hickory/features/entries/entries_list.dart';
import 'package:hickory/features/projects/projects_providers.dart';
import 'package:hickory/features/timer/timer_providers.dart';
import 'package:hickory/l10n/app_localizations.dart';

TimeEntry _entry({
  required String id,
  required DateTime startAt,
  required DateTime endAt,
  int totalPausedSeconds = 0,
}) {
  final now = DateTime.utc(2026, 1, 1);
  return TimeEntry(
    id: id,
    projectId: null,
    description: 'Entry $id',
    startAt: startAt,
    endAt: endAt,
    pausedAt: null,
    totalPausedSeconds: totalPausedSeconds,
    billableOverride: null,
    source: 'manual',
    deviceId: 'device-1',
    jiraTicketKey: null,
    createdAt: now,
    updatedAt: now,
  );
}

BreakRuleTier _tier({required int afterMinutes, required int requiredBreakMinutes}) {
  final now = DateTime.utc(2026, 1, 1);
  return BreakRuleTier(
    id: 'tier-$afterMinutes',
    afterMinutes: afterMinutes,
    requiredBreakMinutes: requiredBreakMinutes,
    deviceId: 'device-1',
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  Widget makeApp(
    List<TimeEntry> entries, {
    List<BreakRuleTier> tiers = const [],
    bool countPausedTimeAsBreak = false,
  }) => ProviderScope(
        overrides: [
          allEntriesProvider.overrideWith((ref) => Stream.value(entries)),
          activeProjectsProvider.overrideWith((ref) => Stream.value(const [])),
          jiraWorklogsByEntryIdProvider.overrideWith((ref) => Stream.value(const {})),
          breakRuleTiersProvider.overrideWith((ref) => Stream.value(tiers)),
          appSettingsProvider.overrideWith(
            (ref) => Stream.value(
              AppSettingsRow(
                id: 'default',
                dateFormat: 'iso',
                timeFormat: '24h',
                quickAddDurationsMinutes: '15,30,45,60',
                countPausedTimeAsBreak: countPausedTimeAsBreak,
                updatedAt: DateTime.utc(2026, 1, 1),
              ),
            ),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: const Scaffold(body: EntriesList()),
        ),
      );

  testWidgets('groups entries under Today/Yesterday headers with totals', (tester) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day, 9);
    final yesterday = today.subtract(const Duration(days: 1));
    await tester.pumpWidget(
      makeApp([
        _entry(id: '1', startAt: today, endAt: today.add(const Duration(hours: 1))),
        _entry(id: '2', startAt: yesterday, endAt: yesterday.add(const Duration(minutes: 30))),
      ]),
    );
    await tester.pumpAndSettle();

    // Match the full header text ("Today · 01:00") rather than just the
    // duration substring: with a single entry per day, the day total equals
    // that entry's own duration, so a substring match on the duration alone
    // would also match the entry row's trailing duration text. The '24h'
    // settings override above maps to TimeFormatStyle.h24, which hides
    // seconds in both the header total and the entry row's own duration.
    expect(find.text('Today · 01:00'), findsOneWidget);
    expect(find.text('Yesterday · 00:30'), findsOneWidget);
  });

  testWidgets(
    "groups a single day's entries into one card with a divider between rows",
    (tester) async {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day, 9);
      await tester.pumpWidget(
        makeApp([
          _entry(id: '1', startAt: today, endAt: today.add(const Duration(hours: 1))),
          _entry(
            id: '2',
            startAt: today.add(const Duration(hours: 2)),
            endAt: today.add(const Duration(hours: 3)),
          ),
        ]),
      );
      await tester.pumpAndSettle();

      expect(find.byType(Card), findsOneWidget);
      expect(find.byType(Divider), findsOneWidget);
      final dismissibles = tester.widgetList<Dismissible>(find.byType(Dismissible));
      expect(
        dismissibles.map((d) => d.key),
        containsAll(const [ValueKey('1'), ValueKey('2')]),
      );
    },
  );

  testWidgets(
    'renders one card per day and omits the divider after the last entry in each block',
    (tester) async {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day, 9);
      final yesterday = today.subtract(const Duration(days: 1));
      await tester.pumpWidget(
        makeApp([
          _entry(id: '1', startAt: today, endAt: today.add(const Duration(hours: 1))),
          _entry(
            id: '2',
            startAt: today.add(const Duration(hours: 2)),
            endAt: today.add(const Duration(hours: 3)),
          ),
          _entry(id: '3', startAt: yesterday, endAt: yesterday.add(const Duration(minutes: 30))),
        ]),
      );
      await tester.pumpAndSettle();

      expect(find.byType(Card), findsNWidgets(2));
      expect(find.byType(Divider), findsOneWidget);
      expect(find.byType(Dismissible), findsNWidgets(3));
    },
  );

  testWidgets('shows the empty state when there are no finished entries', (tester) async {
    await tester.pumpWidget(makeApp(const []));
    await tester.pumpAndSettle();
    expect(find.text('No entries yet.'), findsOneWidget);
  });

  testWidgets('shows break time in the day header when no rule is configured', (tester) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day, 9);
    await tester.pumpWidget(
      makeApp([
        _entry(id: '1', startAt: today, endAt: today.add(const Duration(hours: 2))),
        _entry(
          id: '2',
          startAt: today.add(const Duration(hours: 3)),
          endAt: today.add(const Duration(hours: 4)),
        ),
      ]),
    );
    await tester.pumpAndSettle();

    expect(find.text('Break: 01:00'), findsOneWidget);
    expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);
  });

  testWidgets(
    'marks the break red with a warning icon when it is below the required tier, '
    'including for today',
    (tester) async {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day, 9);
      await tester.pumpWidget(
        makeApp(
          [
            _entry(id: '1', startAt: today, endAt: today.add(const Duration(hours: 7))),
            _entry(
              id: '2',
              startAt: today.add(const Duration(hours: 7, minutes: 10)),
              endAt: today.add(const Duration(hours: 8)),
            ),
          ],
          tiers: [_tier(afterMinutes: 360, requiredBreakMinutes: 30)],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Break: 00:10'), findsOneWidget);
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    },
  );

  testWidgets('does not mark the break red when it meets the required tier', (tester) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day, 9);
    await tester.pumpWidget(
      makeApp(
        [
          _entry(id: '1', startAt: today, endAt: today.add(const Duration(hours: 6))),
          _entry(
            id: '2',
            startAt: today.add(const Duration(hours: 6, minutes: 30)),
            endAt: today.add(const Duration(hours: 7, minutes: 30)),
          ),
        ],
        tiers: [_tier(afterMinutes: 360, requiredBreakMinutes: 30)],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Break: 00:30'), findsOneWidget);
    expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);
  });

  testWidgets(
    'includes pause-button time in the displayed break when countPausedTimeAsBreak is on',
    (tester) async {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day, 9);
      await tester.pumpWidget(
        makeApp(
          [
            _entry(
              id: '1',
              startAt: today,
              endAt: today.add(const Duration(hours: 2)),
              totalPausedSeconds: 600,
            ),
          ],
          countPausedTimeAsBreak: true,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Break: 00:10'), findsOneWidget);
    },
  );

  testWidgets(
    'excludes pause-button time from the displayed break when countPausedTimeAsBreak is off',
    (tester) async {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day, 9);
      await tester.pumpWidget(
        makeApp(
          [
            _entry(
              id: '1',
              startAt: today,
              endAt: today.add(const Duration(hours: 2)),
              totalPausedSeconds: 600,
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Break: 00:00'), findsOneWidget);
    },
  );
}
