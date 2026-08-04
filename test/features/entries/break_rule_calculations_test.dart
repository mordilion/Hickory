import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/data/drift/database.dart';
import 'package:hickory/features/entries/break_rule_calculations.dart';

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
  group('dayBreakDuration', () {
    test('returns zero for no entries', () {
      expect(dayBreakDuration(const []), Duration.zero);
    });

    test('returns zero for a single entry', () {
      final entries = [
        _entry(id: '1', startAt: DateTime(2026, 8, 1, 9), endAt: DateTime(2026, 8, 1, 10)),
      ];
      expect(dayBreakDuration(entries), Duration.zero);
    });

    test('sums the gap between two entries', () {
      final entries = [
        _entry(id: '1', startAt: DateTime(2026, 8, 1, 9), endAt: DateTime(2026, 8, 1, 12)),
        _entry(id: '2', startAt: DateTime(2026, 8, 1, 13), endAt: DateTime(2026, 8, 1, 17)),
      ];
      expect(dayBreakDuration(entries), const Duration(hours: 1));
    });

    test('sums gaps across more than two entries, regardless of input order', () {
      final entries = [
        // Deliberately out of chronological order.
        _entry(id: '3', startAt: DateTime(2026, 8, 1, 15), endAt: DateTime(2026, 8, 1, 17)),
        _entry(id: '1', startAt: DateTime(2026, 8, 1, 9), endAt: DateTime(2026, 8, 1, 11)),
        _entry(id: '2', startAt: DateTime(2026, 8, 1, 11, 30), endAt: DateTime(2026, 8, 1, 14)),
      ];
      // Gap 1->2: 11:00-11:30 = 30min. Gap 2->3: 14:00-15:00 = 1h.
      expect(dayBreakDuration(entries), const Duration(hours: 1, minutes: 30));
    });

    test('back-to-back entries contribute a zero gap', () {
      final entries = [
        _entry(id: '1', startAt: DateTime(2026, 8, 1, 9), endAt: DateTime(2026, 8, 1, 12)),
        _entry(id: '2', startAt: DateTime(2026, 8, 1, 12), endAt: DateTime(2026, 8, 1, 17)),
      ];
      expect(dayBreakDuration(entries), Duration.zero);
    });

    test('ignores totalPausedSeconds by default', () {
      final entries = [
        _entry(
          id: '1',
          startAt: DateTime(2026, 8, 1, 9),
          endAt: DateTime(2026, 8, 1, 12),
          totalPausedSeconds: 600,
        ),
      ];
      expect(dayBreakDuration(entries), Duration.zero);
    });

    test('adds totalPausedSeconds across all entries when includePausedTime is true', () {
      final entries = [
        _entry(
          id: '1',
          startAt: DateTime(2026, 8, 1, 9),
          endAt: DateTime(2026, 8, 1, 12),
          totalPausedSeconds: 300,
        ),
        _entry(
          id: '2',
          startAt: DateTime(2026, 8, 1, 13),
          endAt: DateTime(2026, 8, 1, 17),
          totalPausedSeconds: 120,
        ),
      ];
      // Gap 1->2: 1h, plus 300s + 120s of paused time.
      expect(
        dayBreakDuration(entries, includePausedTime: true),
        const Duration(hours: 1, minutes: 7),
      );
    });

    test('includePausedTime still counts paused time for a single entry', () {
      final entries = [
        _entry(
          id: '1',
          startAt: DateTime(2026, 8, 1, 9),
          endAt: DateTime(2026, 8, 1, 12),
          totalPausedSeconds: 90,
        ),
      ];
      expect(
        dayBreakDuration(entries, includePausedTime: true),
        const Duration(seconds: 90),
      );
    });
  });

  group('requiredBreakForWorked', () {
    test('returns null when there are no tiers', () {
      expect(requiredBreakForWorked(const Duration(hours: 8), const []), isNull);
    });

    test('returns null when worked time is below every tier threshold', () {
      final tiers = [_tier(afterMinutes: 360, requiredBreakMinutes: 30)];
      expect(requiredBreakForWorked(const Duration(hours: 5), tiers), isNull);
    });

    test('returns the smallest tier exactly at its threshold', () {
      final tiers = [
        _tier(afterMinutes: 360, requiredBreakMinutes: 30),
        _tier(afterMinutes: 540, requiredBreakMinutes: 45),
      ];
      expect(
        requiredBreakForWorked(const Duration(hours: 6), tiers),
        const Duration(minutes: 30),
      );
    });

    test('returns the highest tier reached, given unordered tiers', () {
      final tiers = [
        _tier(afterMinutes: 540, requiredBreakMinutes: 45),
        _tier(afterMinutes: 360, requiredBreakMinutes: 30),
      ];
      expect(
        requiredBreakForWorked(const Duration(hours: 10), tiers),
        const Duration(minutes: 45),
      );
    });
  });
}
