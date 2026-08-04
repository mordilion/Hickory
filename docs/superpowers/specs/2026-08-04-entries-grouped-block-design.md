# Entries List: Grouped Day Block Design

**Date**: 2026-08-04
**Status**: Approved
**Scope**: `lib/features/entries/entries_list.dart` only

## Context

The 2026-07-07 Electric Violet redesign deliberately made each time entry its
own pill-shaped row ("each entry is its own pill-shaped row (not a divided
list)" — see `docs/superpowers/specs/2026-07-07-electric-violet-redesign-design.md`
line 70). In practice, a day with several entries renders as a stack of
separate rounded pills with visible gaps between them, and each pill is
independently fully rounded (`StadiumBorder`).

The user wants all entries for a single day visually grouped into one
contiguous block, with rounding applied at the block level rather than to
each individual entry. This spec reverses the "no divided list" decision for
the entries list specifically; it does not change pill shapes used elsewhere
(buttons, chips, nav indicator — see `lib/core/theme/app_theme.dart`).

## Decision

For each day group produced by `groupEntriesByDay`:

- Render **one `Card`** per day (using the theme's default `CardThemeData`
  shape — `RoundedRectangleBorder` at `_cardRadius` = 24px — no per-widget
  shape override needed), with `clipBehavior: Clip.antiAlias` so that the
  swipe-to-delete background is clipped to the card's rounded corners instead
  of bleeding past them during a swipe gesture.
- Inside the card, lay out the day's entries as a `Column` of rows (the
  existing `ListTile` content, unchanged), separated by `Divider(height: 1)`.
  No divider after the last entry in the group.
- Each entry row stays individually wrapped in `Dismissible` for
  swipe-to-delete — this is unchanged behavior, just clipped differently (see
  above).
- The day header (`_DayHeader`: date label, total duration, break duration/
  warning) stays a freestanding element above the block, with its existing
  padding — it is not absorbed into the card.

## Structural change

`EntriesList.build` currently flattens groups into a single list of
`_HeaderRow` / `_EntryRow` items and feeds them to `ListView.builder` one row
at a time. Because a day's entries now render as one combined `Card` instead
of N independent cards, the per-entry list-item structure no longer fits.

`ListView.builder` will instead have one item per day group, each item
building `_DayHeader` followed by the new day-block `Card`. Group count is
typically small (a handful of days visible at once), so this is not a
performance concern.

## Out of scope

- No changes to `app_theme.dart` pill/stadium tokens used elsewhere (buttons,
  chips, nav bar).
- No changes to the manual entry dialog, quick-add bar, or Jira status icon
  logic.
- No changes to bottom padding reserved for the FAB (existing requirement
  from the 2026-07-07 spec), which is unaffected by this change.
