# Quick Entry & Overview Redesign — Design

Date: 2026-08-03
Status: Approved for planning

## 1. Goal & Scope

Reduce manual time-entry creation to as few taps as possible, and make the entries
list easier to scan at a glance ("übersichtlich"). Today, adding a manual entry means:
tap the FAB → fill description/project/Jira in a modal dialog → open a date picker and
a time picker for the start → repeat for the end → Save. That's the primary friction
point being addressed.

In scope:
- A persistent quick-add bar on the Timer tab that creates today's entries with
  minimal taps (duration presets instead of two full date+time pickers).
- User-configurable duration presets (Settings).
- Grouping the entries list by day with a per-day total.

Explicitly out of scope (unchanged):
- The existing full manual-entry dialog (`manual_entry_dialog.dart`) — kept as-is,
  reused for anything the quick-add bar can't do (a different day, precise timestamp
  edits, editing an existing entry).
- Timer start/stop/pause flow (`_RunningCard`/`_StartCard`) — untouched.
- Jira ticket linking mechanics (`JiraTicketField`) — reused, not redesigned.

## 2. Quick-Add Bar

Replaces the FAB. Pinned above `EntriesList`, below the running/start timer card, on
the Timer tab only.

```
[Description............] [Project ▾] [15][30][45][60] [08:15–09:00] [🎫] [📅] [＋]
```

- **Description**: text field, same semantics as the existing dialog's field.
- **Project**: dropdown, same items/behavior as the existing dialog's field.
- **Duration chips**: tappable presets, minutes, user-configurable (Section 4). Tapping
  a chip sets `end = now`, `start = now − duration`, and updates the start–end text.
- **Start–end text** (e.g. `08:15–09:00`): reflects the current computed range. Tapping
  the start or end value lets the user nudge that single time value (hour/minute only —
  no date picker, since the bar is today-only); the other bound stays fixed, so nudging
  the end time changes duration, and nudging the start time also changes duration.
- **🎫 (Jira) icon**: toggles a collapsed row below the bar containing the existing
  `JiraTicketField`. Collapsed by default since most entries have no ticket.
- **📅 (more) icon**: opens the existing full `_ManualEntryDialog`, prefilled with the
  bar's current description/project, for anything outside today (a different date) or
  needing exact timestamps. This is the FAB's old destination, now reached from here
  instead of a separate floating button.
- **＋ (submit)**: creates the entry via the existing `SyncedWrites.createManualEntry`
  path. After submit, description and duration reset to defaults; the selected project
  and Jira ticket persist, since logging several consecutive entries for the same
  project/ticket is a common pattern this optimizes for.

Validation (end before start, etc.) reuses the same rule as the existing dialog.

Editing an existing entry is unchanged: tapping an entry row in `EntriesList` still
opens `_ManualEntryDialog` with that entry loaded.

## 3. FAB Removal

`AppShell.fabBuilder` for the Timer tab is removed. The quick-add bar's 📅 icon is the
sole remaining entry point to the full dialog for new entries; the entries list's tap
handler remains the entry point for editing.

## 4. Configurable Duration Presets

### Data model

`AppSettings` table extended (existing singleton row, already synced), migration
`schemaVersion` 4 → 5:

| Column | Type | Notes |
|---|---|---|
| `quickAddDurationsMinutes` | text, default `'15,30,45,60'` | Comma-separated ascending list of minute values, rendered as the quick-add bar's chips in that order. |

Rationale for a comma-separated column over a new table: this is a small, per-user,
scalar-shaped list (not a relational entity with its own identity/lifecycle), and it
rides along on the existing singleton-row sync exactly like the calendar feature's
`targetMinutes*` columns did — no new `EntityTypes` case or sync-ingestor wiring needed.

### Settings UI

New "Quick Add" section on the Settings screen: a chip editor mirroring the visual
style of the quick-add bar's own chips — each existing duration renders as a removable
chip (`45m ✕`), plus a trailing "add" chip that opens a small numeric input (minutes,
positive integer) for a new preset. Removing the last chip is allowed (an empty preset
list simply means the quick-add bar shows no chips, start/end text nudging still
works). Duplicate values are silently ignored on add.

## 5. Entries List Grouped by Day

`EntriesList` groups the existing `finished` entries (already sorted newest-first) by
local calendar day, and renders a non-sticky header row above each day's entries:

- **Label**: `Today` / `Yesterday` (localized) for the two most recent days; the
  existing `formatDate` (per the user's configured date style) for older days.
- **Total**: sum of `workedDuration` across that day's entries, formatted with the
  existing `formatDuration`, e.g. `Today · 3h 20m`.

No sticky/pinned header behavior — headers scroll with the list, keeping this a
straightforward list transformation rather than a custom sliver layout. The existing
swipe-to-delete, tap-to-edit, and Jira status icon behavior on individual entry rows is
unchanged.

## 6. Testing

- Duration-preset parsing/serialization (comma-separated string ↔ `List<int>`,
  including malformed/empty-string fallback to the default list): unit tests.
- Day-grouping logic (grouping + per-day total computation, including a day with a
  single entry and an empty entries list): unit tests, pure function extracted from
  `EntriesList` so it's testable without a widget harness.
- `AppSettingsDao` test for the new column, following the existing
  `app_settings_dao_test.dart` convention.
- Widget test: quick-add bar creates an entry with the expected start/end when a
  duration chip is tapped, and that the entry appears under today's group header.

## 7. Future Ideas (explicitly out of scope)

- Sticky/pinned day headers while scrolling.
- One-tap "duplicate last entry" action on existing rows (a related but distinct
  quick-entry mechanism, not needed once the quick-add bar itself is fast).
- "Start defaults to end of last entry" behavior — considered during design, not
  chosen; could be added later as an option if back-to-back logging is common enough
  to warrant it.
