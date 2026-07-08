import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/data/drift/database.dart';
import 'package:hickory/data/drift/time_entry_extensions.dart';

TimeEntry _entry({
  required DateTime startAt,
  DateTime? endAt,
  DateTime? pausedAt,
  int totalPausedSeconds = 0,
}) {
  final now = DateTime.utc(2026, 7, 1);
  return TimeEntry(
    id: 'e1',
    startAt: startAt,
    endAt: endAt,
    pausedAt: pausedAt,
    totalPausedSeconds: totalPausedSeconds,
    source: 'manual',
    deviceId: 'dev_a',
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  test('stopped entry: worked duration is endAt minus startAt minus paused time', () {
    final entry = _entry(
      startAt: DateTime.utc(2026, 7, 7, 9),
      endAt: DateTime.utc(2026, 7, 7, 11),
      totalPausedSeconds: 600, // 10 minutes
    );

    expect(entry.workedDuration, const Duration(hours: 1, minutes: 50));
  });

  test('paused entry: worked duration is frozen at pausedAt, ignoring time since', () {
    final entry = _entry(
      startAt: DateTime.utc(2026, 7, 7, 9),
      pausedAt: DateTime.utc(2026, 7, 7, 10),
    );

    expect(entry.workedDuration, const Duration(hours: 1));
  });

  test('running entry: worked duration counts up to now, minus prior paused time', () {
    final entry = _entry(
      startAt: DateTime.now().toUtc().subtract(const Duration(minutes: 5)),
      totalPausedSeconds: 60,
    );

    final duration = entry.workedDuration;
    expect(duration.inSeconds, greaterThanOrEqualTo(4 * 60));
    expect(duration.inSeconds, lessThanOrEqualTo(5 * 60));
  });
}
