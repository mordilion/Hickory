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
  decode the row), `halfDayPart` (`morning` | `afternoon`, null on every other portion and
  on half days recorded before schema 12), `startAt`/`endAt` (UTC, set only for `range`), `note`, `deviceId`,
  `createdAt`, `updatedAt`. Neither table carries a foreign key — like every synced table
  in this codebase, a row must survive a peer applying events out of order.
- `AbsenceTypesDao` / `AbsencesDao` (`lib/data/drift/daos/`): CRUD plus
  `AbsencesDao.countByType(id)`, the one query the deletion guard below depends on.
- `absenceTypesProvider`, `absenceTypesByIdProvider`, `absencesProvider`
  (`lib/core/di/absence_providers.dart`): plain (non-`@riverpod`) providers, for the same
  reason as `appSettingsProvider` and `workTimeBalanceProvider` — mixing riverpod_generator
  with drift's generator in one build_runner pass trips rrousselGit/riverpod#4323.
  `absenceTypesByIdProvider` derives its map from `absenceTypesProvider`'s `.value`,
  defaulting to `{}` while types are still loading; an absence whose type does not resolve
  contributes nothing rather than being guessed at (see below).
- `AppSettingsRow.absenceTrackingEnabled`: the single global switch. Off by default.

## Architecture

- `lib/features/absences/absence_bar.dart` (`AbsenceBar`): the third way to record time on
  the main screen, beside the timer and a manual entry. It renders in the same
  `Card > Padding(16)` box as `_StartCard` and `QuickAddBar` — including its loading and
  "no type yet" states, so switching modes never changes the shape of the tab. The three
  modes are deliberately one shape down to the details: free text first, then the pickers
  as bare `TextButton`s in a centred `Wrap` with an en dash between the two ends, then a
  full-width `GradientPillButton`. Dates and times go through `formatDate`/`formatTime`
  with the stored `dateStyle`/`timeStyle`, never `DateFormat.yMd` or
  `TimeOfDay.format(context)` — those ignore the user's setting, so the same moment used
  to read differently depending on which mode wrote it. `AbsenceEditDialog` follows the
  same layout and shows the day as plain text, since it cannot move a row between days. `lib/features/absences/absence_days.dart`
  (`absenceDaysBetween`) turns a full/half-day date range into the list of calendar days
  that actually get a row — days whose weekday target is zero are skipped, because an
  absence on a day with no target would credit nothing and only leave a row to look at.
  `absenceSpanDays` does the same for a `range` absence, which carries a from/to date as
  well as a from/to time: the span is one continuous absence, so the first day runs from
  its clock time to midnight, the last from midnight to its clock time, and the days
  between are whole days. A span inside one day keeps both times (the appointment case).
  A skipped free day never moves the clipping onto another day — the clock times belong
  to the calendar days the user picked, not to the first and last row that gets written —
  and a span ending at midnight leaves that day out, since it covers none of it.
- `lib/features/settings/absence_types_editor.dart` (`AbsenceTypesEditor`): the global
  switch plus the user's list of types, shown by `absences_settings_screen.dart`. The
  "add standard types" button stays visible for the life of the list and skips every
  name (case-insensitively) already there, so it is safe to press twice and adding one
  type of your own does not shut you out of the standard set.
- `lib/features/absences/absence_edit_dialog.dart` (`AbsenceEditDialog`): pops with an
  `AbsenceEdit` record and writes nothing itself; `_editAbsence` in `entries_list.dart`
  owns the `SyncedWrites.updateAbsence` call, the same split the delete path uses.
  `lib/features/absences/absence_time_range.dart` (`isAbsenceRangeInOrder`) is shared by
  both forms: a range whose end is not after its start is refused rather than written as
  a row worth zero minutes.
- `lib/features/reports/balance_calculations.dart`: `absenceMinutes` scores one absence on
  its day; `dayBalances` folds absences into the per-day totals; both are pure, no Riverpod.
- `lib/features/reports/reports_providers.dart` (`workTimeBalanceProvider`): wires
  `absencesProvider` and `absenceTypesByIdProvider` into `dayBalances`, gated by
  `absenceTrackingEnabled` (see "The switch" below).
- `lib/features/entries/entries_list.dart` and its row widgets render an absence's portion
  label alongside ordinary entries, reading the same two providers. The days holding
  absences are passed to `buildEntryTree`/`groupEntriesByDay` as `extraDays`, so a day
  whose only record is an absence still gets a node (and a year/month/week above it) —
  without that the row, and with it the only delete affordance an absence has, would be
  unreachable. For the same reason the empty state needs both entries *and* absences to
  be missing.

## Decisions

- **Nothing is seeded automatically.** A default "Vacation" / "Sick leave" set created at
  database-creation time would have every device create its own copy, and those copies
  would then sync into a pile of duplicates — there is no natural row for two devices to
  agree is "the same" default type. The standard set is therefore an explicit action the
  user takes once, on one device, and it syncs like any other write from there.
- **A range absence spans days like a manual entry does.** The two clock times only have
  to be in order within a single day; across days, away from Monday 14:00 until Wednesday
  09:00 is ordinary, so `_pickTime`'s clamp and the invalid-range refusal both apply only
  while `_from` and `_to` are the same calendar day. The alternative reading — the same
  clock window repeated on every day of the span — was considered and rejected: the form
  shows the same `date time – date time` line the manual entry does, and it has to mean
  the same thing there.
- **An absence is one row per calendar day, never a span.** A fortnight of vacation
  entered once in the form becomes fourteen (or fewer, once free days are skipped) rows.
  This keeps the balance calculation a per-day lookup — `dayBalances` never has to ask
  "does this range absence cover this day" — and lets a single day in the middle of a
  vacation be removed on its own. The cost is that a bulk entry is several writes, which
  the write-through sync already handles like any other batch; it is not a new problem
  this feature introduces.
- **Which half of a half day is its own nullable column, not two more portion values.**
  A peer that predates it reads `portion: halfDay` and still credits half the target,
  where a `halfDayMorning` portion would have hit `absenceMinutes`'s unknown-portion
  branch and scored zero. It is informational — half a day is credited either way — which
  is also why it stays null rather than defaulting on old rows.
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
- **Deleting a type in use is refused inside `SyncedWrites`, not the database and not the
  screen.** `deleteAbsenceType` counts the referencing rows itself and throws
  `AbsenceTypeInUseException(count)`; the editor only turns that into its message. This
  is the same shape `deleteProject` and `deleteClient` have always had — a guard living
  in a screen is one any other caller walks around. A database-level foreign key would do
  this for a single device, but the synced tables carry none by design — a row
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
  mirrors the same gate at the provider level: it watches `absencesProvider`
  unconditionally — a provider cannot decide what to watch after reading the settings —
  but only *waits for* it and only lets a failure there propagate while the switch is on,
  so a broken absences stream can never take down a balance that does not read absences
  in the first place. See `work-time-balance.md` for the balance side of this.

## Spec deviations

Against `docs/superpowers/specs/2026-09-02-worktime-balance-dashboard-design.md`:

- **An absence's day cannot be edited**, only its type, extent, time range and note
  (`lib/features/absences/absence_edit_dialog.dart`, reached from the row's edit button).
  `date` is the key both `dayBalances` and the entries tree group by, so moving a row
  between days is recording a different absence; the correction path exists for the
  fields a person actually mistypes.
- **The paid flag lives in the type's edit dialog, not on each list row**, where §4
  describes "add, rename, reorder, delete and a paid toggle each". Paid is a property of
  the *type*, changed roughly once when the type is created, and an always-live switch on
  every row invites a mis-tap that silently re-scores every absence of that kind across
  the whole history. The dialog keeps it beside the name it belongs to.
- **The schema landed across versions 10, 11 and 12**, where §2 anticipated a single 10
  for "the tables added in phases 2 and 3". `absenceTypes` and `absences` shipped in separate
  steps, each independently demonstrable, and a migration step is cheap; folding two
  `createTable` calls into one version afterwards would have meant rewriting a migration
  already applied on the developer's own database.

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
