import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/core/di/app_settings_provider.dart';
import 'package:hickory/core/di/break_rule_tiers_provider.dart';
import 'package:hickory/core/di/jira_providers.dart';
import 'package:hickory/data/drift/database.dart';
import 'package:hickory/features/entries/entries_list.dart';
import 'package:hickory/features/entries/entry_tree.dart';
import 'package:hickory/features/entries/entry_tree_expansion.dart';
import 'package:hickory/features/projects/projects_providers.dart';
import 'package:hickory/features/timer/timer_providers.dart';
import 'package:hickory/l10n/app_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';

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
  // Month names go through intl's DateFormat.MMMM, which throws unless the
  // locale data is loaded (the all-numeric date styles never needed it).
  setUpAll(() => initializeDateFormatting('en'));

  Widget makeApp(
    List<TimeEntry> entries, {
    List<BreakRuleTier> tiers = const [],
    bool countPausedTimeAsBreak = false,
    Set<String>? expanded,
  }) => ProviderScope(
        overrides: [
          if (expanded != null)
            entryTreeExpansionProvider.overrideWith(() => _FixedExpansion(expanded)),
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

  // Break and worked sums appear on the year, month and week rows as well as
  // the day's, so a bare find.text matches four times over single-day data.
  // Scope to the row carrying [label] to assert about one level only.
  Finder row(String label) =>
      find.ancestor(of: find.text(label), matching: find.byType(InkWell));

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
        // Both days explicitly: the default seed opens only today's path, and
        // on a Monday (or the 1st) yesterday sits in a collapsed week or month.
        expanded: {...defaultExpandedKeys(today), ...defaultExpandedKeys(yesterday)},
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
        ], expanded: {...defaultExpandedKeys(today), ...defaultExpandedKeys(yesterday)}),
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
      // The warning bubbles up, so a collapsed list still shows where to look.
      expect(
        find.descendant(
          of: row('${today.year}'),
          matching: find.byIcon(Icons.warning_amber_rounded),
        ),
        findsOneWidget,
      );
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

  testWidgets('shows only year rows when everything is collapsed', (tester) async {
    await tester.pumpWidget(
      makeApp(
        [_entry(id: '1', startAt: DateTime(2024, 5, 6, 9), endAt: DateTime(2024, 5, 6, 10))],
        expanded: const <String>{},
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('2024'), findsOneWidget);
    expect(find.text('May'), findsNothing);
    expect(find.byType(Dismissible), findsNothing);
  });

  testWidgets('tapping a year row reveals its months', (tester) async {
    await tester.pumpWidget(
      makeApp(
        [_entry(id: '1', startAt: DateTime(2024, 5, 6, 9), endAt: DateTime(2024, 5, 6, 10))],
        expanded: const <String>{},
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('2024'));
    await tester.pumpAndSettle();

    expect(find.text('May'), findsOneWidget);
    // One level only: the week below stays collapsed.
    expect(find.textContaining('Week 19'), findsNothing);
  });

  testWidgets('a year row carries worked and break sums', (tester) async {
    await tester.pumpWidget(
      makeApp(
        [
          _entry(id: '1', startAt: DateTime(2024, 5, 6, 8), endAt: DateTime(2024, 5, 6, 10)),
          _entry(id: '2', startAt: DateTime(2024, 5, 6, 11), endAt: DateTime(2024, 5, 6, 12)),
        ],
        expanded: const <String>{},
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('03:00'), findsOneWidget);
    expect(find.text('Break: 01:00'), findsOneWidget);
  });

  testWidgets("the default expansion shows today's entries", (tester) async {
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

/// Pins the expansion set so a test doesn't silently depend on today's date.
class _FixedExpansion extends EntryTreeExpansion {
  _FixedExpansion(this._initial);

  final Set<String> _initial;

  @override
  Set<String> build() => _initial;
}
