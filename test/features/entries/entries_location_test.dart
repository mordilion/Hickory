import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/data/drift/database.dart';
import 'package:hickory/features/entries/entries_location.dart';
import 'package:hickory/features/entries/entry_tree.dart';

TimeEntry _entry({
  required String id,
  required DateTime startAt,
  required DateTime endAt,
}) {
  final now = DateTime.utc(2026, 1, 1);
  return TimeEntry(
    id: id,
    projectId: null,
    description: null,
    startAt: startAt,
    endAt: endAt,
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

void main() {
  // 2026-08-18 is a Tuesday in ISO week 34 (Monday 2026-08-17); 2026-07-08 is
  // in week 28. Both fixed so the tests never depend on the real clock.
  final thisWeek = DateTime(2026, 8, 18, 9);
  final julyEntry = DateTime(2026, 7, 8, 9);

  List<EntryYearGroup> treeOf(List<DateTime> starts) => buildEntryTree([
    for (final (index, start) in starts.indexed)
      _entry(
        id: '$index',
        startAt: start,
        endAt: start.add(const Duration(hours: 2)),
      ),
  ], tiers: const []);

  group('initialLocation', () {
    test('opens the week containing today', () {
      final location = initialLocation(
        treeOf([thisWeek, julyEntry]),
        DateTime(2026, 8, 18),
      );

      expect(
        location,
        EntriesWeekLocation(
          monday: DateTime(2026, 8, 17),
          year: 2026,
          month: 8,
        ),
      );
    });

    test('opens the newest week when today has none', () {
      final location = initialLocation(
        treeOf([julyEntry]),
        DateTime(2026, 8, 18),
      );

      expect(
        location,
        EntriesWeekLocation(monday: DateTime(2026, 7, 6), year: 2026, month: 7),
      );
    });

    test('falls back to the years list when there is nothing at all', () {
      expect(
        initialLocation(const [], DateTime(2026, 8, 18)),
        const EntriesYearsLocation(),
      );
    });
  });

  group('viewFor', () {
    test('resolves each level', () {
      final tree = treeOf([thisWeek, julyEntry]);

      expect(
        viewFor(tree, const EntriesYearsLocation()),
        isA<EntriesYearsView>(),
      );
      expect(
        viewFor(tree, const EntriesYearLocation(2026)),
        isA<EntriesMonthsView>(),
      );
      expect(
        viewFor(tree, const EntriesMonthLocation(2026, 7)),
        isA<EntriesWeeksView>(),
      );
      final week = viewFor(
        tree,
        EntriesWeekLocation(monday: DateTime(2026, 7, 6), year: 2026, month: 7),
      );
      expect((week as EntriesWeekView).week.isoWeek, 28);
    });

    test(
      'falls back to the nearest surviving ancestor when a node is gone',
      () {
        // Only July survives -- August's week was deleted out from under us.
        final tree = treeOf([julyEntry]);

        final view = viewFor(
          tree,
          EntriesWeekLocation(
            monday: DateTime(2026, 8, 17),
            year: 2026,
            month: 8,
          ),
        );
        // The month is gone too, so the year list is the nearest thing left.
        expect(view, isA<EntriesMonthsView>());
        expect((view as EntriesMonthsView).year.year, 2026);
      },
    );

    test('falls back to the years list when even the year is gone', () {
      expect(
        viewFor(treeOf([julyEntry]), const EntriesYearLocation(2019)),
        isA<EntriesYearsView>(),
      );
    });
  });

  group('parentOf', () {
    test('walks one level up and stops at the years list', () {
      expect(
        parentOf(
          EntriesWeekLocation(
            monday: DateTime(2026, 8, 17),
            year: 2026,
            month: 8,
          ),
        ),
        const EntriesMonthLocation(2026, 8),
      );
      expect(
        parentOf(const EntriesMonthLocation(2026, 8)),
        const EntriesYearLocation(2026),
      );
      expect(
        parentOf(const EntriesYearLocation(2026)),
        const EntriesYearsLocation(),
      );
      expect(parentOf(const EntriesYearsLocation()), isNull);
    });
  });
}
