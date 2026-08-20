import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/core/di/app_settings_provider.dart';
import 'package:hickory/core/di/break_rule_tiers_provider.dart';
import 'package:hickory/core/di/jira_providers.dart';
import 'package:hickory/core/theme/app_theme.dart';
import 'package:hickory/data/drift/database.dart';
import 'package:hickory/data/drift/tables/jira_worklogs_table.dart';
import 'package:hickory/features/entries/entries_list.dart';
import 'package:hickory/features/entries/entries_location.dart';
import 'package:hickory/features/projects/projects_providers.dart';
import 'package:hickory/features/timer/timer_providers.dart';
import 'package:hickory/l10n/app_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';

TimeEntry _entry({
  required String id,
  required DateTime startAt,
  required DateTime endAt,
  int totalPausedSeconds = 0,
  String? jiraTicketKey,
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
    jiraTicketKey: jiraTicketKey,
    createdAt: now,
    updatedAt: now,
  );
}

JiraWorklogRow _worklog({required String entryId, required String status, String? lastError}) =>
    JiraWorklogRow(
      id: entryId,
      syncedTicketKey: null,
      jiraWorklogId: null,
      status: status,
      lastError: lastError,
      syncedAt: null,
    );

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
  // Month names go through intl's DateFormat.MMMM, which throws unless the
  // locale data is loaded (the all-numeric date styles never needed it).
  setUpAll(() => initializeDateFormatting('en'));

  Widget makeApp(
    List<TimeEntry> entries, {
    List<BreakRuleTier> tiers = const [],
    bool countPausedTimeAsBreak = false,
    EntriesLocation? location,
    Map<String, JiraWorklogRow> jiraWorklogs = const {},
  }) => ProviderScope(
        overrides: [
          if (location != null)
            entriesLocationControllerProvider.overrideWith(() => _FixedLocation(location)),
          allEntriesProvider.overrideWith((ref) => Stream.value(entries)),
          activeProjectsProvider.overrideWith((ref) => Stream.value(const [])),
          jiraWorklogsByEntryIdProvider.overrideWith((ref) => Stream.value(jiraWorklogs)),
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
          // The list reads its muted and accent colors from HickoryColors,
          // which only exists as a ThemeExtension on the app's own theme.
          theme: AppTheme.light,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: const Scaffold(body: EntriesList()),
        ),
      );

  // A day's sums sit in the same Row as its label. Scoping to that Row keeps an
  // assertion about one day from also matching a rolled-up row's identical
  // numbers. Day sub-headers aren't tappable, so this is a Row, not an InkWell.
  Finder row(String label) =>
      find.ancestor(of: find.text(label), matching: find.byType(Row));

  testWidgets('groups entries under Today/Yesterday headers with totals', (tester) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day, 9);
    final yesterday = today.subtract(const Duration(days: 1));
    await tester.pumpWidget(
      makeApp(
        [
          _entry(id: '1', startAt: today, endAt: today.add(const Duration(hours: 1))),
          _entry(id: '2', startAt: yesterday, endAt: yesterday.add(const Duration(minutes: 30))),
        ],
      ),
    );
    await tester.pumpAndSettle();

    // Label and total are separate widgets now, so each is asserted on its own
    // row. The '24h' settings override above maps to TimeFormatStyle.h24, which
    // hides seconds in both the header total and the entry row's duration.
    expect(find.text('Today'), findsOneWidget);
    expect(find.descendant(of: row('Today'), matching: find.text('01:00')), findsOneWidget);
    expect(find.text('Yesterday'), findsOneWidget);
    expect(
      find.descendant(of: row('Yesterday'), matching: find.text('00:30')),
      findsOneWidget,
    );
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
      expect(tester.widget<Card>(find.byType(Card)).clipBehavior, Clip.antiAlias);
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

    expect(
      find.descendant(of: row('Today'), matching: find.text('Break: 01:00')),
      findsOneWidget,
    );
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

      expect(
        find.descendant(of: row('Today'), matching: find.text('Break: 00:10')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: row('Today'), matching: find.byIcon(Icons.warning_amber_rounded)),
        findsOneWidget,
      );

    },
  );

  testWidgets('a rolled-up row marks that a day below it fell short', (tester) async {
    await tester.pumpWidget(
      makeApp(
        [
          _entry(id: '1', startAt: DateTime(2024, 5, 6, 8), endAt: DateTime(2024, 5, 6, 15)),
        ],
        tiers: [_tier(afterMinutes: 360, requiredBreakMinutes: 30)],
        location: const EntriesYearsLocation(),
      ),
    );
    await tester.pumpAndSettle();

    // A marker with a counting tooltip, rather than the day's own triangle:
    // one offending day would otherwise shout from every level above it.
    expect(find.byTooltip('1 day with a break that is too short'), findsOneWidget);
    expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);
  });

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

    expect(
      find.descendant(of: row('Today'), matching: find.text('Break: 00:30')),
      findsOneWidget,
    );
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

      expect(
        find.descendant(of: row('Today'), matching: find.text('Break: 00:10')),
        findsOneWidget,
      );
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

      expect(
      find.descendant(of: row('Today'), matching: find.text('Break: 00:00')),
      findsOneWidget,
    );
    },
  );

  testWidgets('lists years and nothing deeper at the top level', (tester) async {
    await tester.pumpWidget(
      makeApp(
        [_entry(id: '1', startAt: DateTime(2024, 5, 6, 9), endAt: DateTime(2024, 5, 6, 10))],
        location: const EntriesYearsLocation(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('2024'), findsOneWidget);
    expect(find.text('May'), findsNothing);
    expect(find.byType(Dismissible), findsNothing);
    // No path to show at the top, so no breadcrumb eats the space.
    expect(find.byTooltip('Up one level'), findsNothing);
  });

  testWidgets('tapping a year drills into its months', (tester) async {
    await tester.pumpWidget(
      makeApp(
        [_entry(id: '1', startAt: DateTime(2024, 5, 6, 9), endAt: DateTime(2024, 5, 6, 10))],
        location: const EntriesYearsLocation(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('2024'));
    await tester.pumpAndSettle();

    expect(find.text('May'), findsOneWidget);
    // One level at a time: the weeks below are a further tap away.
    expect(find.textContaining('Week 19'), findsNothing);
    expect(find.byTooltip('Up one level'), findsOneWidget);
  });

  testWidgets('a year row carries worked and break sums', (tester) async {
    await tester.pumpWidget(
      makeApp(
        [
          _entry(id: '1', startAt: DateTime(2024, 5, 6, 8), endAt: DateTime(2024, 5, 6, 10)),
          _entry(id: '2', startAt: DateTime(2024, 5, 6, 11), endAt: DateTime(2024, 5, 6, 12)),
        ],
        location: const EntriesYearsLocation(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('03:00'), findsOneWidget);
    expect(find.text('Break: 01:00'), findsOneWidget);
  });

  testWidgets('drills back up through the breadcrumb', (tester) async {
    // 2024-05-06 is a Monday, so its week sits entirely inside May.
    await tester.pumpWidget(
      makeApp(
        [_entry(id: '1', startAt: DateTime(2024, 5, 6, 9), endAt: DateTime(2024, 5, 6, 10))],
        location: EntriesWeekLocation(monday: DateTime(2024, 5, 6), year: 2024, month: 5),
      ),
    );
    await tester.pumpAndSettle();

    // Deepest level: the day and its entry, no chevron rows.
    expect(find.byType(Dismissible), findsOneWidget);

    await tester.tap(find.byTooltip('Up one level'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Week 19'), findsOneWidget);
    expect(find.byType(Dismissible), findsNothing);

    // The breadcrumb's year segment jumps two levels at once.
    await tester.tap(find.text('2024'));
    await tester.pumpAndSettle();
    expect(find.text('May'), findsOneWidget);
  });

  testWidgets("shows the stored Jira error in the failed entry's tooltip", (tester) async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day, 9);
    await tester.pumpWidget(
      makeApp(
        [
          _entry(
            id: '1',
            startAt: start,
            endAt: start.add(const Duration(hours: 1)),
            jiraTicketKey: 'ABC-1',
          ),
        ],
        jiraWorklogs: {
          '1': _worklog(
            entryId: '1',
            status: JiraWorklogStatus.error,
            lastError: 'Issue does not exist or you do not have permission',
          ),
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byTooltip('Issue does not exist or you do not have permission'),
      findsOneWidget,
    );
  });

  testWidgets('falls back to the generic message when no Jira error is stored', (tester) async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day, 9);
    await tester.pumpWidget(
      makeApp(
        [
          _entry(
            id: '1',
            startAt: start,
            endAt: start.add(const Duration(hours: 1)),
            jiraTicketKey: 'ABC-1',
          ),
        ],
        jiraWorklogs: {'1': _worklog(entryId: '1', status: JiraWorklogStatus.error)},
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('Jira booking failed'), findsOneWidget);
  });

  testWidgets("opens on the current week, showing today's entries", (tester) async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day, 9);
    await tester.pumpWidget(
      makeApp([
        _entry(id: '1', startAt: start, endAt: start.add(const Duration(hours: 1))),
      ]),
    );
    await tester.pumpAndSettle();

    expect(find.text('Today'), findsOneWidget);
    expect(find.byType(Dismissible), findsOneWidget);
  });
}

/// Pins the location so a test doesn't silently depend on today's date.
class _FixedLocation extends EntriesLocationController {
  _FixedLocation(this._initial);

  final EntriesLocation? _initial;

  @override
  EntriesLocation? build() => _initial;
}
