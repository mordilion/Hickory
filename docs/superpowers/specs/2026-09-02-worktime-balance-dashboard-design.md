# Work-Time Balance & Reporting Dashboard — Design

Date: 2026-09-02
Status: Approved for planning

## 1. Goal & Scope

Add a dashboard to the Reports tab that answers "am I ahead or behind?" — an overtime
balance ("Gleitzeitkonto") plus the figures that make it trustworthy. Overtime does not
exist in the app today: `AppSettings` holds no target work time, so there is nothing to
measure tracked time against. This design therefore covers three things at once:

1. **Target work time** — per weekday or per week, plus a configurable rule for when the
   balance is reset or carried over.
2. **Absences** — user-defined types (vacation, sick, public holiday, …) with a paid flag,
   recorded as a third entry mode on the main screen, and switchable off entirely.
3. **The dashboard itself** — balance, a worked-vs-target chart, billability and revenue,
   and a tracking-quality block.

Parts of this were already designed in
`docs/superpowers/specs/2026-07-17-worktime-calendar-rules-design.md`, of which only
`BreakRuleTiers` was ever implemented. This spec supersedes that document's target-hours,
balance and exception-day sections. It deliberately does **not** revive the calendar view
or the window-resizing work from it; see Section 8.

## 2. Data Model

### `AppSettings` — new columns

The existing singleton row (`appSettingsRowId`), already synced whole-row with
last-write-wins. `schemaVersion` is currently 8; each phase that changes the schema raises
it by one — 9 for these columns in phase 1, 10 for the tables added in phases 2 and 3.

| Column | Type | Notes |
|---|---|---|
| `targetMinutesMonday` … `targetMinutesSunday` | int, default `0` | Daily target in minutes. `0` means "not a work day" and doubles as the free-day marker. **The single source of truth for every calculation.** Defaults to `0` so existing users are not retroactively put into deficit. |
| `targetInputMode` | text, default `perWeekday` | `perWeekday` \| `perWeek`. Affects only how the settings screen renders and reopens. A weekly figure is distributed across the chosen work days on save (remainder spread minute-wise so the days sum exactly to the weekly value); it is never stored as a separate number, so no second calculation path exists. |
| `balanceResetMode` | text, default `none` | `none` \| `resetToZero` \| `carryOver`. |
| `balanceResetDay`, `balanceResetMonth` | int, nullable | The recurring cutoff (day + month), so a fiscal year end works as well as a calendar one. Required when the mode is not `none`. |
| `carryOverMaxMinutes`, `carryOverMinMinutes` | int, nullable | Upper and lower bound of what survives a cutoff, `carryOver` mode only. `null` = unbounded on that side. |
| `absenceTrackingEnabled` | bool, default `false` | The global switch for Section 2's absence feature. |

Extending `AppSettings` rather than adding a settings table follows the table's own
documented intent and keeps these scalar, fixed-cardinality values on the singleton that
already syncs.

### `AbsenceTypes` — new synced table

| Column | Type | Notes |
|---|---|---|
| `id` | text, PK | |
| `name` | text | User-defined, e.g. "Vacation", "Sick leave". |
| `paid` | bool | See Section 3 for what paid vs. unpaid changes. |
| `sortOrder` | int | Display order in pickers and settings. |
| `deviceId`, `createdAt`, `updatedAt` | | Same convention as `TimeEntries`. |

Fully editable in Settings: add, rename, toggle paid, reorder, delete. Deleting a type
that is still referenced by an `Absences` row is **refused** with a message naming the
count, rather than orphaning rows — the synced tables carry no foreign keys by design, so
this check lives in the application layer.

**No automatic seeding.** Seeding defaults at database creation would have every device
create its own "Vacation" row; all of them would then sync and the user would end up with
duplicates. Instead the settings screen offers an explicit "Add standard types" button,
which the user presses once on one device.

### `Absences` — new synced table

| Column | Type | Notes |
|---|---|---|
| `id` | text, PK | |
| `date` | datetime | The calendar day this absence covers, stored as that day's **local** midnight — the same key `totalsByDay` already groups worked time by, so the two line up without conversion. |
| `absenceTypeId` | text | References `AbsenceTypes.id` (no DB-level FK, as above). |
| `portion` | text | `fullDay` \| `halfDay` \| `range`. |
| `startAt`, `endAt` | datetime, nullable | Set only when `portion == range`; UTC, same convention as `TimeEntries`. |
| `note` | text, nullable | |
| `deviceId`, `createdAt`, `updatedAt` | | Same convention as `TimeEntries`. |

**One row per day.** A two-week vacation entered once in the form produces one row per
affected day, skipping days whose target is `0`. This keeps the calculation a simple
per-day lookup and lets a single day be removed later; the cost is that a bulk entry is
several writes, which the write-through sync handles the same way it handles any batch.

**`fullDay` and `halfDay` store no minute figure**, only the portion. The credited time is
derived from the day's target at display time, so an absence stays correct if the target
is changed afterwards.

### `BalanceAdjustments` — new synced table

| Column | Type | Notes |
|---|---|---|
| `id` | text, PK | |
| `date` | datetime | Effective date, as local midnight — same convention as `Absences.date`. |
| `deltaMinutes` | int, signed | |
| `note` | text, nullable | E.g. "3 days paid out". |
| `deviceId`, `createdAt`, `updatedAt` | | Same convention as `TimeEntries`. |

Available regardless of the reset mode, so every manual correction stays dated, annotated
and reversible instead of silently rewriting history.

### Sync wiring

`AbsenceTypes`, `Absences` and `BalanceAdjustments` each get an `EntityTypes` constant, a
`SyncedWrites` write-through method, a case in `SyncIngestor._applyMaterializedEntity`,
and a round-trip test — the same per-row event-log pattern as every existing entity. The
`AppSettings` columns ride along on the existing singleton sync.

## 3. Calculation

A pure Dart module with no Riverpod or Flutter dependency, mirroring
`report_calculations.dart`, exposed through plain Riverpod providers. Nothing is
materialized: a cached balance would need recomputation after every cross-device event-log
merge, and those merges happen at arbitrary times.

**Per day:**

```
dayBalance = worked + paidCredit − effectiveTarget
```

- `worked` — the day's tracked time, as `totalsByDay` already computes it.
- `effectiveTarget` — `targetMinutes[weekday]`, reduced by the portion covered by
  **unpaid** absences.
- `paidCredit` — the portion covered by **paid** absences: `fullDay` credits the day's
  target, `halfDay` half of it, `range` its own duration **minus any overlap with tracked
  entries**, so a doctor's appointment that was also tracked as work cannot be counted
  twice. `fullDay` and `halfDay` are deliberately not reduced by tracked time: someone who
  works on a vacation day should see that time as a plus.

Paid and unpaid are both neutral for the balance on a full day; they differ in the target
that gets reported, which is exactly what the flag is for. A day with target `0` is not a
work day, so time tracked on it counts fully as a plus.

**With the absence switch off, absences are ignored entirely** — existing rows stay in the
database and reappear untouched when the switch is turned back on.

**With no targets configured at all** (the default: all seven weekdays `0`), every tracked
minute would read as overtime. The balance tiles and the trend's target line therefore show
an empty state pointing at the settings screen instead of a number, until at least one
weekday has a target.

**The absence switch changes how gaps are read**, and this is the feature's real payoff:

| `absenceTrackingEnabled` | Days entering the balance |
|---|---|
| off | Only days that have at least one tracked entry. A day off cannot be recorded, so counting it would manufacture a deficit. |
| on | Every work day. A work day with neither entries nor an absence shows up as a deficit — a forgotten day becomes visible instead of hiding as if it were vacation. |

**The cutoff is applied in a single forward pass** over the days from the first tracked day
to the end of the period. Whenever a cutoff date is crossed, the running balance is set to
`0` (`resetToZero`) or clamped into `[carryOverMinMinutes, carryOverMaxMinutes]`
(`carryOver`). No recursion over years, deterministic, and one pass regardless of history
length. `BalanceAdjustments` are added on their effective date, before that date's cutoff
is evaluated.

**Reported figures:** balance since the last cutoff (independent of the selected report
range), balance within the selected range, target and actual for the range, and the
average per work day.

## 4. Settings UI

Two new entries on the settings home screen, each its own screen file, rather than
enlarging the already busy time-tracking page.

**Work time & balance:**
- A `perWeekday` / `perWeek` toggle. Weekly mode shows one hours field plus work-day
  checkboxes; per-weekday mode shows seven fields.
- The reset rule: none / reset to zero / carry over with caps, with the day+month cutoff
  and the two bounds revealed only when the selected mode uses them. A mode other than
  `none` cannot be saved without a cutoff date, and `carryOver` needs at least one of the
  two bounds — the screen refuses the save and says which field is missing rather than
  persisting a rule the calculation would have to guess at.

**Absences:**
- The global switch.
- The type list with add, rename, reorder, delete and a paid toggle each, plus the
  "Add standard types" button. The list stays visible when the switch is off; only the
  third entry mode and the dashboard's absence blocks disappear.

## 5. Main-Screen UI

The main screen's existing two-segment `SegmentedButton` (`timer_screen.dart`) gains a
third segment, **Absence**, rendered only when absence tracking is enabled. It selects a
form built like `QuickAddBar`: type picker, single date or from/to date, portion
(`fullDay` / `halfDay` / `range`, the last revealing time fields), and a note.

Absences appear **in the entries list**, as their own row inside the day they belong to,
with a distinct icon and the type's name — and that is where they are edited and deleted.
Without this, the main screen would create records the user can never see again there.
This is the only change to `entries_list.dart`.

## 6. Reports-Tab Dashboard

The range chips and the filter button stay where they are; everything below them becomes
one scrollable column:

1. **Balance** — four tiles: balance since the cutoff (with the cutoff's date), balance
   within the range, target vs. actual with a progress bar, and average per work day.
   Sign is conveyed by an icon **and** color, never color alone.
2. **Trend** — bars per day, switching automatically to per week beyond roughly two
   months, with a target line. Drawn with `CustomPainter`: the project has no charting
   dependency and this does not warrant adding one. Hover tooltip on desktop, and a
   `Semantics` label per bar as the accessible equivalent.
3. **Money & billability** — billable share as a percentage, revenue per currency, top
   clients, computed from the existing `billable` / `hourlyRateCents` fields.
4. **Tracking quality** — work days with no booking, days with too short a break (reusing
   `break_rule_calculations.dart`), failed Jira/Personio pushes (reusing
   `failed_pushes.dart` from the Sync tab), and absence days per type.
5. **The existing project list and CSV export**, unchanged.

**The project and billable filters must not reach the balance.** "Overtime, but only for
project X" is not a meaningful number. Blocks 1, 2 and 4 therefore always compute over all
entries in the range; only block 3 and the project list follow the filter, and the tiles
carry a note whenever a filter is active.

## 7. Testing

- **Calculation module** — unit tests per rule: the cutoff pass across year boundaries,
  carry-over clamping at both bounds, paid vs. unpaid absences, half days, ranges,
  adjustments landing on a cutoff date, and both settings of the absence switch.
- **DAOs** — against a fresh `AppDatabase.forTesting`, the existing convention. As with
  the earlier specs, the `onUpgrade` path itself is not exercised; the tests verify the new
  columns and tables behave once created.
- **Sync** — a round-trip test per new entity type, following the existing pattern.
- **Widgets** — the two settings screens, the absence form, the absence row in the entries
  list, and each dashboard block.
- **l10n** — every new string goes into all six ARB files; `arb_completeness_test.dart`
  fails the build otherwise. German is the template locale.

## 8. Phasing

Each phase is independently demonstrable.

| Phase | Contents |
|---|---|
| 1 | `AppSettings` targets and reset rule, the work-time settings screen, the pure calculation module, and a first balance tile in the Reports tab |
| 2 | Absences: type CRUD, the `Absences` table, the third segment, the entries-list row, the switch, and their effect on the calculation |
| 3 | The full dashboard: remaining tiles, trend chart, money and quality blocks, `BalanceAdjustments` and its correction dialog |

## 9. Out of Scope

- **The calendar view** (month/week grid) from the 2026-07-17 spec. The dashboard answers
  the "did I work enough" question without it; a calendar is a separate feature.
- **Window resizing** from that same spec — unrelated to this work.
- **Minimum rest time between work days** and live warnings during work.
- **Automatic public-holiday import** for a country or region. Holidays are absence days
  entered like any other; an importer can fill the same table later.
- **Payroll-grade exports.** The CSV export stays as it is.
