# Collapsible Entries Hierarchy — Design

Date: 2026-08-18
Status: Implemented, revised 2026-08-19

## Revision — expanding tree replaced by drill-down

The first implementation was a tree that expanded in place. Seeing it running, the
partner found it wasteful of space and dated: four look-alike rows, the same sums
repeated at every level, and week labels wrapping onto a second line. The list now
**drills into one level at a time** — years, then months, then one week — with a
breadcrumb carrying the path back up.

What changed against the sections below:

- The **week is the deepest level** and lists its days with their entries, so a week
  reads in one view. There is no separate day level and no per-day drill-in; a day
  sub-header labels its entries and is not tappable. (This supersedes §1's decision to
  make the day a fourth clickable level, which existed to keep the day's totals and
  break warning — those now live on the day sub-header instead.)
- `flattenEntryTree`, its row types, the expansion-key builders and the expansion
  notifier are **gone**. Navigation state is one `EntriesLocation` in
  `lib/features/entries/entries_location.dart`, which also holds `initialLocation`,
  `viewFor` and `parentOf` as pure functions.
- The list **opens on the week holding today**, falling back to the newest week that
  has entries, then to the years list when there are none. Null state means "not
  navigated yet" and is resolved by the widget, which is the only place that knows
  what data exists.
- `viewFor` falls back to the nearest surviving ancestor, so deleting a week's last
  entry cannot strand the list on an empty view.
- A rolled-up row marks a short break with a **dot plus a counting tooltip**; the
  triangle stays on the day sub-header, where the rule actually applies.

The data model in §2, the ISO week helpers in §3 and the month-boundary split are
unchanged — they carried over intact.

Original design follows.

## 1. Goal & Scope

`EntriesList` (`lib/features/entries/entries_list.dart`) renders one flat, always-expanded
list of day groups. With more than a few weeks of tracked time it becomes an endless scroll
with no way to get an overview or to reach an older period quickly.

This replaces that flat list with a four-level collapsible hierarchy:

```
Year  ›  Month  ›  ISO calendar week (incl. date range)  ›  Day  ›  Entries
```

Every header row carries a right-aligned summary of worked time and break time for
everything below it.

Confirmed with the user during brainstorming:

- The day level is **kept** as the fourth level. Its header keeps today's content (worked
  total, break, "break too short" warning) — an entry row shows only `Project · 09:00 – 10:30`
  with no date, so without a day level an entry in an expanded week would be unattributable.
- On app start, exactly the **path to today** is expanded (current year, current month,
  current week, today). Everything else is collapsed. State survives tab switches, resets on
  restart — no persistence.
- A week that spans a month boundary is **split at that boundary**, so month and year totals
  match the calendar period exactly (this matters for billing).
- Every level shows worked time **and** break time. The "break too short" warning **bubbles
  up**: a week, month, or year row shows the warning icon when any day below it violates the
  break rule, because a collapsed list would otherwise hide exactly the days worth finding.
- Approach A of three: an explicit tree model with a controlled expansion set and a
  flattened `ListView`, rather than nested `ExpansionTile`s (used elsewhere in this repo for
  fixed two-section cards, but it keeps expansion state inside framework widgets, builds
  whole subtrees eagerly, and adds Material padding per level).

## 2. Data model — `lib/features/entries/entry_tree.dart` (new)

Pure logic, no Flutter imports beyond `meta`, mirroring `day_grouping.dart`'s style.

```dart
class EntryYearGroup {
  final int year;
  final List<EntryMonthGroup> months;      // newest month first
  final Duration totalDuration;
  final Duration breakDuration;
  final int insufficientBreakDays;
}

class EntryMonthGroup {
  final int year;
  final int month;                          // 1-12
  final List<EntryWeekGroup> weeks;         // newest week first
  final Duration totalDuration;
  final Duration breakDuration;
  final int insufficientBreakDays;
}

class EntryWeekGroup {
  final int isoWeek;                        // 1-53
  final DateTime firstDay;                  // earliest day actually contained (local midnight)
  final DateTime lastDay;                   // latest day actually contained
  final List<EntryDayGroup> days;           // newest day first
  final Duration totalDuration;
  final Duration breakDuration;
  final int insufficientBreakDays;
}
```

`buildEntryTree` is the single entry point:

```dart
List<EntryYearGroup> buildEntryTree(
  List<TimeEntry> entries, {
  required List<BreakRuleTier> tiers,
  bool includePausedTimeInBreak = false,
})
```

It calls `groupEntriesByDay` (unchanged behavior) and buckets the resulting day groups:

- **Week key** is the day's Monday (`mondayOf`), which is unique across years — safer than
  `(isoWeekYear, isoWeek)` and needs no ISO-week-year arithmetic.
- **Month/year key** is the *day's own* month and year, never the week's. That is what splits
  a boundary-crossing week: the days 28.–31.12. land under December, 01.–03.01. under
  January, each as its own `EntryWeekGroup` with the same `isoWeek` but different
  `firstDay`/`lastDay`.
- `firstDay`/`lastDay` are the earliest/latest day **actually contained**, not the calendar
  bounds of the ISO week. So the January half of week 53 displays `01.01. – 03.01.`, and its
  `totalDuration` covers those three days only.
- `totalDuration` and `breakDuration` at every level are the plain sum of the contained day
  groups', so each level equals the sum of its children.
- `insufficientBreakDays` is the count of contained days whose `breakDuration` is less than
  their `requiredBreak`.
- Ordering is newest-first at every level, matching today's day ordering.

### Change to `EntryDayGroup` (`lib/features/entries/day_grouping.dart`)

`EntryDayGroup` gains `final Duration? requiredBreak` plus a `bool get isBreakInsufficient`,
and `groupEntriesByDay` gains a `List<BreakRuleTier> tiers = const []` parameter to compute it
via the existing `requiredBreakForWorked`. The parameter is optional rather than required so
the eight existing calls in `day_grouping_test.dart` stay untouched; the risk of a silent
default is contained because after this change `buildEntryTree` — which *does* require
`tiers` — is the function's only production caller. `EntriesList` computes this inline in `build` today; the roll-up
needs the same value, so it moves to the group rather than being computed twice.

The day row's warning then reads that value off the group instead of the call site
recomputing it (`_DayHeader` itself is replaced in §5). No behavior change at the day level.

## 3. ISO weeks — `lib/core/format/iso_week.dart` (new)

```dart
/// Local-midnight Monday of [day]'s ISO 8601 week.
DateTime mondayOf(DateTime day);

/// ISO 8601 week number (1-53) of [day]: weeks start Monday, week 1 is the
/// week containing the first Thursday of the year.
int isoWeekNumber(DateTime day);

/// `2026-08-04` -- the canonical, zero-padded date part of an expansion key.
String isoDayKey(DateTime day);
```

ISO 8601 (Monday start, Thursday rule) is fixed, not locale-derived: all six supported
locales (de, en, es, fr, it, nl) use it, and a locale-dependent week number would make the
same day sit in different weeks per language.

Both functions take and return local dates and ignore the time component.

## 4. Expansion state — `lib/features/entries/entry_tree_expansion.dart` (new)

A `@riverpod` `Notifier` (code generation, as in `report_view_controller.dart`) holding
`Set<String>` of expanded node keys:

| Level | Key |
|-------|-----|
| Year  | `y2026` |
| Month | `m2026-08` |
| Week  | `w2026-08-17-2026-08` (the week's Monday plus the month it sits in) |
| Day   | `d2026-08-18` |

Keys come from four free functions in `entry_tree.dart` — `yearTreeKey(int)`,
`monthTreeKey(int, int)`, `weekTreeKey(DateTime monday, int year, int month)`,
`dayTreeKey(DateTime)` — rather than getters on the node classes, which would force
`day_grouping.dart` to import `entry_tree.dart` and close an import cycle.

The week key carries the month on purpose: the two halves of a month-crossing week share the
same Monday, so a Monday-only key would collapse both halves at once. The month makes each
node's key unique while staying computable from the calendar alone — which the "path to
today" seed needs, since it cannot know which days actually hold entries.

- Initial value is the path to today: `{y<year>, m<year>-<month>, w<monday>, d<today>}`,
  computed once when the provider is first read. An app left open past midnight keeps the
  old seed; acceptable, and consistent with "resets on restart".
- Only today is expanded inside the current week. Yesterday's row is visible with its
  summary; its entries are collapsed.
- API: `void toggle(String key)`. There is no `isExpanded` — the state *is* the set, and the
  widget already watches it, so it asks `expanded.contains(key)` directly.
- Keys of nodes that no longer exist (last entry of a day deleted) stay in the set
  harmlessly; nothing iterates the set, it is only queried.

## 5. Flattening and rendering

### `flattenEntryTree` (in `entry_tree.dart`)

```dart
List<EntryTreeRow> flattenEntryTree(
  List<EntryYearGroup> years,
  Set<String> expanded,
)
```

`EntryTreeRow` is a sealed class with one variant per row kind: `YearRow`, `MonthRow`,
`WeekRow`, `DayRow`, `EntriesRow` (which carries the day's `List<TimeEntry>`). A node's
children are emitted only when its key is in `expanded`; `EntriesRow` is emitted only for an
expanded day. Being a pure function over (tree, expansion set), it is unit-testable across
all collapse permutations without a widget tree.

`EntriesList` then renders `ListView.builder` over these rows, so only visible rows build —
a collapsed year costs one row regardless of how much sits under it.

### `_GroupHeader` (replaces `_DayHeader`)

One widget for all four levels:

```
[›]  August                        ⚠  Pause: 12:15   152:30
 └ left inset = depth * 12px           ↑ only when insufficientBreakDays > 0
```

- Leading chevron: `Icons.keyboard_arrow_right` rotated to down when expanded (an
  `AnimatedRotation`, matching the affordance `ExpansionTile` gives elsewhere in the app).
- The whole row is the tap target (an `InkWell`), not just the chevron.
- Title left, `Expanded`; summary right in a `Wrap` (`alignment: end`) so it moves to a
  second line instead of overflowing in a narrow window: warning icon, then break
  (`entriesBreakLabel`, `bodySmall`), then worked total (`titleSmall`, bold) outermost.
- Worked total renders as a bare duration but is wrapped in
  `Semantics(label: l10n.entriesWorkLabel(value))` so a screen reader announces what the
  number means without adding visual noise.
- The header takes a single nullable `warningTooltip` string: non-null draws the warning icon
  with that message, null draws nothing. The call site picks the wording — a day row passes
  `entriesBreakInsufficientTooltip` ("Break too short") when its own break falls short, a
  rolled-up row passes `entriesBreakInsufficientDaysTooltip(count)` when its count is above
  zero. This keeps the widget free of both a level flag and any break-rule knowledge.
- Break text and warning icon use `colorScheme.error` exactly as the day header does today.
- Day rows keep the existing "Today"/"Yesterday"/formatted-date label logic.

Labels per level:

| Level | Label |
|-------|-------|
| Year  | `2026` |
| Month | `DateFormat.MMMM(localeName)` — month name only, the year is the row above |
| Week  | `entriesWeekHeader(week, range)`, range = `formatDate(firstDay) – formatDate(lastDay)` |
| Day   | unchanged |

Date ranges go through the existing `formatDate` so they follow the user's date-format
setting. `DateFormat.MMMM` needs `initializeDateFormatting` for the locale, which `main.dart`
already does and widget tests must do in `setUpAll` (as they already do for `formatDate`).

Left inset per depth: year 0, month 12, week 24, day 36. The `EntriesRow` card gets the
day's 36px inset so it lines up under its own header rather than under the week.

`_DayEntriesBlock` and `_EntryTile` are untouched: same card, same dividers, same
swipe-to-delete and tap-to-edit. The list's loading, error, and "no entries yet" states stay
exactly as they are — the hierarchy only replaces what happens once there are finished
entries to show.

## 6. i18n

New keys in all six `.arb` files (`app_de.arb` is the template):

| Key | de | en |
|-----|----|----|
| `entriesWeekHeader` | `KW {week} · {range}` | `Week {week} · {range}` |
| `entriesWorkLabel` | `Arbeitszeit: {duration}` | `Worked: {duration}` |
| `entriesBreakInsufficientDaysTooltip` | `{count, plural, =1{1 Tag mit zu kurzer Pause} other{{count} Tage mit zu kurzer Pause}}` | `{count, plural, =1{1 day with a break that is too short} other{{count} days with breaks that are too short}}` |

`entriesBreakInsufficientDaysTooltip` is this project's first ICU plural; `count` is declared
as `{"type": "num"}` in the template's `@`-metadata.

`entriesDayHeader` (`{day} · {total}`) becomes unused once label and summary are separate
widgets and is removed from all six files, following the precedent of the removed
`quickAddMoreTooltip`.

## 7. Testing

New pure-logic tests (no widgets, fully deterministic — fixed dates, never `DateTime.now()`):

- `test/core/format/iso_week_test.dart`: `mondayOf` across a month boundary; `isoWeekNumber`
  for a mid-year date, for 01.01. landing in week 53 of the previous year, for 31.12. landing
  in week 1 of the next year, and for a 53-week year.
- `test/features/entries/entry_tree_test.dart`: sums roll up so each level equals the sum of
  its children; a week spanning a month boundary appears under both months with only its own
  days and a `firstDay`/`lastDay` limited to them; `insufficientBreakDays` counts correctly at
  each level; newest-first ordering at every level; empty input yields an empty list.
- Flattening: everything collapsed yields one row per year; expanding a year adds exactly its
  months; a day's `EntriesRow` appears only when that day is expanded; expansion keys for
  non-existent nodes are ignored.

New widget tests in `entries_list_test.dart`: with everything collapsed only year rows render;
with the default seed today's entries are visible; tapping a year row reveals its months;
a year row shows worked and break sums.

Existing tests to update:

- `entries_list_test.dart` asserts `'Today · 01:00'` and a fixed number of `Card`s — the
  split label/summary layout and the collapsed siblings change both.
- `day_grouping_test.dart` — new `tiers` parameter.
- `quick_add_bar_test.dart` and `timer_screen_test.dart` pump `EntriesList` and assert that a
  created entry is visible; they must still pass given today's path is expanded by default.

## 8. Out of Scope

- Persisting the expansion state across app restarts (explicitly declined: needs a settings
  column, a Drift migration, and sync considerations for pure UI state).
- An "expand/collapse all" control.
- Any change to `ReportsScreen`, CSV export, or `report_calculations.dart`.
- Any change to `_EntryTile` itself (no date added to the row, since the day level provides it).
- Locale-dependent week numbering or a configurable week start.
