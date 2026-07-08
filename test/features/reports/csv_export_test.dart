import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/data/drift/database.dart';
import 'package:hickory/features/reports/csv_export.dart';

void main() {
  test('entriesToCsv writes one row per finished entry with a header', () {
    final now = DateTime.utc(2026, 7, 1);
    final project = Project(
      id: 'p1',
      name: 'Client X',
      colorHex: '#5B8DEF',
      archived: false,
      billable: true,
      hourlyRateCents: 10000,
      currency: 'EUR',
      createdAt: now,
      updatedAt: now,
    );
    final entry = TimeEntry(
      id: 'e1',
      projectId: 'p1',
      description: 'Design review',
      startAt: DateTime.utc(2026, 7, 7, 9),
      endAt: DateTime.utc(2026, 7, 7, 10, 30),
      source: 'manual',
      deviceId: 'dev_a',
      createdAt: now,
      updatedAt: now,
      totalPausedSeconds: 0,
    );

    final csv = entriesToCsv([entry], [project]);
    final lines = csv.trim().split('\r\n');

    expect(lines, hasLength(2));
    expect(lines[0], contains('Datum'));
    expect(lines[1], contains('Client X'));
    expect(lines[1], contains('Design review'));
    expect(lines[1], contains('1.50')); // 1h30m
    expect(lines[1], contains('150.00')); // 1.5h * 100.00/hr
  });

  test('a still-running entry (no endAt) is skipped', () {
    final now = DateTime.utc(2026, 7, 1);
    final running = TimeEntry(
      id: 'e1',
      startAt: DateTime.utc(2026, 7, 7, 9),
      source: 'manual',
      deviceId: 'dev_a',
      createdAt: now,
      updatedAt: now,
      totalPausedSeconds: 0,
    );

    final csv = entriesToCsv([running], const []);

    expect(csv.trim().split('\r\n'), hasLength(1)); // header only
  });

  test('entriesToCsv excludes paused time from the exported hours', () {
    final now = DateTime.utc(2026, 7, 1);
    final project = Project(
      id: 'p1',
      name: 'Client X',
      colorHex: '#5B8DEF',
      archived: false,
      billable: true,
      hourlyRateCents: 10000,
      currency: 'EUR',
      createdAt: now,
      updatedAt: now,
    );
    final entry = TimeEntry(
      id: 'e1',
      projectId: 'p1',
      description: 'Design review',
      startAt: DateTime.utc(2026, 7, 7, 9),
      endAt: DateTime.utc(2026, 7, 7, 11), // 2h wall-clock
      totalPausedSeconds: 30 * 60, // 30 minutes paused
      source: 'manual',
      deviceId: 'dev_a',
      createdAt: now,
      updatedAt: now,
    );

    final csv = entriesToCsv([entry], [project]);
    final lines = csv.trim().split('\r\n');

    expect(lines[1], contains('1.50')); // 2h - 30min = 1.5h
  });
}
