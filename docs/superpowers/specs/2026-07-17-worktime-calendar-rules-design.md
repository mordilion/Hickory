# Work-Time Calendar & Rules — Design

Date: 2026-07-17
Status: Approved for planning

## 1. Goal & Scope

Add a **Calendar** view that shows tracked time visually (month and week views) so the
user can check whether they worked enough — against a set of configurable work-time
rules. No specific country's labor law is hard-coded; every threshold is user-defined,
since Hickory is used internationally. A running overtime/undertime balance
("Gleitzeitkonto") complements the target-hours comparison. The current fixed
400×800 window size is lifted (freely resizable) since a month grid needs more width
than the existing phone-like layout.

Rule types covered in v1 (selected from a broader set of possibilities):
- Minimum/maximum work time per day
- Minimum break time, tiered by hours worked
- Weekly/monthly target hours (derived from per-weekday targets, not a separate raw number)
- A cumulative overtime/undertime balance with manual, auditable adjustments

Deliberately **not** in v1 (see Section 7 for why and what a later iteration could add):
minimum rest time between work days, live/proactive warnings during work, holiday
auto-import, adaptive navigation for wide windows.

## 2. Data Model

### `AppSettings` table extended (existing singleton row, already synced)
New columns, migration `schemaVersion` 4 → 5:

| Column | Type | Notes |
|---|---|---|
| `targetMinutesMonday` … `targetMinutesSunday` | int, default `0` | Per-weekday target work time in minutes. `0` means "not a work day" and doubles as the free-day marker — no separate flag needed. Defaults to `0` for all seven days so existing users aren't retroactively flagged until they configure it. |
| `maxDailyMinutes` | int, nullable | Daily maximum. `null` = no maximum rule configured. |

Rationale for extending `AppSettings` rather than a new settings table: the table's
existing doc comment already anticipates this ("holds more than just date/time format
so a future setting can be added as a new column ... without introducing a second
synced singleton entity type"), and these are scalar, fixed-cardinality values — not a
list, so no 1NF concerns.

### New `BreakRuleTiers` table (own synced entity — variable-length list, so not a
column on `AppSettings`)

| Column | Type | Notes |
|---|---|---|
| `id` | text, PK | |
| `afterMinutes` | int | Worked-minutes threshold at which this tier applies. |
| `requiredBreakMinutes` | int | Break minutes required once `afterMinutes` is reached. |
| `deviceId` | text | Sync origin, same convention as `TimeEntries`. |
| `createdAt` / `updatedAt` | datetime | |

Evaluation picks the tier with the highest `afterMinutes` that is `<=` the day's
worked minutes, then compares the day's actual break time against
`requiredBreakMinutes`. No tiers configured = no break rule enforced.

### New `DayExceptions` table (own synced entity)

| Column | Type | Notes |
|---|---|---|
| `id` | text, PK | |
| `date` | date, unique | One exception per calendar day. |
| `type` | text | `holiday` \| `vacation` \| `sick` \| `custom`. |
| `note` | text, nullable | |
| `deviceId`, `createdAt`, `updatedAt` | | Same convention as `TimeEntries`. |

Marks a specific day as non-working regardless of its weekday's configured target —
settable directly from the calendar day-detail view (not from Settings). A day with an
exception has both day-level rules (min/max) suspended entirely, and contributes `0`
to the period's target-hours sum.

### New `BalanceAdjustments` table (own synced entity)

| Column | Type | Notes |
|---|---|---|
| `id` | text, PK | |
| `date` | date | Effective date of the correction. |
| `deltaMinutes` | int, signed | Positive or negative correction. |
| `note` | text, nullable | E.g. "year-end reset". |
| `deviceId`, `createdAt`, `updatedAt` | | Same convention as `TimeEntries`. |

Lets the user correct or reset the running balance (e.g. to `0` at year end) without
destroying history: a reset is just a new adjustment row with a delta that offsets the
accumulated total as of that date, so every correction stays auditable.

### Sync wiring

`BreakRuleTiers`, `DayExceptions`, and `BalanceAdjustments` each get a new
`EntityTypes` constant, a `SyncedWrites` method, and a case in
`SyncIngestor._applyMaterializedEntity` — the exact same per-row event-log pattern
already used for `TimeEntries`, `Projects`, `Tags`, etc. The `AppSettings` extension
rides along on the existing singleton-row sync (whole row, last-write-wins).

## 3. Calculation Logic

New pure-Dart module (no Riverpod/DB dependency in the module itself, mirroring
`report_calculations.dart`), exposed via Riverpod providers (mirroring
`reports_providers.dart`) — computed on demand, nothing materialized in the database.
This choice avoids a whole class of invalidation bugs the sync engine would otherwise
create: a materialized compliance table would need recomputation after every
cross-device event-log merge, and that merge can happen at arbitrary times.

- **Daily worked time**: sum of every entry touching the day; an entry spanning
  midnight is split proportionally at the boundary (e.g. 23:00–01:00 contributes 1h to
  each of the two days).
- **Min/max work time per day**: worked minutes vs. `targetMinutes[weekday]` (minimum)
  and `maxDailyMinutes` (maximum, if set). Both are skipped entirely on a day that has
  a `DayExceptions` row.
- **Break rule**: sum of gaps between entries *within the same calendar day* only —
  the overnight gap between one day's last entry and the next day's first entry is
  never counted (it crosses a day boundary; see Section 7 for reusing it later for a
  rest-time rule). Compared against the applicable `BreakRuleTiers` tier.
- **Weekly/monthly target**: sum of `targetMinutes[weekday]` across the period's days,
  with exception days contributing `0`, compared against the summed worked minutes for
  the same period. This is a derived value, not a separately configured number, so
  there's only one place (`AppSettings`) where target hours are set.
- **Running balance**: cumulative `Σ(worked − target)` across all days up to a given
  date, plus `Σ(deltaMinutes)` from `BalanceAdjustments` up to that date.

## 4. UI

- **New "Calendar" tab** in `AppShell`'s navigation (new `NavigationDestination`,
  `calendar_month` icon), positioned between Reports and Sync.
- **Month view** (default): 7-column grid; each cell shows the date, worked hours, and
  a status indicator using icon *and* color together (not color alone, per the
  project's accessibility rules) — e.g. a check/warning/error glyph, plus a distinct
  glyph for exception days. Tapping a day opens a detail view: its entries, break
  check, target vs. actual, and a "Mark as vacation/holiday" action that writes a
  `DayExceptions` row.
- **Week view**: toggled via an app-bar control; columns are weekdays, entries render
  as time blocks, each day's header shows worked/target and break status.
- **Balance display**: shown in the calendar's header/footer as the running total, with
  an "Add adjustment" action opening a dialog (date, delta, note) that writes a
  `BalanceAdjustments` row.
- **New Settings section "Work-Time Rules"**: seven weekday-target input fields, a
  daily-maximum field, and an add/remove list for break tiers. Exception days are
  managed from the calendar, not from Settings.

## 5. Window Size & Layout

`WindowTrayController` (`lib/core/window/window_tray_controller.dart`) changes:
- `setResizable(false)` → `setResizable(true)`; drop the `setMaximumSize` call
  entirely (no upper bound).
- `setMinimumSize` keeps the current `Size(400, 800)` as a floor, so the existing
  narrow layout still has a guaranteed minimum to render into.
- Window size/position is persisted **locally only**: `WindowListener`'s
  `onWindowResized`/`onWindowMoved` callbacks write a small local file (in the
  app-support directory resolved via `path_provider`, already a dependency — no new
  package needed), restored on the next launch. This deliberately does **not** go
  through the sync event log: window geometry is a per-device UI preference, not
  synchronized business data.
- The calendar screen is responsive: near the 400px minimum it falls back to a
  compact/scrollable layout; at greater widths it renders the full month grid.
  Bottom navigation itself is unchanged (see Section 7 for a possible future
  `NavigationRail` on wide windows).

## 6. Testing

- Calculation module: unit tests per rule (day min/max, tiered break rule, weekly/
  monthly target with exception days, balance accumulation across adjustments,
  midnight-split attribution) — pure functions, no widget/DB harness needed.
- Migration test: `schemaVersion` 4 → 5 preserves existing `AppSettings` row and
  defaults new columns to `0`/`null` as specified (same pattern as
  `docs/superpowers/plans/2026-07-08-user-configurable-date-time-format.md`'s
  migration tests).
- Sync round-trip test for the three new entity types, following the existing
  `TimeEntries` sync test pattern.

## 7. Future Ideas (explicitly out of scope for v1)

- **Minimum rest time between work days** (e.g. 11h) — the overnight gap is already
  computed and discarded in Section 3; a later rule can reuse it directly.
- **Live/proactive warnings** during work (e.g. a system notification when a max is
  exceeded or a break is overdue), instead of only reviewing the calendar after the
  fact.
- **Extended export**: augment the existing CSV export (`csv_export.dart`) with a
  compliance/violation summary suitable as documentation for an employer.
- **Automatic holiday import** for a selectable country/region, instead of marking
  every exception day by hand.
- **`NavigationRail` instead of bottom navigation** on wide windows, for a more
  desktop-appropriate layout once resizing is in place.
