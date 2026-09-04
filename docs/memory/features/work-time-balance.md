# Work-Time Balance (flex-time / "Gleitzeit")

## Entities

- `AppSettingsRow` (`lib/data/drift/tables/app_settings_table.dart`) carries the whole
  feature: `targetMinutesMonday` … `targetMinutesSunday` (one `int` per weekday, `0` means
  not a work day), `targetInputMode` (`'perWeekday'` | `'perWeek'`), `balanceResetMode`
  (`'none'` | `'resetToZero'` | `'carryOver'`), `balanceResetDay` / `balanceResetMonth`
  (nullable cutoff date), `carryOverMaxMinutes` / `carryOverMinMinutes` (nullable bounds).
  No dedicated balance table — the balance is never persisted (see below).
- `test/support/app_settings_fixture.dart` builds an `AppSettingsRow` for tests with every
  field defaulted to what a fresh install holds; extend it, not the generated constructor,
  when adding a settings column.

## Architecture

- `lib/features/reports/balance_calculations.dart` is the pure calculation core: no
  Riverpod, no Flutter, no database access beyond drift's row types.
  - `targetMinutesForWeekday` / `hasAnyTarget` read the seven weekday columns.
  - `dayBalances` groups worked time per day (via `report_calculations.dart`'s
    `totalsByDay`) against that day's target.
  - `lastCutoffOnOrBefore` / `runningBalance` apply the yearly cutoff rule.
- `lib/features/settings/work_time_targets_editor.dart` and
  `weekly_target_distribution.dart`: the per-weekday/per-week target editor.
  **The seven weekday columns are the single source of truth.** `targetInputMode` only
  controls which editor UI is shown; picking "per week" distributes one weekly number
  across the seven columns via `weekly_target_distribution.dart` and writes them the same
  way the per-weekday editor does — there is no separate "weekly target" value stored
  anywhere, so a switch back to per-weekday shows exactly what per-week last wrote.
- `lib/features/settings/balance_rule_editor.dart`: the cutoff-rule editor. Keeps an
  incomplete selection (mode chosen but no date, or carry-over with no bound) local and
  never persists it — `SyncedWrites` only ever sees a complete rule.
- `lib/features/reports/reports_providers.dart`'s `workTimeBalanceProvider` and
  `lib/features/reports/balance_card.dart`'s `BalanceCard`: the Reports-tab display.

## Decisions

- **The cutoff walk is a single forward pass, never recursive.** `runningBalance` seeds at
  the first worked day (not the epoch) and walks forward once, applying `_afterCutoff`
  whenever a cutoff falls between the previous day and the current one. A recursive
  "balance of the previous period" formulation would re-walk the same years once per
  cutoff crossed; this is linear in the number of worked days regardless of history length.
- **The balance is never materialized in the database.** A cached value would need
  recomputation after every cross-device event-log merge, and those merges happen at
  arbitrary times — recomputing on read from `allEntriesProvider` + `appSettingsProvider`
  is simpler and always correct.
- **`BalanceCard` deliberately ignores the Reports tab's project and billable filters.**
  `workTimeBalanceProvider` reads `allEntriesProvider` directly, not the filtered/ranged
  `reportEntriesProvider`: "overtime, but only for project X" is not a meaningful number.
- **The empty state exists because a fresh install has all-zero targets.** `hasAnyTarget`
  returns false when every weekday target is `0` (the shipped default) — without it, every
  tracked minute would read as overtime for a brand-new user. `BalanceCard` shows a
  `ListTile` pointing at Settings instead of a number in that case.
- **Status is always icon + colour, never colour alone** (repo accessibility rule): the
  balance row pairs `Icons.trending_up`/`trending_down` with `colorScheme.primary`/`error`.
- `formatSignedDuration` (in `balance_card.dart`) always emits an explicit `+`/`-` sign —
  `"1:30"` alone is ambiguous between a surplus and a deficit. It is intentionally separate
  from the shared, signless `formatDuration`.

## Gotchas

- **Do not overlay `appDatabaseProvider` in a widget test that mounts anything watching
  both `appSettingsProvider` and `allEntriesProvider`.** That combination deadlocks
  `flutter_test`: drift's debounced stream-close leaves a pending timer, and `tearDown`'s
  `db.close()` then waits forever. Override `appSettingsProvider` and `allEntriesProvider`
  directly with `Stream.value(...)` fixtures instead (see `balance_card_test.dart` and
  `reports_screen_test.dart`, which needed the same fix once it started mounting
  `BalanceCard`). This is the same class of trap documented for `SyncedWrites`' real file
  I/O in `balance_rule_editor_test.dart`.
- Providers whose type touches drift-generated row classes (`workTimeBalanceProvider`,
  `appSettingsProvider`, `allEntriesProvider`) are plain Riverpod providers, never
  `@riverpod` codegen — mixing riverpod_generator with drift's generator in the same
  build_runner pass trips `rrousselGit/riverpod#4323`.
- `_cutoffInYear` clamps the configured day to the target month's length (a 29 February
  rule becomes 28 February in a non-leap year) rather than letting `DateTime` roll the
  date into the next month.

## Out of scope (phase 1)

- Absence tracking: `dayBalances` only counts days with at least one finished entry: while
  `absenceTrackingEnabled` is always off, a day off cannot be recorded, so counting empty
  work days would manufacture a deficit. A later phase makes this conditional on that flag.
