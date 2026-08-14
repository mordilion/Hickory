# Manual Entry Date Rework — Design

Date: 2026-08-14
Status: Approved for planning

## 1. Goal & Scope

`QuickAddBar` (the manual-entry card pinned to the Timer tab) already lets a user
pick start/end **time** inline via two tappable buttons (`_pickTime`, opens
`showTimePicker`). It has no **date** control at all — both start and end are
implicitly "now," and the only way to log an entry on a different day is the
"more" icon, which opens the full `ManualEntryDialog` (a much bigger modal) just
to reach a date field. This adds inline start/end date buttons directly to
`QuickAddBar`, matching the existing time buttons' interaction pattern, and
removes the now-redundant "more" icon and its full-dialog escape hatch.

`ManualEntryDialog` (still needed as the edit path for existing entries, reached
by tapping a row in `EntriesList`) gets its combined date+time `ListTile`s
(`_pickDateTime`, sequential `showDatePicker` → `showTimePicker`) split into
separate date and time controls too, for consistency with `QuickAddBar`.

End-before-start validation already exists in both `QuickAddBar._submit()` and
`ManualEntryDialog._save()` (a snackbar with `entriesEndBeforeStartError`) —
no scope here, already correct.

Out of scope: any change to `EntriesList`, the duration chips, project/Jira
fields, or the delete flow.

## 2. Bug fix required for this to work: `_pickTime` discards the current date

`QuickAddBar._pickTime` and `ManualEntryDialog._pickDateTime`'s time step both
combine the picked `TimeOfDay` with **today's date**
(`DateTime(now.year, now.month, now.day, time.hour, time.minute)`), discarding
whatever date was already set on that side. This is invisible today because
neither screen has a way to set a date other than today in the first place —
once a date picker exists, picking a date and then adjusting the time would
silently snap the date back to today. Both new `_pickTime` implementations (and
`ManualEntryDialog`'s, since it's being split the same way) must combine the
picked time with the **existing** date instead:
`DateTime(initial.year, initial.month, initial.day, time.hour, time.minute)`,
where `initial` is the current `_startAt`/`_endAt` (or `_displayStartAt`/
`_displayEndAt` in `QuickAddBar`) for that side.

## 3. `QuickAddBar` (`lib/features/entries/quick_add_bar.dart`)

### New method

```dart
Future<void> _pickDate({required bool isStart}) async {
  final initial = isStart ? _displayStartAt : _displayEndAt;
  final date = await showDatePicker(
    context: context,
    initialDate: initial,
    firstDate: DateTime(2020),
    lastDate: DateTime.now().add(const Duration(days: 1)),
  );
  if (date == null || !mounted) return;
  final combined = DateTime(date.year, date.month, date.day, initial.hour, initial.minute);
  final freshStart = _displayStartAt;
  final freshEnd = _displayEndAt;
  setState(() {
    _startAt = isStart ? combined : freshStart;
    _endAt = isStart ? freshEnd : combined;
    _rangeTouched = true;
  });
}
```

Mirrors `_pickTime`'s existing shape exactly (same `freshStart`/`freshEnd`
snapshot-before-setState pattern, since `_displayStartAt`/`_displayEndAt` are
computed getters that would otherwise re-evaluate against a half-updated
`_rangeTouched` mid-`setState`).

### `_pickTime`, corrected per §2

```dart
Future<void> _pickTime({required bool isStart}) async {
  final initial = isStart ? _displayStartAt : _displayEndAt;
  final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(initial));
  if (time == null || !mounted) return;
  final combined = DateTime(initial.year, initial.month, initial.day, time.hour, time.minute);
  final freshStart = _displayStartAt;
  final freshEnd = _displayEndAt;
  setState(() {
    _startAt = isStart ? combined : freshStart;
    _endAt = isStart ? freshEnd : combined;
    _rangeTouched = true;
  });
}
```

(Only change from today: `DateTime(now.year, now.month, now.day, ...)` →
`DateTime(initial.year, initial.month, initial.day, ...)`, and `now` itself is
no longer needed in this method.)

### Layout — confirmed via visual brainstorm, Option A

Replace the current last `Wrap` (time buttons + more icon + submit) with:

```dart
Wrap(
  spacing: 8,
  runSpacing: 8,
  crossAxisAlignment: WrapCrossAlignment.center,
  children: [
    TextButton(
      onPressed: () => _pickDate(isStart: true),
      child: Text(formatDate(_displayStartAt, dateStyle, Localizations.localeOf(context).languageCode)),
    ),
    TextButton(
      onPressed: () => _pickTime(isStart: true),
      child: Text(formatTime(_displayStartAt, timeStyle)),
    ),
    const Text('–'),
    TextButton(
      onPressed: () => _pickDate(isStart: false),
      child: Text(formatDate(_displayEndAt, dateStyle, Localizations.localeOf(context).languageCode)),
    ),
    TextButton(
      onPressed: () => _pickTime(isStart: false),
      child: Text(formatTime(_displayEndAt, timeStyle)),
    ),
    IconButton.filled(
      tooltip: l10n.quickAddSubmitTooltip,
      onPressed: _submit,
      icon: const Icon(Icons.add),
    ),
  ],
),
```

`dateStyle` comes from `settings.dateStyle` (already read in `build()` for
`timeStyle`; add the corresponding read for date, same shape as
`ManualEntryDialog.build()` already does).

### Removed

- `_openFullDialog()` method.
- The `IconButton` with `Icons.calendar_month_outlined` / tooltip
  `quickAddMoreTooltip`.
- The `import '../projects/project_form_dialog.dart';`... no — that import
  stays (used by the new-project `IconButton`). Only
  `import 'manual_entry_dialog.dart';` is removed (no longer referenced once
  `_openFullDialog` is gone).

## 4. `ManualEntryDialog` (`lib/features/entries/manual_entry_dialog.dart`)

### Replace `_pickDateTime` with two methods

```dart
Future<void> _pickDate({required bool isStart}) async {
  final initial = isStart ? _startAt : _endAt;
  final date = await showDatePicker(
    context: context,
    initialDate: initial,
    firstDate: DateTime(2020),
    lastDate: DateTime.now().add(const Duration(days: 1)),
  );
  if (date == null || !mounted) return;
  setState(() {
    final combined = DateTime(date.year, date.month, date.day, initial.hour, initial.minute);
    if (isStart) {
      _startAt = combined;
    } else {
      _endAt = combined;
    }
  });
}

Future<void> _pickTime({required bool isStart}) async {
  final initial = isStart ? _startAt : _endAt;
  final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(initial));
  if (time == null || !mounted) return;
  setState(() {
    final combined = DateTime(initial.year, initial.month, initial.day, time.hour, time.minute);
    if (isStart) {
      _startAt = combined;
    } else {
      _endAt = combined;
    }
  });
}
```

No `freshStart`/`freshEnd` snapshot dance needed here — unlike `QuickAddBar`,
`_startAt`/`_endAt` are plain fields with no computed-getter layer.

### Replace the two `ListTile`s with two Rows

```dart
Row(
  children: [
    Expanded(child: Text(l10n.entriesStartLabel)),
    TextButton(
      onPressed: () => _pickDate(isStart: true),
      child: Text(formatDate(_startAt, dateStyle, Localizations.localeOf(context).languageCode)),
    ),
    TextButton(
      onPressed: () => _pickTime(isStart: true),
      child: Text(formatTime(_startAt, timeStyle)),
    ),
  ],
),
Row(
  children: [
    Expanded(child: Text(l10n.entriesEndLabel)),
    TextButton(
      onPressed: () => _pickDate(isStart: false),
      child: Text(formatDate(_endAt, dateStyle, Localizations.localeOf(context).languageCode)),
    ),
    TextButton(
      onPressed: () => _pickTime(isStart: false),
      child: Text(formatTime(_endAt, timeStyle)),
    ),
  ],
),
```

(Existing `ListTile`s used `contentPadding: EdgeInsets.zero` with the label as
`title` and the combined date+time string as `subtitle`; a `Row` with the label
in an `Expanded` on the left and two `TextButton`s on the right reproduces the
same "label left, value right" reading order without a single shared tap
target.)

### `showManualEntryDialog` signature

Remove `initialDescription`/`initialProjectId` — after §3 removes
`QuickAddBar`'s only call site that passes them, `entries_list.dart`'s
`showManualEntryDialog(context, ref, existing: entry)` is the sole remaining
caller and never passes them; keeping unused parameters would be dead code.

```dart
Future<void> showManualEntryDialog(BuildContext context, WidgetRef ref, {TimeEntry? existing})
```

`_ManualEntryDialog`'s constructor and `initState` shrink accordingly (drop the
two fields, `_descriptionController`'s initializer becomes
`existing?.description ?? ''`).

## 5. i18n cleanup

`quickAddMoreTooltip` becomes unused once the "more" icon is removed — delete
it from all 6 locale files (`app_de.arb` is the template; delete from all six
in the same change so `arb_completeness_test.dart` doesn't need every locale
touched separately, they're just each losing the same key). No new l10n keys
needed: date/time button labels reuse `formatDate`/`formatTime` output
(already dynamic, not translated strings), and `entriesStartLabel`/
`entriesEndLabel` already exist and are reused as-is in `ManualEntryDialog`.

## 6. Testing

- `test/features/entries/quick_add_bar_test.dart`:
  - Remove `'tapping the more icon opens the full dialog prefilled with the
    current description'` (the icon no longer exists).
  - New: tapping the start-date button opens a date picker; selecting a date
    updates the displayed start-date button text and preserves the previously
    set time (regression test for §2 — pick a time first via the existing time
    button, then pick a date, assert the time button's text is unchanged).
  - New: tapping the end-date button behaves the same for the end side.
  - New: submitting after picking a date writes a `TimeEntry` whose
    `startAt`/`endAt` reflect the picked date (not just today), via the same
    `pumpUntilTrue`-on-DB-row pattern the existing submit tests already use.
  - Update `makeApp`'s `AppSettingsRow` / any date-format expectations if the
    default `dateFormat: 'iso'` produces a specific expected string worth
    asserting on directly (`yyyy-MM-dd`).
- `test/features/entries/manual_entry_dialog_test.dart`: existing tests
  (delete/cancel-delete) don't touch date/time controls, so they're unaffected
  by the `ListTile` → `Row` change — confirm they still pass. New: tapping the
  start-date `TextButton` (find by the formatted date text, e.g. via
  `find.byType(TextButton)` at a known index, or by locating within the Start
  `Row`) opens a date picker; picking a date updates `_startAt`'s date and
  preserves its time (same §2 regression shape as `QuickAddBar`'s test); same
  for the end side.
- `flutter test test/l10n/arb_completeness_test.dart` after the key removal —
  must still pass (parity is about matching keys across locales, not about a
  specific key existing).

## 7. Out of Scope

Smart "Today"/"Yesterday" labels on the date buttons (plain `formatDate`
output only, matching the user's configured date format style — no new
UI convenience beyond what was asked), live/inline validation before submit
(the existing submit-time snackbar check is unchanged and sufficient), any
change to how `EntriesList` displays entries.
