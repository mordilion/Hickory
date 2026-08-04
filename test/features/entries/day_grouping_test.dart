import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/data/drift/database.dart';
import 'package:hickory/features/entries/day_grouping.dart';

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
    description: null,
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

void main() {
  test('groups entries by local calendar day, most recent day first', () {
    final entries = [
      _entry(id: '1', startAt: DateTime(2026, 8, 1, 9), endAt: DateTime(2026, 8, 1, 10)),
      _entry(id: '2', startAt: DateTime(2026, 8, 2, 9), endAt: DateTime(2026, 8, 2, 11)),
    ];
    final groups = groupEntriesByDay(entries);
    expect(groups, hasLength(2));
    expect(groups[0].day, DateTime(2026, 8, 2));
    expect(groups[0].entries.single.id, '2');
    expect(groups[1].day, DateTime(2026, 8, 1));
    expect(groups[1].entries.single.id, '1');
  });

  test("sums workedDuration across a day's entries into totalDuration", () {
    final entries = [
      _entry(id: '1', startAt: DateTime(2026, 8, 1, 9), endAt: DateTime(2026, 8, 1, 10)),
      _entry(id: '2', startAt: DateTime(2026, 8, 1, 11), endAt: DateTime(2026, 8, 1, 11, 30)),
    ];
    final groups = groupEntriesByDay(entries);
    expect(groups, hasLength(1));
    expect(groups.single.totalDuration, const Duration(hours: 1, minutes: 30));
  });

  test("computes breakDuration from gaps between a day's entries", () {
    final entries = [
      _entry(id: '1', startAt: DateTime(2026, 8, 1, 9), endAt: DateTime(2026, 8, 1, 12)),
      _entry(id: '2', startAt: DateTime(2026, 8, 1, 13), endAt: DateTime(2026, 8, 1, 17)),
    ];
    final groups = groupEntriesByDay(entries);
    expect(groups, hasLength(1));
    expect(groups.single.breakDuration, const Duration(hours: 1));
  });

  test('keeps multiple entries on the same day together and in input order', () {
    final entries = [
      _entry(id: 'a', startAt: DateTime(2026, 8, 1, 14), endAt: DateTime(2026, 8, 1, 15)),
      _entry(id: 'b', startAt: DateTime(2026, 8, 1, 9), endAt: DateTime(2026, 8, 1, 10)),
    ];
    final groups = groupEntriesByDay(entries);
    expect(groups.single.entries.map((e) => e.id), ['a', 'b']);
  });

  test('returns an empty list for no entries', () {
    expect(groupEntriesByDay(const []), isEmpty);
  });

  test('forwards includePausedTimeInBreak to breakDuration', () {
    final entries = [
      _entry(
        id: '1',
        startAt: DateTime(2026, 8, 1, 9),
        endAt: DateTime(2026, 8, 1, 12),
        totalPausedSeconds: 600,
      ),
      _entry(id: '2', startAt: DateTime(2026, 8, 1, 13), endAt: DateTime(2026, 8, 1, 17)),
    ];

    final withoutPaused = groupEntriesByDay(entries);
    expect(withoutPaused.single.breakDuration, const Duration(hours: 1));

    final withPaused = groupEntriesByDay(entries, includePausedTimeInBreak: true);
    expect(withPaused.single.breakDuration, const Duration(hours: 1, minutes: 10));
  });
}
