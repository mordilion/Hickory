# Entries List (drill-down hierarchy)

## Entities

No dedicated entity — reads `TimeEntry` through `allEntriesProvider` and writes only via
the existing delete/edit paths. This feature is UI plus pure grouping logic.

## Architecture

- `EntriesList` (`lib/features/entries/entries_list.dart`) shows **one level at a time**:
  years → months → one ISO week. The week is the deepest level and lists its days, each
  with a day sub-header plus that day's `_DayEntriesBlock`. A breadcrumb (`_Breadcrumb`)
  carries the path back up; the years list shows none, so nothing eats the space there.
- Grouping is pure and widget-free: `buildEntryTree` (`entry_tree.dart`) turns entries into
  Year → Month → Week → Day with worked time, break time and a count of days that fall
  short of the break rule rolled up to every level. `groupEntriesByDay`
  (`day_grouping.dart`) supplies the day level and now also each day's `requiredBreak` /
  `isBreakInsufficient`.
- Navigation is `EntriesLocation` (`entries_location.dart`): a sealed
  years/year/month/week location plus the pure `initialLocation`, `viewFor` and `parentOf`.
  The `EntriesLocationController` notifier is `keepAlive` and holds **null** until the user
  navigates — the widget resolves null through `initialLocation`, because only it knows
  what data exists. Not persisted: every app start reopens the current week.
- ISO week maths lives in `lib/core/format/iso_week.dart` (`mondayOf`, `isoWeekNumber`,
  `isoDayKey`), fixed to ISO 8601 rather than locale-derived.

## Decisions

- **A week crossing a month boundary is split at that boundary**, so month and year totals
  equal the calendar period they name — that matters for billing. The two halves share a
  Monday, which is why `EntriesWeekLocation` carries year and month alongside `monday`.
- **The day is not a level of its own.** An earlier design made it a fourth clickable
  level; in a drill-down that view would often hold two rows. Its totals and break warning
  moved to the day sub-header inside the week view.
- **Rolled-up rows mark a short break with a dot and a counting tooltip**, not the day's
  triangle: one offending day used to shout from every level above it.
- **The break-rule verdict is computed once**, on the day group, because the roll-up counts
  offending days and the sub-header renders the warning.
- **The Jira error tooltip shows the stored `lastError`**, not a generic string. The message
  is already sanitised of credentials by `JiraSyncService._safeErrorMessage`, so the UI can
  render it verbatim; the localised generic string is only the fallback for a row without a
  stored message (an older row, or state received from another device before the message).
  See docs/superpowers/specs/2026-08-19-sync-error-visibility-design.md §2.
- Opening on the current week (falling back to the newest week with entries) replaced the
  earlier "expand the path to today" seed. Same intent, no stored expansion state.

## Gotchas

- **A widget test that pumps `EntriesList` must mount `theme: AppTheme.light`.** The rows
  read muted and accent colors from `HickoryColors`, whose lookup asserts when the
  `ThemeExtension` is missing. A bare `MaterialApp` fails at build time and the visible
  symptom is a follow-on `RenderFlex overflowed by 99400 pixels` from the error widget —
  the overflow is not the cause.
- **A test using fixed dates must pin the location**, by overriding
  `entriesLocationControllerProvider` with a subclass whose `build()` returns the wanted
  `EntriesWeekLocation`. Otherwise the list opens on the current week and the entry under
  test is simply not on screen; the failure reads as "finder found 0 widgets" for the entry
  text, which looks like a rendering bug rather than a navigation one.
- **The week of a fixed date is rarely the date's own Monday.** 2026-07-01 is a Wednesday,
  so its `EntriesWeekLocation` monday is 2026-06-29 while year/month stay July — the June
  days are a separate node.
- **Scoping an assertion to one level:** a day's sums sit in the same `Row` as its label,
  so `find.ancestor(of: find.text('Today'), matching: find.byType(Row))` pins an assertion
  to that day. Over single-level data the identical numbers also appear on rolled-up rows,
  and a bare `find.text` matches several times.
- `formatDuration` output is compared verbatim in tests (`'01:00'`), which depends on the
  `24h` setting the test harnesses override. Changing that override changes those strings.

## Out of scope (intentionally)

- Persisting the location across app restarts (needs a settings column, a migration and a
  sync decision for pure UI state).
- An "expand/collapse all" or multi-level view — superseded by drill-down.
- Any change to `_EntryTile`, `ReportsScreen`, CSV export or `report_calculations.dart`.
- Locale-dependent week numbering or a configurable week start.
