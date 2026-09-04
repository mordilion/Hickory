# Absences

## Entities

- `AbsenceType` (`lib/data/drift/tables/absence_types_table.dart`): a user-defined kind of
  absence — vacation, sickness, a public holiday, unpaid leave. `id`, `name`, `paid`,
  `sortOrder` (display order, ties broken by name), `deviceId`, `createdAt`, `updatedAt`.
  No employment-law categories are built in — same reasoning that keeps labour rules out
  of `BreakRuleTiers`: Hickory is used across countries and contracts, so the set of kinds
  has to be whatever the user's own contract calls them.
- `Absence` (`lib/data/drift/tables/absences_table.dart`): one day of absence. `id`, `date`
  (local midnight, the same key `totalsByDay` groups worked time by), `absenceTypeId`,
  `portion` (`fullDay` | `halfDay` | `range`, stored as text rather than a drift enum so an
  older peer ingesting an unknown value reads a harmless string instead of failing to
  decode the row), `startAt`/`endAt` (UTC, set only for `range`), `note`, `deviceId`,
  `createdAt`, `updatedAt`. Neither table carries a foreign key — like every synced table
  in this codebase, a row must survive a peer applying events out of order.
- `AbsenceTypesDao` / `AbsencesDao` (`lib/data/drift/daos/`): CRUD plus
  `AbsencesDao.countByType(id)`, the one query the deletion guard below depends on.
- `absenceTypesProvider`, `absenceTypesByIdProvider`, `absencesProvider`
  (`lib/core/di/absence_providers.dart`): plain (non-`@riverpod`) providers, for the same
  reason as `appSettingsProvider` and `workTimeBalanceProvider` — mixing riverpod_generator
  with drift's generator in one build_runner pass trips rrousselGit/riverpod#4323.
  `absenceTypesByIdProvider` derives its map from `absenceTypesByIdProvider`'s `.value`,
  defaulting to `{}` while types are still loading; an absence whose type does not resolve
  contributes nothing rather than being guessed at (see below).
- `AppSettingsRow.absenceTrackingEnabled`: the single global switch. Off by default.

## Architecture

- `lib/features/absences/absence_bar.dart` (`AbsenceBar`): the third way to record time on
  the main screen, beside the timer and a manual entry. `lib/features/absences/absence_days.dart`
  (`absenceDaysBetween`) turns a full/half-day date range into the list of calendar days
  that actually get a row — days whose weekday target is zero are skipped, because an
  absence on a day with no target would credit nothing and only leave a row to look at.
- `lib/features/settings/absence_types_editor.dart` (`AbsenceTypesEditor`): the global
  switch plus the user's list of types, shown by `absences_settings_screen.dart`.
- `lib/features/reports/balance_calculations.dart`: `absenceMinutes` scores one absence on
  its day; `dayBalances` folds absences into the per-day totals; both are pure, no Riverpod.
- `lib/features/reports/reports_providers.dart` (`workTimeBalanceProvider`): wires
  `absencesProvider` and `absenceTypesByIdProvider` into `dayBalances`, gated by
  `absenceTrackingEnabled` (see "The switch" below).
- `lib/features/entries/entries_list.dart` and its row widgets render an absence's portion
  label alongside ordinary entries, reading the same two providers.

## Decisions

- **Nothing is seeded automatically.** A default "Vacation" / "Sick leave" set created at
  database-creation time would have every device create its own copy, and those copies
  would then sync into a pile of duplicates — there is no natural row for two devices to
  agree is "the same" default type. The standard set is therefore an explicit action the
  user takes once, on one device, and it syncs like any other write from there.
- **An absence is one row per calendar day, never a span.** A fortnight of vacation
  entered once in the form becomes fourteen (or fewer, once free days are skipped) rows.
  This keeps the balance calculation a per-day lookup — `dayBalances` never has to ask
  "does this range absence cover this day" — and lets a single day in the middle of a
  vacation be removed on its own. The cost is that a bulk entry is several writes, which
  the write-through sync already handles like any other batch; it is not a new problem
  this feature introduces.
- **Full and half days store a portion, not a minute figure.** `absenceMinutes` derives
  the credited time from *that day's* target when the balance is computed, not from a
  number written down when the absence was recorded. An absence therefore stays correct
  if the weekday targets are edited afterwards — a full-day vacation booked against an
  eight-hour Monday still reads as a full day if Monday's target later changes to six
  hours. `range` is the one exception: its length is its own (a two-hour doctor's
  appointment does not depend on the day's target at all), so it is the only portion that
  carries `startAt`/`endAt`.
- **A range subtracts its overlap with tracked work; full and half days do not.** A range
  absence and a tracked entry can genuinely double-book the same clock minutes (a
  doctor's appointment logged as both), so `_overlapMinutes` clips the overlap out before
  crediting the range. A full or half day is different by construction — it already
  covers the whole day (or half of it) regardless of anything tracked — and someone who
  chooses to also work on a vacation day should see that work as a plus on top, not have
  it silently cancelled against the absence credit. Paid credit is still capped at the
  day's effective target, so absence can bring a day to neutral but never manufacture
  overtime on its own.
- **Deleting a type in use is refused in the application layer, not the database.**
  `AbsencesDao.countByType` is checked before `SyncedWrites.deleteAbsenceType`, and the
  editor shows the count rather than a bare "cannot delete." A database-level foreign key
  would do this for a single device, but the synced tables carry none by design — a row
  written by one peer must decode even if another peer's ordering of events would
  otherwise orphan it — so nothing below the UI would stop the delete from leaving
  absence rows pointing at a type that no longer exists. `absenceTypesByIdProvider`'s
  "unresolvable type contributes nothing" behavior is the calculation's own backstop for
  the case that slips through anyway (a delete that raced ahead of this check on another
  device, or an older peer that predates the guard).
- **The switch decides which days enter the balance, not just whether absences count.**
  With `absenceTrackingEnabled` off, `dayBalances` returns only days that carry at least
  one finished `TimeEntry`, exactly as before this feature existed — a day off cannot be
  recorded, so treating every empty day as a deficit would be wrong. With it on, every
  work day between the first known day and `through` is enumerated, entry or not,
  because a work day with neither a booking nor an absence is now genuinely a deficit —
  making that visible is the point of turning the feature on. `workTimeBalanceProvider`
  mirrors the same gate at the provider level: it only watches `absencesProvider` (and
  only lets a failure there propagate) while the switch is on, so a broken absences
  stream can never take down a balance that does not read absences in the first place.
  See `work-time-balance.md` for the balance side of this.

## Gotchas

- A widget test that mounts anything reading `workTimeBalanceProvider` (directly, or via
  `BalanceCard`/`ReportsScreen`) must override `absencesProvider` and
  `absenceTypesProvider` with `Stream.value(...)` fixtures, exactly like
  `appSettingsProvider`/`allEntriesProvider` already have to be — `workTimeBalanceProvider`
  now watches both, and leaving them live routes through the real `appDatabaseProvider`
  and hits the same drift-stream-plus-`flutter_test`-teardown deadlock documented in
  `work-time-balance.md`'s gotchas. `reports_screen_test.dart` needed this once
  `workTimeBalanceProvider` started reading absences, the same way `entries_list_test.dart`
  needed it once `EntriesList` started rendering them.
- Any database read inside a widget test in this feature uses a one-shot query, never a
  DAO watch stream (`AbsencesDao.watchAllAbsences`, `absenceTypesProvider`'s underlying
  stream) awaited inside `tester.runAsync` — that combination deadlocks `flutter_test`
  here regardless of drift being involved elsewhere in the same test.
