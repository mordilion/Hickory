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
  incomplete selection local and never persists it — `SyncedWrites` only ever sees a
  complete rule. Complete means: any mode other than `none` has **both** a cutoff day and
  a cutoff month, and `carryOver` additionally has at least one bound. Nothing is
  defaulted; a cutoff the user never picked would reset or clamp the balance on a date of
  the app's choosing.
- `lib/features/settings/settings_editor_support.dart`: shared by both editors above.
  `SettingsWriteGuard` queues writes to the singleton settings row (never drops them),
  turns a failure into a SnackBar and reports success as a `bool`; `CommitOnFocusLoss` is
  what makes the text fields commit without an Enter key, and `setTextPreservingCaret` is
  how a stored value is pushed into an open field. The queue is per State, so it
  serialises one editor's writes, not two editors at once — enough only because each
  editor is its own sub-page.
- `lib/features/reports/reports_providers.dart`'s `workTimeBalanceProvider` and
  `lib/features/reports/balance_card.dart`'s `BalanceCard`: the Reports-tab display.

## Decisions

- **A correction is a dated fact, so `BalanceAdjustments` has no update path.** Fixing a
  wrong one is a delete plus a new row, which keeps the event log a truthful account of
  what the user actually did — and saves an update case in the ingestor that nothing
  would emit.
- **The cutoff takes effect at the start of the date it names, for work and corrections
  alike.** Spec §3 says corrections land "before that date's cutoff is evaluated", which
  taken literally would put a correction dated on the cutoff on the far side of the line
  from that same day's work — a payout split from the hours it settles. `runningBalance`
  merges days and corrections into one ordered ledger and applies a cutoff when crossing
  it, so both belong to the period that begins there. Configure the cutoff as the first
  day of the new period (1 January, not 31 December), which is how the settings screen
  words it.
- **The range tiles follow the report's range but none of its filters.** Same reason the
  running balance ignores them: "overtime, but only for project X" is not a number. The
  block says so whenever a filter is active.
- **Money follows the report's filters; the balance, trend and quality blocks do not.**
  Revenue for one project or one client is a real figure, where "overtime, but only for
  project X" is not and a target line drawn over a filtered subset would compare one
  project's hours against a whole week's target. Spec §6 draws the line in the same place.
- **Currencies are never summed.** `moneyFigures` returns cents per currency, and a client
  billed in two appears once per currency: adding them would mean picking an exchange
  rate, which the app has no basis for choosing and no place to store.
- **The trend switches to weekly bars past ~62 days** (`granularityFor`), and draws only
  from the first day the data covers to today, clamped into the range. The "all" preset
  spans 2000–2100, so enumerating the range itself would be thirty thousand empty bars;
  stopping at today keeps the rest of a running month from being drawn as zeroes that have
  not happened yet, while a forgotten week inside the span still reads as a gap.
- **Every trend bar is a `Semantics` node carrying its date and figures.** The hover
  tooltip §6.2 asks for has no keyboard or screen-reader equivalent, so the labels are the
  accessible path, not decoration — and the only thing a widget test can assert on, since
  a `CustomPainter`'s output is unreadable from a test.
- **A figure with no meaning shows a dash, not a zero.** An average over a range without
  a single work day, or figures that have not arrived yet — a zero there reads as a
  measurement that was taken.

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

- **An older peer's settings write wipes the seven targets, and nothing prevents it.**
  `materialize` picks one winning event by timestamp and applies its whole payload; a
  device still on schema 8 that writes any settings change after targets were configured
  elsewhere produces a winner with no target keys, the ingestor's backfill supplies `0`
  for all seven, and the upsert applies them. This is inherent to whole-row
  last-write-wins across a mixed-version fleet — `countPausedTimeAsBreak` has had the same
  exposure since v7 — and field-level merge is deliberately **not** built for it. Upgrade
  every device before configuring targets.
- **The `EntityTypes.appSettings` case in `sync_ingestor.dart` decodes with
  `toCompanion(false)`, unlike every other case.** With `true` a null nullable field
  becomes `Value.absent()` and `insertOnConflictUpdate` leaves that column unchanged, so
  clearing `carryOverMaxMinutes` would never reach the peer and the two devices would
  compute different balances. This is the first row on which `null` is semantically
  meaningful; do not "harmonize" it back to `true`.
- **Every settings field remembers what it last committed**, in a `_committed` field
  beside its controller, and compares against that rather than against the incoming
  `settings`/`widget` values. Enter and the focus loss that follows it are two commit
  paths over one value and neither the settings stream nor the parent's pending state has
  come back round in between, so without this both wrote — idempotent, but one sync-log
  event each for every peer to ingest. A write reported as failed puts the old figure
  back, or a value that failed to save could never be retried from that field.
- **Pushing text into a field goes through `setTextPreservingCaret`, never
  `controller.text =`.** The setter drops the selection even when the text is unchanged,
  so a field refreshed while the user is in it loses their place — most visibly when a
  work-day chip redistributes the weekly figure being typed.
- **The text fields in both settings editors are never disabled while a write is in
  flight** (only the chips, dropdowns and the mode toggle are). Disabling a focused field
  takes its focus away, and focus loss is exactly what commits it — tabbing from one day
  field to the next would break. `SettingsWriteGuard` queues concurrent writes instead.
- **A widget test that mounts `ReportsScreen` must override every provider the dashboard
  blocks read**, now `balanceAdjustmentsProvider`, `allClientsProvider`,
  `breakRuleTiersProvider`, `jiraWorklogsByEntryIdProvider` and
  `personioAttendancesByEntryIdProvider` on top of the older four. Each one left live
  watches a real drift stream from inside a widget, and the failure is not a missing
  value but "A Timer is still pending even after the widget tree was disposed" at
  teardown — which reads like a flake in an unrelated test.
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

## Absences

- **`dayBalances` counting only days with at least one finished entry is now conditional
  on `AppSettingsRow.absenceTrackingEnabled`, not a permanent rule.** With the switch off
  it behaves exactly as before absences existed: an empty day cannot be recorded, so
  counting it would manufacture a deficit. With it on, every work day up to `through` is
  enumerated whether or not it carries an entry, because an unrecorded, unexcused day is
  now a real deficit the feature exists to surface. `workTimeBalanceProvider` only reads
  `absencesProvider` (and only lets a failure in it reach the UI) while the switch is on,
  for the same reason. See `absences.md` for the recording side and the full reasoning.
