# Collapsible Entries Hierarchy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the flat day list in `EntriesList` with a collapsible Year › Month › ISO week › Day › Entries hierarchy where every header row shows rolled-up worked and break time on the right.

**Architecture:** All grouping, key building, roll-up and flattening are pure functions in `lib/features/entries/entry_tree.dart` and `lib/core/format/iso_week.dart`, unit-tested without a widget tree. Expansion state is a `Set<String>` of node keys in a keep-alive Riverpod notifier, seeded to the path to today. `EntriesList` flattens (tree, expansion set) into a row list and renders it through the existing `ListView.builder`, so only visible rows are built.

**Tech Stack:** Flutter (stable, version from `pubspec.yaml` — do not pin), Riverpod 3 with `riverpod_generator` codegen, Drift, `intl`, `flutter_test`.

**Spec:** `docs/superpowers/specs/2026-08-18-entries-hierarchy-design.md`

## Global Constraints

- Source of truth for behavior is the spec above. Where this plan and the spec disagree, stop and ask.
- **Commits:** this repo's `CLAUDE.md` forbids committing without the user's explicit request. Each task ends with a commit step; run it only once the user has said commits are wanted, otherwise leave the work staged and report it.
- Conventional Commits, imperative mood, lowercase, no trailing period, under 72 chars.
- Every task ends green: `flutter analyze` reports no issues and `flutter test` passes in full.
- `flutter`/`dart` live at `/opt/homebrew/bin/` and may not be on a non-interactive shell's `PATH`; call them by absolute path if `which flutter` comes up empty.
- Never introduce a fixed dependency version; read versions from `pubspec.yaml`.
- Pure-logic files (`iso_week.dart`, `entry_tree.dart`, `day_grouping.dart`) must not import `flutter/material.dart`.
- Tests use fixed dates, never `DateTime.now()`, except where an existing test already does.
- ISO 8601 weeks only: Monday start, week 1 contains the year's first Thursday. No locale-dependent week numbering.
- Do not reformat untouched lines. `test/features/timer/timer_screen_test.dart` and `test/features/entries/manual_entry_dialog_test.dart` are not `dart format`-clean at the repo's default width; never run `dart format` across them.
- New user-facing strings go into all six `.arb` files (`lib/l10n/app_{de,en,es,fr,it,nl}.arb`); `app_de.arb` is the template that carries `@`-metadata.

---

### Task 1: ISO week helpers

**Files:**
- Create: `lib/core/format/iso_week.dart`
- Test: `test/core/format/iso_week_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces: `DateTime mondayOf(DateTime day)`, `int isoWeekNumber(DateTime day)`, `String isoDayKey(DateTime day)`.

- [ ] **Step 1: Write the failing test**

Create `test/core/format/iso_week_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/core/format/iso_week.dart';

void main() {
  group('mondayOf', () {
    test('returns the same day for a Monday', () {
      expect(mondayOf(DateTime(2026, 8, 17)), DateTime(2026, 8, 17));
    });

    test('reaches back across a month boundary for a Sunday', () {
      // 2026-08-02 is a Sunday; its ISO week starts 2026-07-27.
      expect(mondayOf(DateTime(2026, 8, 2)), DateTime(2026, 7, 27));
    });

    test('drops the time component', () {
      expect(mondayOf(DateTime(2026, 8, 18, 23, 45, 30)), DateTime(2026, 8, 17));
    });
  });

  group('isoWeekNumber', () {
    test('numbers a mid-year day', () {
      expect(isoWeekNumber(DateTime(2026, 8, 18)), 34);
    });

    test('puts 2027-01-01 in week 53 of the previous ISO year', () {
      expect(isoWeekNumber(DateTime(2027, 1, 1)), 53);
    });

    test('puts 2024-12-30 in week 1 of the next ISO year', () {
      expect(isoWeekNumber(DateTime(2024, 12, 30)), 1);
    });

    test('numbers the first week of a year starting on a Thursday', () {
      // 2026-01-01 is a Thursday, so its week is week 1 of 2026.
      expect(isoWeekNumber(DateTime(2026, 1, 1)), 1);
    });
  });

  group('isoDayKey', () {
    test('zero-pads month and day', () {
      expect(isoDayKey(DateTime(2026, 8, 4)), '2026-08-04');
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `/opt/homebrew/bin/flutter test test/core/format/iso_week_test.dart`
Expected: FAIL — `Error: Method not found: 'mondayOf'` (the file does not exist yet).

- [ ] **Step 3: Write minimal implementation**

Create `lib/core/format/iso_week.dart`:

```dart
/// ISO 8601 calendar helpers: weeks start Monday and week 1 is the week
/// containing the year's first Thursday. Fixed rather than locale-derived --
/// all six supported languages use this convention, and a locale-dependent
/// week number would put the same day in different weeks per language.
///
/// All functions take local dates, ignore the time component, and return
/// local midnight. Day arithmetic goes through the [DateTime] constructor
/// (which normalizes out-of-range values) instead of `add`/`subtract`, so a
/// daylight-saving boundary can't shift the result off midnight.

/// Local-midnight Monday of [day]'s ISO week.
DateTime mondayOf(DateTime day) => DateTime(
  day.year,
  day.month,
  day.day - (day.weekday - DateTime.monday),
);

/// ISO 8601 week number (1-53) of [day].
int isoWeekNumber(DateTime day) {
  final monday = mondayOf(day);
  // The week's Thursday decides which ISO year the week belongs to.
  final thursday = DateTime(monday.year, monday.month, monday.day + 3);
  final firstThursday = _firstThursdayOf(thursday.year);
  final firstWeekMonday = DateTime(
    firstThursday.year,
    firstThursday.month,
    firstThursday.day - 3,
  );
  return _wholeDaysBetween(firstWeekMonday, monday) ~/ 7 + 1;
}

/// `2026-08-04` -- the canonical date part of an expansion key. Zero-padded
/// so keys sort and compare as plain strings.
String isoDayKey(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-'
    '${day.month.toString().padLeft(2, '0')}-'
    '${day.day.toString().padLeft(2, '0')}';

DateTime _firstThursdayOf(int year) {
  final january1 = DateTime(year, 1, 1);
  final offset = (DateTime.thursday - january1.weekday + 7) % 7;
  return DateTime(year, 1, 1 + offset);
}

/// Calendar days from [from] to [to]. Goes through UTC because a local
/// `difference` spanning a daylight-saving change is 23 or 25 hours, which
/// truncates to the wrong number of days.
int _wholeDaysBetween(DateTime from, DateTime to) => DateTime.utc(
  to.year,
  to.month,
  to.day,
).difference(DateTime.utc(from.year, from.month, from.day)).inDays;
```

- [ ] **Step 4: Run test to verify it passes**

Run: `/opt/homebrew/bin/flutter test test/core/format/iso_week_test.dart`
Expected: PASS, 8 tests.

Then: `/opt/homebrew/bin/flutter analyze` — expected "No issues found!".

- [ ] **Step 5: Commit** (only with the user's go-ahead — see Global Constraints)

```bash
git add lib/core/format/iso_week.dart test/core/format/iso_week_test.dart
git commit -m "feat(format): add ISO 8601 week helpers"
```

---

### Task 2: Move the break-rule check onto the day group

`EntriesList` computes `requiredBreakForWorked(...)` inline in `build` today. The week/month/year roll-up needs the same verdict, so it moves onto `EntryDayGroup` — one place instead of two.

**Files:**
- Modify: `lib/features/entries/day_grouping.dart`
- Modify: `lib/features/entries/entries_list.dart:46-62` (call site of `groupEntriesByDay` and `_DayHeader`'s `requiredBreak` argument)
- Test: `test/features/entries/day_grouping_test.dart`

**Interfaces:**
- Consumes: `requiredBreakForWorked(Duration, List<BreakRuleTier>) -> Duration?` from `break_rule_calculations.dart`; `BreakRuleTier` from `data/drift/database.dart`.
- Produces: `EntryDayGroup.requiredBreak` (`Duration?`), `EntryDayGroup.isBreakInsufficient` (`bool`), and `groupEntriesByDay(List<TimeEntry>, {List<BreakRuleTier> tiers = const [], bool includePausedTimeInBreak = false})`.

`tiers` is **optional** with a `const []` default on purpose: `day_grouping_test.dart` calls
`groupEntriesByDay(entries)` positionally in eight existing tests, and a required parameter
would force eight unrelated edits. After Task 3, `buildEntryTree` — which does require
`tiers` — is this function's only production caller, so the default can't silently swallow the
break rules.

- [ ] **Step 1: Write the failing test**

`test/features/entries/day_grouping_test.dart` already has a private
`_entry({required String id, required DateTime startAt, required DateTime endAt, int totalPausedSeconds = 0})`
helper at the top of the file — use it. It has no tier helper, so copy the one from
`test/features/entries/break_rule_calculations_test.dart` verbatim, next to `_entry`:

```dart
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
```

Then append this group inside `main()`:

```dart
  group('requiredBreak', () {
    test('is null when no tier applies to the worked time', () {
      final groups = groupEntriesByDay([
        _entry(id: '1', startAt: DateTime(2026, 8, 18, 9), endAt: DateTime(2026, 8, 18, 10)),
      ]);

      expect(groups.single.requiredBreak, isNull);
      expect(groups.single.isBreakInsufficient, isFalse);
    });

    test('reports the tier value and flags a break that falls short', () {
      final groups = groupEntriesByDay(
        [
          _entry(id: '1', startAt: DateTime(2026, 8, 18, 8), endAt: DateTime(2026, 8, 18, 15)),
        ],
        tiers: [_tier(afterMinutes: 360, requiredBreakMinutes: 30)],
      );

      expect(groups.single.requiredBreak, const Duration(minutes: 30));
      // A single uninterrupted entry means no break at all was taken.
      expect(groups.single.isBreakInsufficient, isTrue);
    });

    test('does not flag a day whose gap covers the required break', () {
      final groups = groupEntriesByDay(
        [
          _entry(id: '1', startAt: DateTime(2026, 8, 18, 8), endAt: DateTime(2026, 8, 18, 12)),
          _entry(id: '2', startAt: DateTime(2026, 8, 18, 13), endAt: DateTime(2026, 8, 18, 16)),
        ],
        tiers: [_tier(afterMinutes: 360, requiredBreakMinutes: 30)],
      );

      expect(groups.single.breakDuration, const Duration(hours: 1));
      expect(groups.single.isBreakInsufficient, isFalse);
    });
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `/opt/homebrew/bin/flutter test test/features/entries/day_grouping_test.dart`
Expected: FAIL — `No named parameter with the name 'tiers'` and
`The getter 'isBreakInsufficient' isn't defined`. The eight pre-existing tests in this file
must still compile unchanged; if they don't, `tiers` was made required by mistake.

- [ ] **Step 3: Write minimal implementation**

In `lib/features/entries/day_grouping.dart`, add the field to `EntryDayGroup`:

```dart
class EntryDayGroup {
  const EntryDayGroup({
    required this.day,
    required this.entries,
    required this.totalDuration,
    required this.breakDuration,
    required this.requiredBreak,
  });

  /// Local midnight for this group's calendar day.
  final DateTime day;
  final List<TimeEntry> entries;
  final Duration totalDuration;
  final Duration breakDuration;

  /// Break the active rule tiers demand for [totalDuration], or null when no
  /// tier applies. Computed here rather than at the render site because the
  /// week/month/year roll-up counts offending days too.
  final Duration? requiredBreak;

  /// True when a tier applies and [breakDuration] falls short of it.
  bool get isBreakInsufficient {
    final required = requiredBreak;
    return required != null && breakDuration < required;
  }
}
```

Change the function signature and body:

```dart
List<EntryDayGroup> groupEntriesByDay(
  List<TimeEntry> entries, {
  List<BreakRuleTier> tiers = const [],
  bool includePausedTimeInBreak = false,
}) {
```

and inside the returned `EntryDayGroup`, add:

```dart
        requiredBreak: requiredBreakForWorked(
          entriesByDay[day]!.fold(
            Duration.zero,
            (sum, entry) => sum + entry.workedDuration,
          ),
          tiers,
        ),
```

Extract the per-day total into a local instead of folding it twice — the file already computes it for `totalDuration`, so restructure the loop body to compute `total` once and pass it to both `totalDuration` and `requiredBreakForWorked`. Update the doc comment above the function to mention `tiers` and `requiredBreak`.

In `lib/features/entries/entries_list.dart`, pass the tiers through and read the verdict off the group:

```dart
        final groups = groupEntriesByDay(
          finished,
          tiers: tiers,
          includePausedTimeInBreak: countPausedTimeAsBreak,
        );
```

and replace `requiredBreak: requiredBreakForWorked(group.totalDuration, tiers),` with `requiredBreak: group.requiredBreak,`. Drop the now-unused `break_rule_calculations.dart` import from `entries_list.dart` only if nothing else in that file uses it (check first — `flutter analyze` flags unused imports).

- [ ] **Step 4: Run tests to verify they pass**

Run: `/opt/homebrew/bin/flutter test test/features/entries/day_grouping_test.dart`
Expected: PASS.

Run: `/opt/homebrew/bin/flutter test && /opt/homebrew/bin/flutter analyze`
Expected: whole suite passes (the day header renders identically — same value, different source), no analyzer issues.

- [ ] **Step 5: Commit** (only with the user's go-ahead)

```bash
git add lib/features/entries/day_grouping.dart lib/features/entries/entries_list.dart test/features/entries/day_grouping_test.dart
git commit -m "refactor(entries): move break-rule verdict onto the day group"
```

---

### Task 3: Tree model, keys, and `buildEntryTree`

**Files:**
- Create: `lib/features/entries/entry_tree.dart`
- Test: `test/features/entries/entry_tree_test.dart`

**Interfaces:**
- Consumes: `EntryDayGroup`, `groupEntriesByDay` (Task 2); `mondayOf`, `isoWeekNumber`, `isoDayKey` (Task 1).
- Produces: classes `EntryYearGroup`, `EntryMonthGroup`, `EntryWeekGroup`; key builders `yearTreeKey(int)`, `monthTreeKey(int, int)`, `weekTreeKey(DateTime monday, int year, int month)`, `dayTreeKey(DateTime)`; `Set<String> defaultExpandedKeys(DateTime today)`; `List<EntryYearGroup> buildEntryTree(List<TimeEntry>, {required List<BreakRuleTier> tiers, bool includePausedTimeInBreak = false})`.

- [ ] **Step 1: Write the failing test**

Create `test/features/entries/entry_tree_test.dart`. Copy the `_entry` and `_tier` helpers
from `day_grouping_test.dart` (after Task 2 that file has both) into the top of the new file —
these test helpers are duplicated per file throughout this repo rather than shared, so follow
that convention. `_entry` requires a unique `id`, so number them within each test:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/features/entries/entry_tree.dart';

void main() {
  group('buildEntryTree', () {
    test('returns an empty list for no entries', () {
      expect(buildEntryTree(const [], tiers: const []), isEmpty);
    });

    test('nests year > month > week > day, newest first at every level', () {
      final tree = buildEntryTree(
        [
          _entry(id: '1', startAt: DateTime(2025, 12, 1, 9), endAt: DateTime(2025, 12, 1, 10)),
          _entry(id: '2', startAt: DateTime(2026, 8, 18, 9), endAt: DateTime(2026, 8, 18, 10)),
          _entry(id: '3', startAt: DateTime(2026, 8, 11, 9), endAt: DateTime(2026, 8, 11, 10)),
        ],
        tiers: const [],
      );

      expect(tree.map((y) => y.year), [2026, 2025]);
      final august = tree.first.months.single;
      expect(august.month, 8);
      expect(august.weeks.map((w) => w.isoWeek), [34, 33]);
      expect(august.weeks.first.days.single.day, DateTime(2026, 8, 18));
    });

    test('sums worked and break time up every level', () {
      final tree = buildEntryTree(
        [
          _entry(id: '1', startAt: DateTime(2026, 8, 18, 8), endAt: DateTime(2026, 8, 18, 10)),
          _entry(id: '2', startAt: DateTime(2026, 8, 18, 11), endAt: DateTime(2026, 8, 18, 12)),
          _entry(id: '3', startAt: DateTime(2026, 8, 11, 9), endAt: DateTime(2026, 8, 11, 10)),
        ],
        tiers: const [],
      );

      final year = tree.single;
      expect(year.totalDuration, const Duration(hours: 4));
      // The one-hour gap on the 18th is that day's break; the 11th has none.
      expect(year.breakDuration, const Duration(hours: 1));
      expect(year.months.single.totalDuration, year.totalDuration);
      expect(
        year.months.single.weeks.fold(
          Duration.zero,
          (sum, week) => sum + week.totalDuration,
        ),
        year.totalDuration,
      );
    });

    test('splits a week that crosses a month boundary into two nodes', () {
      // ISO week 53 of 2026 runs 2026-12-28 to 2027-01-03.
      final tree = buildEntryTree(
        [
          _entry(id: '1', startAt: DateTime(2026, 12, 30, 9), endAt: DateTime(2026, 12, 30, 11)),
          _entry(id: '2', startAt: DateTime(2027, 1, 2, 9), endAt: DateTime(2027, 1, 2, 10)),
        ],
        tiers: const [],
      );

      final january = tree.first.months.single;
      final december = tree.last.months.single;
      expect(tree.map((y) => y.year), [2027, 2026]);

      final januaryWeek = january.weeks.single;
      final decemberWeek = december.weeks.single;
      expect(januaryWeek.isoWeek, 53);
      expect(decemberWeek.isoWeek, 53);

      // Each node covers only the days inside its own month, so the month
      // totals stay true to the calendar month.
      expect(januaryWeek.firstDay, DateTime(2027, 1, 2));
      expect(januaryWeek.lastDay, DateTime(2027, 1, 2));
      expect(januaryWeek.totalDuration, const Duration(hours: 1));
      expect(decemberWeek.firstDay, DateTime(2026, 12, 30));
      expect(decemberWeek.totalDuration, const Duration(hours: 2));
    });

    test('gives the two halves of a split week distinct expansion keys', () {
      final tree = buildEntryTree(
        [
          _entry(id: '1', startAt: DateTime(2026, 12, 30, 9), endAt: DateTime(2026, 12, 30, 11)),
          _entry(id: '2', startAt: DateTime(2027, 1, 2, 9), endAt: DateTime(2027, 1, 2, 10)),
        ],
        tiers: const [],
      );

      final januaryWeek = tree.first.months.single.weeks.single;
      final decemberWeek = tree.last.months.single.weeks.single;
      expect(januaryWeek.monday, decemberWeek.monday);
      expect(
        weekTreeKey(januaryWeek.monday, januaryWeek.year, januaryWeek.month),
        isNot(weekTreeKey(decemberWeek.monday, decemberWeek.year, decemberWeek.month)),
      );
    });

    test('counts days that fall short of the break rule at every level', () {
      final tree = buildEntryTree(
        [
          // 7h straight, no break -> short.
          _entry(id: '1', startAt: DateTime(2026, 8, 18, 8), endAt: DateTime(2026, 8, 18, 15)),
          // 7h with a 1h gap -> fine.
          _entry(id: '2', startAt: DateTime(2026, 8, 11, 8), endAt: DateTime(2026, 8, 11, 12)),
          _entry(id: '3', startAt: DateTime(2026, 8, 11, 13), endAt: DateTime(2026, 8, 11, 16)),
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

  group('defaultExpandedKeys', () {
    test('covers exactly the path to the given day', () {
      expect(defaultExpandedKeys(DateTime(2026, 8, 18, 14, 30)), {
        yearTreeKey(2026),
        monthTreeKey(2026, 8),
        weekTreeKey(DateTime(2026, 8, 17), 2026, 8),
        dayTreeKey(DateTime(2026, 8, 18)),
      });
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `/opt/homebrew/bin/flutter test test/features/entries/entry_tree_test.dart`
Expected: FAIL — the import of `entry_tree.dart` cannot be resolved.

- [ ] **Step 3: Write minimal implementation**

Create `lib/features/entries/entry_tree.dart`:

```dart
import '../../core/format/iso_week.dart';
import '../../data/drift/database.dart';
import 'day_grouping.dart';

/// A year of entries, newest month first.
class EntryYearGroup {
  const EntryYearGroup({
    required this.year,
    required this.months,
    required this.totalDuration,
    required this.breakDuration,
    required this.insufficientBreakDays,
  });

  final int year;
  final List<EntryMonthGroup> months;
  final Duration totalDuration;
  final Duration breakDuration;

  /// Number of days below this node whose break falls short of the rule.
  final int insufficientBreakDays;
}

/// A calendar month of entries, newest week first.
class EntryMonthGroup {
  const EntryMonthGroup({
    required this.year,
    required this.month,
    required this.weeks,
    required this.totalDuration,
    required this.breakDuration,
    required this.insufficientBreakDays,
  });

  final int year;
  final int month;
  final List<EntryWeekGroup> weeks;
  final Duration totalDuration;
  final Duration breakDuration;
  final int insufficientBreakDays;
}

/// One ISO week's entries *within a single month*, newest day first. A week
/// crossing a month boundary yields two of these -- one per month -- so
/// month and year totals stay true to the calendar period. [monday] is the
/// week's calendar Monday (shared by both halves), while [firstDay] and
/// [lastDay] cover only the days this node actually holds.
class EntryWeekGroup {
  const EntryWeekGroup({
    required this.isoWeek,
    required this.monday,
    required this.year,
    required this.month,
    required this.firstDay,
    required this.lastDay,
    required this.days,
    required this.totalDuration,
    required this.breakDuration,
    required this.insufficientBreakDays,
  });

  final int isoWeek;
  final DateTime monday;
  final int year;
  final int month;
  final DateTime firstDay;
  final DateTime lastDay;
  final List<EntryDayGroup> days;
  final Duration totalDuration;
  final Duration breakDuration;
  final int insufficientBreakDays;
}

String yearTreeKey(int year) => 'y$year';

String monthTreeKey(int year, int month) =>
    'm$year-${month.toString().padLeft(2, '0')}';

/// The month is part of the key because a week crossing a month boundary
/// becomes two nodes that share a [monday]; without it, collapsing one half
/// would collapse the other.
String weekTreeKey(DateTime monday, int year, int month) =>
    'w${isoDayKey(monday)}-$year-${month.toString().padLeft(2, '0')}';

String dayTreeKey(DateTime day) => 'd${isoDayKey(day)}';

/// Expansion keys for the path to [today]: its year, month, ISO week and the
/// day itself.
Set<String> defaultExpandedKeys(DateTime today) => {
  yearTreeKey(today.year),
  monthTreeKey(today.year, today.month),
  weekTreeKey(mondayOf(today), today.year, today.month),
  dayTreeKey(DateTime(today.year, today.month, today.day)),
};

/// Groups [entries] into Year > Month > ISO week > Day, newest first at every
/// level, with worked/break totals and offending-day counts rolled up.
///
/// [tiers] and [includePausedTimeInBreak] pass straight through to
/// [groupEntriesByDay]. A week spanning a month boundary is split at that
/// boundary (see [EntryWeekGroup]).
List<EntryYearGroup> buildEntryTree(
  List<TimeEntry> entries, {
  required List<BreakRuleTier> tiers,
  bool includePausedTimeInBreak = false,
}) {
  final days = groupEntriesByDay(
    entries,
    tiers: tiers,
    includePausedTimeInBreak: includePausedTimeInBreak,
  );

  // Dart maps keep insertion order, and `days` is newest-first, so the first
  // time a week, month or year is seen it is also the newest one -- every
  // level comes out sorted without a single sort call.
  final daysByWeek = <String, List<EntryDayGroup>>{};
  for (final day in days) {
    final key = weekTreeKey(mondayOf(day.day), day.day.year, day.day.month);
    daysByWeek.putIfAbsent(key, () => []).add(day);
  }

  final weeksByMonth = <String, List<EntryWeekGroup>>{};
  for (final dayGroups in daysByWeek.values) {
    final week = _weekGroup(dayGroups);
    weeksByMonth
        .putIfAbsent(monthTreeKey(week.year, week.month), () => [])
        .add(week);
  }

  final monthsByYear = <int, List<EntryMonthGroup>>{};
  for (final weeks in weeksByMonth.values) {
    final month = _monthGroup(weeks);
    monthsByYear.putIfAbsent(month.year, () => []).add(month);
  }

  return [for (final months in monthsByYear.values) _yearGroup(months)];
}

EntryWeekGroup _weekGroup(List<EntryDayGroup> days) {
  final first = days.first.day;
  return EntryWeekGroup(
    isoWeek: isoWeekNumber(first),
    monday: mondayOf(first),
    year: first.year,
    month: first.month,
    // `days` is newest-first, so the last element is the earliest day.
    firstDay: days.last.day,
    lastDay: first,
    days: days,
    totalDuration: _sum(days.map((d) => d.totalDuration)),
    breakDuration: _sum(days.map((d) => d.breakDuration)),
    insufficientBreakDays: days.where((d) => d.isBreakInsufficient).length,
  );
}

EntryMonthGroup _monthGroup(List<EntryWeekGroup> weeks) => EntryMonthGroup(
  year: weeks.first.year,
  month: weeks.first.month,
  weeks: weeks,
  totalDuration: _sum(weeks.map((w) => w.totalDuration)),
  breakDuration: _sum(weeks.map((w) => w.breakDuration)),
  insufficientBreakDays: weeks.fold(
    0,
    (sum, week) => sum + week.insufficientBreakDays,
  ),
);

EntryYearGroup _yearGroup(List<EntryMonthGroup> months) => EntryYearGroup(
  year: months.first.year,
  months: months,
  totalDuration: _sum(months.map((m) => m.totalDuration)),
  breakDuration: _sum(months.map((m) => m.breakDuration)),
  insufficientBreakDays: months.fold(
    0,
    (sum, month) => sum + month.insufficientBreakDays,
  ),
);

Duration _sum(Iterable<Duration> durations) =>
    durations.fold(Duration.zero, (sum, duration) => sum + duration);
```

- [ ] **Step 4: Run test to verify it passes**

Run: `/opt/homebrew/bin/flutter test test/features/entries/entry_tree_test.dart`
Expected: PASS, 8 tests.

Then `/opt/homebrew/bin/flutter analyze` — no issues.

- [ ] **Step 5: Commit** (only with the user's go-ahead)

```bash
git add lib/features/entries/entry_tree.dart test/features/entries/entry_tree_test.dart
git commit -m "feat(entries): add year/month/week entry tree with rolled-up totals"
```

---

### Task 4: Flatten the tree into renderable rows

**Files:**
- Modify: `lib/features/entries/entry_tree.dart` (append)
- Test: `test/features/entries/entry_tree_test.dart` (append)

**Interfaces:**
- Consumes: the four group classes and key builders from Task 3.
- Produces: `sealed class EntryTreeRow` with subclasses `EntryTreeYearRow(EntryYearGroup year)`, `EntryTreeMonthRow(EntryMonthGroup month)`, `EntryTreeWeekRow(EntryWeekGroup week)`, `EntryTreeDayRow(EntryDayGroup day)`, `EntryTreeEntriesRow(EntryDayGroup day)`; and `List<EntryTreeRow> flattenEntryTree(List<EntryYearGroup>, Set<String>)`.

- [ ] **Step 1: Write the failing test**

Append to `test/features/entries/entry_tree_test.dart`:

```dart
  group('flattenEntryTree', () {
    List<EntryYearGroup> twoWeeksAcrossTwoYears() => buildEntryTree(
      [
        _entry(id: '1', startAt: DateTime(2026, 8, 18, 9), endAt: DateTime(2026, 8, 18, 10)),
        _entry(id: '2', startAt: DateTime(2025, 3, 4, 9), endAt: DateTime(2025, 3, 4, 10)),
      ],
      tiers: const [],
    );

    test('shows one row per year when nothing is expanded', () {
      final rows = flattenEntryTree(twoWeeksAcrossTwoYears(), const {});

      expect(rows, hasLength(2));
      expect(rows.every((row) => row is EntryTreeYearRow), isTrue);
    });

    test('an expanded year adds exactly its months', () {
      final rows = flattenEntryTree(twoWeeksAcrossTwoYears(), {yearTreeKey(2026)});

      expect(rows.whereType<EntryTreeMonthRow>(), hasLength(1));
      expect(rows.whereType<EntryTreeWeekRow>(), isEmpty);
    });

    test('the entries row appears only for an expanded day', () {
      final tree = twoWeeksAcrossTwoYears();
      final collapsedDay = {
        yearTreeKey(2026),
        monthTreeKey(2026, 8),
        weekTreeKey(DateTime(2026, 8, 17), 2026, 8),
      };

      expect(
        flattenEntryTree(tree, collapsedDay).whereType<EntryTreeEntriesRow>(),
        isEmpty,
      );
      expect(
        flattenEntryTree(tree, {
          ...collapsedDay,
          dayTreeKey(DateTime(2026, 8, 18)),
        }).whereType<EntryTreeEntriesRow>(),
        hasLength(1),
      );
    });

    test('ignores keys for nodes that no longer exist', () {
      final rows = flattenEntryTree(twoWeeksAcrossTwoYears(), {
        yearTreeKey(1999),
        dayTreeKey(DateTime(1999, 1, 1)),
      });

      expect(rows, hasLength(2));
    });

    test('keeps rows in display order: year, month, week, day, entries', () {
      final rows = flattenEntryTree(
        twoWeeksAcrossTwoYears(),
        defaultExpandedKeys(DateTime(2026, 8, 18)),
      );

      expect(rows.take(5).map((row) => row.runtimeType.toString()), [
        'EntryTreeYearRow',
        'EntryTreeMonthRow',
        'EntryTreeWeekRow',
        'EntryTreeDayRow',
        'EntryTreeEntriesRow',
      ]);
    });
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `/opt/homebrew/bin/flutter test test/features/entries/entry_tree_test.dart`
Expected: FAIL — `Method not found: 'flattenEntryTree'`.

- [ ] **Step 3: Write minimal implementation**

Append to `lib/features/entries/entry_tree.dart`:

```dart
/// One rendered line of the entries list. [EntryTreeEntriesRow] is the card of
/// entry tiles that follows an expanded day's header.
sealed class EntryTreeRow {
  const EntryTreeRow();
}

class EntryTreeYearRow extends EntryTreeRow {
  const EntryTreeYearRow(this.year);
  final EntryYearGroup year;
}

class EntryTreeMonthRow extends EntryTreeRow {
  const EntryTreeMonthRow(this.month);
  final EntryMonthGroup month;
}

class EntryTreeWeekRow extends EntryTreeRow {
  const EntryTreeWeekRow(this.week);
  final EntryWeekGroup week;
}

class EntryTreeDayRow extends EntryTreeRow {
  const EntryTreeDayRow(this.day);
  final EntryDayGroup day;
}

class EntryTreeEntriesRow extends EntryTreeRow {
  const EntryTreeEntriesRow(this.day);
  final EntryDayGroup day;
}

/// Flattens [years] into the rows currently visible for [expanded] (a set of
/// keys from [yearTreeKey] and friends). A node's children are emitted only
/// while its own key is present, so a collapsed year costs one row no matter
/// how much sits below it. Unknown keys are ignored.
List<EntryTreeRow> flattenEntryTree(
  List<EntryYearGroup> years,
  Set<String> expanded,
) {
  final rows = <EntryTreeRow>[];
  for (final year in years) {
    rows.add(EntryTreeYearRow(year));
    if (!expanded.contains(yearTreeKey(year.year))) continue;
    for (final month in year.months) {
      rows.add(EntryTreeMonthRow(month));
      if (!expanded.contains(monthTreeKey(month.year, month.month))) continue;
      for (final week in month.weeks) {
        rows.add(EntryTreeWeekRow(week));
        if (!expanded.contains(
          weekTreeKey(week.monday, week.year, week.month),
        )) {
          continue;
        }
        for (final day in week.days) {
          rows.add(EntryTreeDayRow(day));
          if (!expanded.contains(dayTreeKey(day.day))) continue;
          rows.add(EntryTreeEntriesRow(day));
        }
      }
    }
  }
  return rows;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `/opt/homebrew/bin/flutter test test/features/entries/entry_tree_test.dart`
Expected: PASS, 13 tests.

- [ ] **Step 5: Commit** (only with the user's go-ahead)

```bash
git add lib/features/entries/entry_tree.dart test/features/entries/entry_tree_test.dart
git commit -m "feat(entries): flatten the entry tree into visible rows"
```

---

### Task 5: Expansion-state notifier

**Files:**
- Create: `lib/features/entries/entry_tree_expansion.dart`
- Generated: `lib/features/entries/entry_tree_expansion.g.dart` (build_runner output — commit it, the repo checks generated files in)
- Test: `test/features/entries/entry_tree_expansion_test.dart`

**Interfaces:**
- Consumes: `defaultExpandedKeys` (Task 3).
- Produces: `entryTreeExpansionProvider` (a `NotifierProvider<EntryTreeExpansion, Set<String>>`) with `void toggle(String key)`.

- [ ] **Step 1: Write the failing test**

Create `test/features/entries/entry_tree_expansion_test.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/features/entries/entry_tree.dart';
import 'package:hickory/features/entries/entry_tree_expansion.dart';

void main() {
  test('starts expanded on the path to today', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(
      container.read(entryTreeExpansionProvider),
      defaultExpandedKeys(DateTime.now()),
    );
  });

  test('toggle adds a collapsed key and removes an expanded one', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(entryTreeExpansionProvider.notifier);

    notifier.toggle(yearTreeKey(2020));
    expect(container.read(entryTreeExpansionProvider), contains(yearTreeKey(2020)));

    notifier.toggle(yearTreeKey(2020));
    expect(
      container.read(entryTreeExpansionProvider),
      isNot(contains(yearTreeKey(2020))),
    );
  });
}
```

`DateTime.now()` is acceptable here (it is the one thing under test) but keep the assertion to set equality so it cannot flake on formatting.

- [ ] **Step 2: Run test to verify it fails**

Run: `/opt/homebrew/bin/flutter test test/features/entries/entry_tree_expansion_test.dart`
Expected: FAIL — `entry_tree_expansion.dart` cannot be resolved.

- [ ] **Step 3: Write minimal implementation**

Create `lib/features/entries/entry_tree_expansion.dart`:

```dart
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'entry_tree.dart';

part 'entry_tree_expansion.g.dart';

/// Which nodes of the entries hierarchy are expanded, as keys from
/// [yearTreeKey] and friends.
///
/// Kept alive so switching tabs doesn't collapse the list; deliberately not
/// persisted, so every app start reopens the path to today (see
/// docs/superpowers/specs/2026-08-18-entries-hierarchy-design.md). The seed is
/// computed once on first read: an app left running past midnight keeps
/// yesterday's path until it restarts.
@Riverpod(keepAlive: true)
class EntryTreeExpansion extends _$EntryTreeExpansion {
  @override
  Set<String> build() => defaultExpandedKeys(DateTime.now());

  /// Expands [key] when collapsed and collapses it when expanded. Keys of
  /// nodes that have since disappeared are harmless -- the set is only ever
  /// queried, never iterated.
  void toggle(String key) {
    final next = {...state};
    if (!next.remove(key)) next.add(key);
    state = next;
  }
}
```

Then generate the `.g.dart`:

```bash
/opt/homebrew/bin/dart run build_runner build --delete-conflicting-outputs
```

- [ ] **Step 4: Run test to verify it passes**

Run: `/opt/homebrew/bin/flutter test test/features/entries/entry_tree_expansion_test.dart`
Expected: PASS, 2 tests.

Then `/opt/homebrew/bin/flutter analyze` — no issues. If build_runner touched unrelated generated files, check `git status` and keep only the intended ones in the commit.

- [ ] **Step 5: Commit** (only with the user's go-ahead)

```bash
git add lib/features/entries/entry_tree_expansion.dart lib/features/entries/entry_tree_expansion.g.dart test/features/entries/entry_tree_expansion_test.dart
git commit -m "feat(entries): add expansion state for the entries hierarchy"
```

---

### Task 6: New strings in all six locales

**Files:**
- Modify: `lib/l10n/app_de.arb` (template, carries `@`-metadata), `app_en.arb`, `app_es.arb`, `app_fr.arb`, `app_it.arb`, `app_nl.arb`
- Generated: `lib/l10n/app_localizations*.dart`

**Interfaces:**
- Produces: `l10n.entriesWeekHeader(week, range)`, `l10n.entriesWorkLabel(duration)`, `l10n.entriesBreakInsufficientDaysTooltip(count)`. Removes `l10n.entriesDayHeader`.

- [ ] **Step 1: Add the keys to the template**

In `lib/l10n/app_de.arb`, next to the existing `entries*` keys, add:

```json
  "entriesWeekHeader": "KW {week} · {range}",
  "@entriesWeekHeader": {
    "placeholders": {
      "week": { "type": "int" },
      "range": { "type": "String" }
    }
  },
  "entriesWorkLabel": "Arbeitszeit: {duration}",
  "@entriesWorkLabel": {
    "placeholders": {
      "duration": { "type": "String" }
    }
  },
  "entriesBreakInsufficientDaysTooltip": "{count, plural, =1{1 Tag mit zu kurzer Pause} other{{count} Tage mit zu kurzer Pause}}",
  "@entriesBreakInsufficientDaysTooltip": {
    "placeholders": {
      "count": { "type": "num" }
    }
  },
```

This is the project's first ICU plural — `count` must be typed `num` for `plural` to generate.

- [ ] **Step 2: Add the same keys to the five other locales**

Values only, no `@`-metadata (only the template carries it — match how the existing keys are written in those files).

| Key | en | es | fr | it | nl |
|-----|----|----|----|----|----|
| `entriesWeekHeader` | `Week {week} · {range}` | `Semana {week} · {range}` | `Semaine {week} · {range}` | `Settimana {week} · {range}` | `Week {week} · {range}` |
| `entriesWorkLabel` | `Worked: {duration}` | `Trabajado: {duration}` | `Travaillé : {duration}` | `Lavorato: {duration}` | `Gewerkt: {duration}` |

`entriesBreakInsufficientDaysTooltip`:

- en: `{count, plural, =1{1 day with a break that is too short} other{{count} days with breaks that are too short}}`
- es: `{count, plural, =1{1 día con una pausa demasiado corta} other{{count} días con pausas demasiado cortas}}`
- fr: `{count, plural, =1{1 jour avec une pause trop courte} other{{count} jours avec des pauses trop courtes}}`
- it: `{count, plural, =1{1 giorno con una pausa troppo breve} other{{count} giorni con pause troppo brevi}}`
- nl: `{count, plural, =1{1 dag met een te korte pauze} other{{count} dagen met te korte pauzes}}`

- [ ] **Step 3: Remove `entriesDayHeader`**

Delete the `entriesDayHeader` value from all six files, plus its `@entriesDayHeader` metadata block in `app_de.arb`. Task 7 replaces its only use with a separate label and summary; leaving it would be a dead string (the repo removed `quickAddMoreTooltip` for the same reason).

- [ ] **Step 4: Regenerate and verify**

Run: `/opt/homebrew/bin/flutter gen-l10n`
Then: `/opt/homebrew/bin/flutter analyze`

Expected: generation succeeds; analyze reports no issues. `build/untranslated_messages.json` must not list any of the three new keys — if it does, a locale file is missing one.

Note: analyze will still pass at this point because nothing references the new keys yet; `entriesDayHeader`'s removal will break `entries_list.dart` only if Task 7 has not run yet. Do Task 6 and Task 7 back to back, or temporarily keep `entriesDayHeader` and delete it at the end of Task 7 — either is fine, but the branch must not be left with a compile error.

- [ ] **Step 5: Commit** (only with the user's go-ahead)

```bash
git add lib/l10n
git commit -m "feat(l10n): add week, worked, and short-break-days strings"
```

---

### Task 7: Render the hierarchy in `EntriesList`

**Files:**
- Modify: `lib/features/entries/entries_list.dart` (replace the `ListView.builder` body and `_DayHeader`)
- Test: `test/features/entries/entries_list_test.dart`
- Test (update only): `test/features/entries/quick_add_bar_test.dart`, `test/features/timer/timer_screen_test.dart`

**Interfaces:**
- Consumes: everything from Tasks 1-6.
- Produces: no public API; `_DayHeader` is gone, replaced by `_GroupHeader`.

- [ ] **Step 1: Write the failing tests**

`test/features/entries/entries_list_test.dart` has `Widget makeApp(List<TimeEntry> entries, {List<BreakRuleTier> tiers = const [], bool countPausedTimeAsBreak = false})`
— entries are **positional** — plus private `_entry`/`_tier` helpers. Two harness changes come first:

1. **Add date-formatting init.** The file has none today, because `dateFormat: 'iso'` never
   touches `intl`'s locale data. Month names do: `DateFormat.MMMM('en')` throws
   `LocaleDataException` unless the data is loaded. Add at the top of `main()`, matching
   `settings_home_screen_test.dart`:

```dart
  setUpAll(() => initializeDateFormatting('en'));
```

   with `import 'package:intl/date_symbol_data_local.dart';`.

2. **Add an expansion override.** Give `makeApp` an extra `Set<String>? expanded` parameter;
   when non-null, add to the `overrides` list:

```dart
          if (expanded != null)
            entryTreeExpansionProvider.overrideWith(() => _FixedExpansion(expanded)),
```

   and at the bottom of the file:

```dart
/// Pins the expansion set so a test doesn't silently depend on today's date.
class _FixedExpansion extends EntryTreeExpansion {
  _FixedExpansion(this._initial);

  final Set<String> _initial;

  @override
  Set<String> build() => _initial;
}
```

Then add these tests:

```dart
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
```

Also update the two existing expectations in this file that will now be wrong:
`find.text('Today · 01:00')` and `find.text('Yesterday · 00:30')` no longer exist (label and
summary are separate widgets) — assert `find.text('Today')` plus `find.text('01:00')`
instead. And the assertions counting `Card`s / `Dismissible`s must account for sibling days
being collapsed by default; where a test needs several days visible at once, pass an explicit
`expanded` set covering them rather than relying on the seed.

- [ ] **Step 2: Run tests to verify they fail**

Run: `/opt/homebrew/bin/flutter test test/features/entries/entries_list_test.dart`
Expected: FAIL — `No named parameter with the name 'expanded'` before the harness changes,
then `find.text('2024')` finding nothing once it compiles.

- [ ] **Step 3: Write the implementation**

In `lib/features/entries/entries_list.dart`, replace the `entriesAsync.when(data: ...)` body's grouping and `ListView.builder` with:

```dart
        final years = buildEntryTree(
          finished,
          tiers: tiers,
          includePausedTimeInBreak: countPausedTimeAsBreak,
        );
        final expanded = ref.watch(entryTreeExpansionProvider);
        final rows = flattenEntryTree(years, expanded);
        final localeName = Localizations.localeOf(context).languageCode;
        void toggle(String key) =>
            ref.read(entryTreeExpansionProvider.notifier).toggle(key);

        return ListView.builder(
          itemCount: rows.length,
          itemBuilder: (context, index) => switch (rows[index]) {
            EntryTreeYearRow(:final year) => _GroupHeader(
              depth: 0,
              label: '${year.year}',
              total: year.totalDuration,
              breakDuration: year.breakDuration,
              warningTooltip: _rolledUpBreakTooltip(l10n, year.insufficientBreakDays),
              expanded: expanded.contains(yearTreeKey(year.year)),
              onTap: () => toggle(yearTreeKey(year.year)),
              l10n: l10n,
              timeStyle: timeStyle,
            ),
            EntryTreeMonthRow(:final month) => _GroupHeader(
              depth: 1,
              label: DateFormat.MMMM(localeName).format(
                DateTime(month.year, month.month),
              ),
              total: month.totalDuration,
              breakDuration: month.breakDuration,
              warningTooltip: _rolledUpBreakTooltip(l10n, month.insufficientBreakDays),
              expanded: expanded.contains(monthTreeKey(month.year, month.month)),
              onTap: () => toggle(monthTreeKey(month.year, month.month)),
              l10n: l10n,
              timeStyle: timeStyle,
            ),
            EntryTreeWeekRow(:final week) => _GroupHeader(
              depth: 2,
              label: l10n.entriesWeekHeader(
                week.isoWeek,
                '${formatDate(week.firstDay, dateStyle, localeName)} – '
                '${formatDate(week.lastDay, dateStyle, localeName)}',
              ),
              total: week.totalDuration,
              breakDuration: week.breakDuration,
              warningTooltip: _rolledUpBreakTooltip(l10n, week.insufficientBreakDays),
              expanded: expanded.contains(
                weekTreeKey(week.monday, week.year, week.month),
              ),
              onTap: () => toggle(weekTreeKey(week.monday, week.year, week.month)),
              l10n: l10n,
              timeStyle: timeStyle,
            ),
            EntryTreeDayRow(:final day) => _GroupHeader(
              depth: 3,
              label: _dayLabel(day.day, l10n, dateStyle, localeName),
              total: day.totalDuration,
              breakDuration: day.breakDuration,
              warningTooltip: day.isBreakInsufficient
                  ? l10n.entriesBreakInsufficientTooltip
                  : null,
              expanded: expanded.contains(dayTreeKey(day.day)),
              onTap: () => toggle(dayTreeKey(day.day)),
              l10n: l10n,
              timeStyle: timeStyle,
            ),
            EntryTreeEntriesRow(:final day) => Padding(
              padding: const EdgeInsets.only(left: _depthInset * 3),
              child: _DayEntriesBlock(
                entries: day.entries,
                projectsById: projectsById,
                jiraWorklogsById: jiraWorklogsById,
                timeStyle: timeStyle,
                l10n: l10n,
              ),
            ),
          },
        );
```

Add `import 'package:intl/intl.dart';` and imports for `entry_tree.dart` / `entry_tree_expansion.dart`. Keep the `const double _depthInset = 12;` file-level constant next to `_GroupHeader`.

Move `_DayHeader`'s label logic into a file-level function so the day row can reuse it verbatim:

```dart
/// "Today"/"Yesterday" for the two most recent days, otherwise the formatted
/// date. Unchanged from the previous day header.
String _dayLabel(
  DateTime day,
  AppLocalizations l10n,
  DateFormatStyle dateStyle,
  String localeName,
) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  if (day == today) return l10n.entriesToday;
  if (day == DateTime(today.year, today.month, today.day - 1)) {
    return l10n.entriesYesterday;
  }
  return formatDate(day, dateStyle, localeName);
}

/// Tooltip for a week/month/year row's warning icon, or null when no day
/// below it falls short of the break rule.
String? _rolledUpBreakTooltip(AppLocalizations l10n, int insufficientBreakDays) =>
    insufficientBreakDays == 0
        ? null
        : l10n.entriesBreakInsufficientDaysTooltip(insufficientBreakDays);
```

Replace the whole `_DayHeader` class with:

```dart
const double _depthInset = 12;

/// One header row of the entries hierarchy -- year, month, week or day. Purely
/// presentational: it neither knows its level's meaning nor touches Riverpod,
/// it just indents by [depth], shows [label] on the left and the summary on the
/// right, and reports taps through [onTap].
class _GroupHeader extends StatelessWidget {
  const _GroupHeader({
    required this.depth,
    required this.label,
    required this.total,
    required this.breakDuration,
    required this.warningTooltip,
    required this.expanded,
    required this.onTap,
    required this.l10n,
    required this.timeStyle,
  });

  final int depth;
  final String label;
  final Duration total;
  final Duration breakDuration;

  /// Non-null shows the warning icon with this message; the caller decides
  /// which wording fits its level.
  final String? warningTooltip;
  final bool expanded;
  final VoidCallback onTap;
  final AppLocalizations l10n;
  final TimeFormatStyle timeStyle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tooltip = warningTooltip;
    final totalText = formatDuration(total, timeStyle);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.only(
          left: depth * _depthInset,
          top: 12,
          bottom: 8,
        ),
        child: Row(
          children: [
            AnimatedRotation(
              turns: expanded ? 0.25 : 0,
              duration: const Duration(milliseconds: 150),
              child: const Icon(Icons.keyboard_arrow_right, size: 20),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            // Wrap so a long date range plus both sums drop to a second line
            // instead of overflowing in a narrow window.
            Flexible(
              child: Wrap(
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 4,
                children: [
                  if (tooltip != null)
                    Tooltip(
                      message: tooltip,
                      child: Icon(
                        Icons.warning_amber_rounded,
                        size: 16,
                        color: theme.colorScheme.error,
                      ),
                    ),
                  Text(
                    l10n.entriesBreakLabel(
                      formatDuration(breakDuration, timeStyle),
                    ),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: tooltip == null ? null : theme.colorScheme.error,
                    ),
                  ),
                  // Visually just a duration; labelled for screen readers so
                  // the bare number still says what it is.
                  Semantics(
                    label: l10n.entriesWorkLabel(totalText),
                    excludeSemantics: true,
                    child: Text(
                      totalText,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `/opt/homebrew/bin/flutter test test/features/entries/entries_list_test.dart`
Expected: PASS.

Run: `/opt/homebrew/bin/flutter test`
Expected: whole suite passes. `quick_add_bar_test.dart` and `timer_screen_test.dart` assert a
freshly created entry is visible; today's path is expanded by default, so they should pass
untouched. If one fails because a sibling day is collapsed, fix the test by overriding the
expansion set (same `_FixedExpansion` approach), not by changing the seed.

Run: `/opt/homebrew/bin/flutter analyze`
Expected: no issues.

- [ ] **Step 5: Verify in the running app**

`flutter run -d macos` needs `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`
first (the active developer dir is the Command Line Tools, which have no `xcodebuild`). Once
it runs: everything collapsed shows only years; expanding down to a day shows its entries;
sums sit on the right at every level; a day with too short a break shows the warning and its
week/month/year rows do too. If the toolchain is still unavailable, say so explicitly instead
of implying the UI was seen.

- [ ] **Step 6: Commit** (only with the user's go-ahead)

```bash
git add lib/features/entries/entries_list.dart test/features/entries/entries_list_test.dart test/features/entries/quick_add_bar_test.dart test/features/timer/timer_screen_test.dart
git commit -m "feat(entries): make the entries list a collapsible hierarchy"
```

---

### Task 8: Update project documentation

**Files:**
- Modify: `docs/memory/features.md`, `docs/memory/features/manual-entry.md`
- Create: `docs/memory/features/entries-list.md`
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Write the feature memory**

Create `docs/memory/features/entries-list.md` covering: the four-level hierarchy and why the
day level survived (entry rows carry no date); the month-boundary split and why (calendar-true
month totals for billing); why week keys include the month (two nodes share a Monday); the
expansion seed being the path to today, keep-alive but not persisted; that grouping, keys and
flattening are pure functions in `entry_tree.dart` with widget-free tests; and the gotcha that
a widget test pumping `EntriesList` must override `entryTreeExpansionProvider` or it silently
depends on today's date.

Add a row for it in `docs/memory/features.md`. In `manual-entry.md`, fix the line that
describes `EntriesList` as a flat day list if present.

- [ ] **Step 2: Add the changelog entry**

Under `## [Unreleased]` → `### Added`:

```markdown
- Make the entries overview collapsible: years contain months, months contain calendar weeks with their date range, weeks contain days, and every header shows the worked and break time below it. Opening the app expands the path to today.
```

- [ ] **Step 3: Commit** (only with the user's go-ahead)

```bash
git add docs CHANGELOG.md
git commit -m "docs(entries): document the collapsible entries hierarchy"
```
