import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/features/settings/weekly_target_distribution.dart';

void main() {
  const workWeek = {
    DateTime.monday,
    DateTime.tuesday,
    DateTime.wednesday,
    DateTime.thursday,
    DateTime.friday,
  };

  test('an evenly divisible week splits into equal days', () {
    final result = distributeWeeklyMinutes(2400, workWeek);
    expect(result[DateTime.monday], 480);
    expect(result[DateTime.friday], 480);
    expect(result[DateTime.saturday], 0);
  });

  test('every weekday is present in the result', () {
    final result = distributeWeeklyMinutes(2400, workWeek);
    expect(result.keys.toSet(), {1, 2, 3, 4, 5, 6, 7});
  });

  test('a remainder goes to the earliest days so the week sums exactly', () {
    final result = distributeWeeklyMinutes(2313, workWeek);
    expect(result.values.reduce((a, b) => a + b), 2313);
    expect(result[DateTime.monday], 463);
    expect(result[DateTime.tuesday], 463);
    expect(result[DateTime.wednesday], 463);
    expect(result[DateTime.thursday], 462);
    expect(result[DateTime.friday], 462);
  });

  test('no work days yields an all-zero week', () {
    final result = distributeWeeklyMinutes(2400, const {});
    expect(result.values.every((minutes) => minutes == 0), isTrue);
  });

  test('a negative weekly figure is treated as zero', () {
    final result = distributeWeeklyMinutes(-60, workWeek);
    expect(result.values.every((minutes) => minutes == 0), isTrue);
  });
}
