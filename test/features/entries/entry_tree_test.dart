import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/data/drift/database.dart';
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

BreakRuleTier _tier({
  required int afterMinutes,
  required int requiredBreakMinutes,
}) {
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

/// ISO week 53 of 2026 runs 2026-12-28 to 2027-01-03, so these two entries
/// share a week but sit in different months *and* years.
List<TimeEntry> _splitWeekEntries() => [
  _entry(
    id: '1',
    startAt: DateTime(2026, 12, 30, 9),
    endAt: DateTime(2026, 12, 30, 11),
  ),
  _entry(
    id: '2',
    startAt: DateTime(2027, 1, 2, 9),
    endAt: DateTime(2027, 1, 2, 10),
  ),
];

void main() {
  group('buildEntryTree', () {
    test('returns an empty list for no entries', () {
      expect(buildEntryTree(const [], tiers: const []), isEmpty);
    });

    test('nests year > month > week > day, newest first at every level', () {
      final tree = buildEntryTree([
        _entry(
          id: '1',
          startAt: DateTime(2025, 12, 1, 9),
          endAt: DateTime(2025, 12, 1, 10),
        ),
        _entry(
          id: '2',
          startAt: DateTime(2026, 8, 18, 9),
          endAt: DateTime(2026, 8, 18, 10),
        ),
        _entry(
          id: '3',
          startAt: DateTime(2026, 8, 11, 9),
          endAt: DateTime(2026, 8, 11, 10),
        ),
      ], tiers: const []);

      expect(tree.map((y) => y.year), [2026, 2025]);
      final august = tree.first.months.single;
      expect(august.month, 8);
      expect(august.weeks.map((w) => w.isoWeek), [34, 33]);
      expect(august.weeks.first.days.single.day, DateTime(2026, 8, 18));
    });

    test('sums worked and break time up every level', () {
      final tree = buildEntryTree([
        _entry(
          id: '1',
          startAt: DateTime(2026, 8, 18, 8),
          endAt: DateTime(2026, 8, 18, 10),
        ),
        _entry(
          id: '2',
          startAt: DateTime(2026, 8, 18, 11),
          endAt: DateTime(2026, 8, 18, 12),
        ),
        _entry(
          id: '3',
          startAt: DateTime(2026, 8, 11, 9),
          endAt: DateTime(2026, 8, 11, 10),
        ),
      ], tiers: const []);

      final year = tree.single;
      expect(year.totalDuration, const Duration(hours: 4));
      // The one-hour gap on the 18th is that day's break; the 11th has none.
      expect(year.breakDuration, const Duration(hours: 1));
      expect(year.months.single.totalDuration, year.totalDuration);
      expect(
        year.months.single.weeks.fold(
          Duration.zero,
          (Duration sum, week) => sum + week.totalDuration,
        ),
        year.totalDuration,
      );
    });

    test('splits a week that crosses a month boundary into two nodes', () {
      final tree = buildEntryTree(_splitWeekEntries(), tiers: const []);

      expect(tree.map((y) => y.year), [2027, 2026]);
      final januaryWeek = tree.first.months.single.weeks.single;
      final decemberWeek = tree.last.months.single.weeks.single;
      expect(januaryWeek.isoWeek, 53);
      expect(decemberWeek.isoWeek, 53);

      // Each node covers only the days inside its own month, so month totals
      // stay true to the calendar month.
      expect(januaryWeek.firstDay, DateTime(2027, 1, 2));
      expect(januaryWeek.lastDay, DateTime(2027, 1, 2));
      expect(januaryWeek.totalDuration, const Duration(hours: 1));
      expect(decemberWeek.firstDay, DateTime(2026, 12, 30));
      expect(decemberWeek.totalDuration, const Duration(hours: 2));
    });

    test('gives the two halves of a split week distinct expansion keys', () {
      final tree = buildEntryTree(_splitWeekEntries(), tiers: const []);
      final januaryWeek = tree.first.months.single.weeks.single;
      final decemberWeek = tree.last.months.single.weeks.single;

      expect(januaryWeek.monday, decemberWeek.monday);
      expect(
        weekTreeKey(januaryWeek.monday, januaryWeek.year, januaryWeek.month),
        isNot(
          weekTreeKey(
            decemberWeek.monday,
            decemberWeek.year,
            decemberWeek.month,
          ),
        ),
      );
    });

    test('counts days that fall short of the break rule at every level', () {
      final tree = buildEntryTree(
        [
          // 7h straight, no break -> short.
          _entry(
            id: '1',
            startAt: DateTime(2026, 8, 18, 8),
            endAt: DateTime(2026, 8, 18, 15),
          ),
          // 7h with a 1h gap -> fine.
          _entry(
            id: '2',
            startAt: DateTime(2026, 8, 11, 8),
            endAt: DateTime(2026, 8, 11, 12),
          ),
          _entry(
            id: '3',
            startAt: DateTime(2026, 8, 11, 13),
            endAt: DateTime(2026, 8, 11, 16),
          ),
        ],
        tiers: [_tier(afterMinutes: 360, requiredBreakMinutes: 30)],
      );

      final year = tree.single;
      expect(year.insufficientBreakDays, 1);
      expect(year.months.single.insufficientBreakDays, 1);
      expect(year.months.single.weeks.first.insufficientBreakDays, 1);
      expect(year.months.single.weeks.last.insufficientBreakDays, 0);
    });
  });
}
