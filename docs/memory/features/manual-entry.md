# Manual Entry (QuickAddBar + ManualEntryDialog)

## Entities

No dedicated entity — writes go through the existing `TimeEntry`/`SyncedWrites.createManualEntry`/`.updateEntry`. This feature is UI-only.

## Architecture

- `QuickAddBar` (`lib/features/entries/quick_add_bar.dart`), pinned to the Timer tab, is the primary entry point: description, project, Jira ticket, duration chips, and inline start/end date+time buttons, all in one row (`[start-date][start-time] – [end-date][end-time] [submit]`).
- `ManualEntryDialog` (`lib/features/entries/manual_entry_dialog.dart`) is now edit-only, reached by tapping a row in `EntriesList` — `showManualEntryDialog` no longer takes `initialDescription`/`initialProjectId` (QuickAddBar used to open it as a "more options" escape hatch for picking a date; that's gone now that date is inline). Its date/time controls are two labeled `Row`s (`Start: [date] [time]`, `Ende: [date] [time]`) instead of the single-tap `ListTile`s it used to have.
- Both widgets have their own `_pickDate`/`_pickTime` pair rather than a shared helper — `QuickAddBar`'s version threads through its `_rangeTouched`/`_displayStartAt`/`_displayEndAt` computed-getter model (a manual entry that hasn't been touched yet tracks "now" live); `ManualEntryDialog`'s version is plain fields, no getters. Don't try to unify them without re-deriving why the getter dance exists in one and not the other.

## Gotchas

- **`showDatePicker`/`showTimePicker` combine logic must preserve the *other* field.** `_pickDate` must build its result from the *picked date* + the *already-set hour/minute*; `_pickTime` must build its result from the *already-set year/month/day* + the *picked time*. Getting this backwards (e.g. `_pickTime` defaulting to `DateTime.now()`'s date) is exactly the bug this feature fixed — it silently discards whatever date the user already picked the next time they touch the time field. Any new date/time picker in this app should follow the same pattern.
- **A widget test that only confirms a picker's pre-filled default doesn't prove anything.** `showDatePicker`'s `initialDate` defaults to "today" — a test that opens the picker and immediately taps "OK" is indistinguishable from a test that never opened the picker at all, and won't catch a regression where the picked value is silently discarded. This bit us twice in the same PR (once in `QuickAddBar`'s tests, then again almost identically in the final whole-branch review for a different test in the same file) before landing on the fix: navigate the actual calendar grid to a day that isn't today (`find.descendant(of: find.byType(DatePickerDialog), matching: find.text('$targetDay'))`, where `targetDay = now.day > 1 ? now.day - 1 : now.day + 1` to stay on the same calendar page) before confirming.
- **End-before-start validation constrains which field is safe to test-shift.** `QuickAddBar._submit()` (and `ManualEntryDialog._save()`) silently refuse to write (snackbar, no DB row) if the computed range has `endAt` before `startAt`. A test that moves the *end* date backward (or the *start* date forward) without also moving the other side will hit this guard and never reach the database — the failure looks like "nothing got written," not an assertion mismatch. When picking a non-today day in a test, move the start date backward on non-1st-of-month days, or the end date forward specifically on the 1st (when `now.day - 1` would roll into the previous month and the "safe backward" trick doesn't apply the same way).
- `Row(children: [Expanded(label), TextButton(date), TextButton(time)])` in `ManualEntryDialog` can overflow under a long date format + verbose time format + narrow window — mitigated with `Flexible`/`Wrap` around the button pair, but only verified pixel-identical to the old layout under the default `iso`/`24h` settings. Not re-verified against `DateFormatStyle.long` or 12h-with-seconds; check visually if that combination becomes common.

## Out of scope (intentionally)

- Smart "Today"/"Yesterday" labels on the date buttons — plain `formatDate` output only.
- Live/inline end-before-start validation before submit — the existing submit-time snackbar is unchanged.
- Any change to `EntriesList`.
