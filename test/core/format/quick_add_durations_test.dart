import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/core/format/quick_add_durations.dart';
import 'package:hickory/data/drift/database.dart';

void main() {
  test('parseQuickAddDurations returns the default list when raw is null', () {
    expect(parseQuickAddDurations(null), [15, 30, 45, 60]);
  });

  test(
    'parseQuickAddDurations returns an empty list for an explicitly empty raw '
    '(removing every preset is a deliberate, supported choice)',
    () {
      expect(parseQuickAddDurations(''), <int>[]);
      expect(parseQuickAddDurations('   '), <int>[]);
    },
  );

  test('formatQuickAddDurations of an empty list round-trips to an empty list', () {
    expect(parseQuickAddDurations(formatQuickAddDurations(const [])), <int>[]);
  });

  test('parseQuickAddDurations parses and sorts a comma-separated list', () {
    expect(parseQuickAddDurations('60,15,45'), [15, 45, 60]);
  });

  test('parseQuickAddDurations drops invalid and non-positive entries', () {
    expect(parseQuickAddDurations('15,abc,-5,0,30'), [15, 30]);
  });

  test('parseQuickAddDurations de-duplicates values', () {
    expect(parseQuickAddDurations('15,15,30'), [15, 30]);
  });

  test('parseQuickAddDurations falls back to defaults when nothing valid remains', () {
    expect(parseQuickAddDurations('abc,-5,0'), [15, 30, 45, 60]);
  });

  test('formatQuickAddDurations joins minutes with commas', () {
    expect(formatQuickAddDurations([15, 30, 45]), '15,30,45');
  });

  test('quickAddDurations extension parses the settings row field', () {
    final row = AppSettingsRow(
      id: 'default',
      dateFormat: 'iso',
      timeFormat: '24h',
      quickAddDurationsMinutes: '20,40',
      countPausedTimeAsBreak: false,
      updatedAt: DateTime.utc(2026, 1, 1),
    );
    expect(row.quickAddDurations, [20, 40]);
  });

  test('quickAddDurations extension falls back to defaults for a null row', () {
    const AppSettingsRow? row = null;
    expect(row.quickAddDurations, [15, 30, 45, 60]);
  });
}
