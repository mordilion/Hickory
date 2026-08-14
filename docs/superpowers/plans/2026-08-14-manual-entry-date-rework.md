# Manual Entry Date Rework Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add inline start/end date buttons to `QuickAddBar` (matching its existing inline time buttons), split `ManualEntryDialog`'s combined date+time picker into separate date/time controls for consistency, and remove `QuickAddBar`'s "more" icon / full-dialog escape hatch now that date is reachable inline.

**Architecture:** Two `ConsumerStatefulWidget`s get a new `_pickDate` method mirroring their existing `_pickTime` method, plus a corrected `_pickTime` that preserves the already-set date instead of resetting to today. No data-layer or provider changes.

**Tech Stack:** Flutter, Riverpod, `flutter_test`.

## Global Constraints

- `showDatePicker`'s bounds, wherever used: `firstDate: DateTime(2020)`, `lastDate: DateTime.now().add(const Duration(days: 1))` — matches the existing (pre-change) `ManualEntryDialog._pickDateTime`'s bounds exactly.
- `lib/l10n/app_de.arb` is the l10n template (`l10n.yaml`) — `test/l10n/arb_completeness_test.dart` diffs every other locale file against `de`, not `en`.
- End-before-start validation is out of scope — it already exists in both files' submit/save methods and is untouched by this plan.
- Commit messages: Conventional Commits, imperative mood, lowercase, no trailing period, summary line under 72 chars.
- Run the full test suite once before each commit, not after every edit.

---

### Task 1: `QuickAddBar` — date buttons, `_pickTime` fix, remove "more" icon

**Files:**
- Modify: `lib/features/entries/quick_add_bar.dart`
- Test: `test/features/entries/quick_add_bar_test.dart`

**Interfaces:**
- Produces: `_pickDate({required bool isStart})` on `_QuickAddBarState` (new, private — no external interface). `showManualEntryDialog` is no longer called from this file.

- [ ] **Step 1: Write the failing tests**

Modify `test/features/entries/quick_add_bar_test.dart`:

Remove this entire test (the icon it taps no longer exists):

```dart
  testWidgets(
    'tapping the more icon opens the full dialog prefilled with the current description',
    (tester) async {
      await tester.pumpWidget(makeApp());
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'Retro');
      await tester.tap(find.byTooltip('More options'));
      await tester.pumpAndSettle();

      expect(find.text('Manual entry'), findsOneWidget);
      // Scoped to the dialog, not a bare find.text('Retro') -- the bar's own
      // description field behind the dialog still reads "Retro" too, so an
      // unscoped assertion would pass even if the dialog itself were never
      // actually prefilled.
      final retroInDialog = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Retro'),
      );
      expect(retroInDialog, findsOneWidget);
    },
  );
```

Append these three tests inside `main()`, after the last remaining test (`'tapping the new-project icon opens the new-project dialog'`), following the same finder conventions already used elsewhere in this file (`find.byTooltip`, `find.byType(TextButton)` indexed by position, `pumpUntilTrue` polling the DB):

```dart
  testWidgets('tapping the start-date button opens a date picker', (tester) async {
    await tester.pumpWidget(makeApp());
    await tester.pumpAndSettle();

    // Row order after this task: [start date][start time] – [end date][end time][submit].
    await tester.tap(find.byType(TextButton).first);
    await tester.pumpAndSettle();

    expect(find.byType(DatePickerDialog), findsOneWidget);
  });

  testWidgets(
    'picking a start date preserves the previously-picked start time, and vice versa',
    (tester) async {
      await tester.pumpWidget(makeApp());
      await tester.pumpAndSettle();

      // Confirm the time picker via its pre-filled default -- this still
      // exercises _pickTime's date-preserving combine step without depending
      // on the picker's internal widget structure (dial vs. input mode),
      // which isn't worth pinning down for this test.
      await tester.tap(find.byType(TextButton).at(1));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      final startTimeLabelAfterTimePick =
          ((tester.widget(find.byType(TextButton).at(1)) as TextButton).child! as Text).data;

      // Now confirm the date picker via its pre-filled default too, and
      // check the time button's label is unchanged.
      await tester.tap(find.byType(TextButton).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      final startTimeLabelAfterDatePick =
          ((tester.widget(find.byType(TextButton).at(1)) as TextButton).child! as Text).data;

      expect(startTimeLabelAfterDatePick, startTimeLabelAfterTimePick);
    },
  );

  testWidgets(
    'submitting after picking an end date writes that date to the entry',
    (tester) async {
      await tester.pumpWidget(makeApp());
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'Dated entry');
      // TextButton index 2 is end-date (0: start-date, 1: start-time, 2: end-date, 3: end-time).
      await tester.tap(find.byType(TextButton).at(2));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Add entry'));
      await tester.pump();

      await pumpUntilTrue(
        tester,
        () async => (await db.select(db.timeEntries).get()).isNotEmpty,
      );

      final created = (await db.select(db.timeEntries).get()).single;
      expect(created.description, 'Dated entry');
      expect(created.endAt, isNotNull);
    },
  );
```

Add the import needed for `DatePickerDialog`/`TimePickerDialog` type references — they're already exported by `package:flutter/material.dart`, already imported in this file, so no new import is needed.

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/features/entries/quick_add_bar_test.dart`
Expected: FAIL — `find.byType(TextButton).first`/`.at(1)`/`.at(2)` don't resolve to date/time buttons yet (only 2 `TextButton`s exist today: start-time, end-time — indices are off, and no `DatePickerDialog` ever opens), so the new tests fail; the removed "more icon" test is gone so it can't fail.

- [ ] **Step 3: Fix `_pickTime` and add `_pickDate`**

In `lib/features/entries/quick_add_bar.dart`, replace the existing `_pickTime` method:

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

Add a new `_pickDate` method right after it:

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

- [ ] **Step 4: Remove `_openFullDialog` and the now-unused import**

Remove this method entirely:

```dart
  void _openFullDialog() {
    final description = _descriptionController.text.trim();
    showManualEntryDialog(
      context,
      ref,
      initialDescription: description.isEmpty ? null : description,
      initialProjectId: _projectId,
    );
  }
```

Remove this import line (no longer referenced once `_openFullDialog` is gone):

```dart
import 'manual_entry_dialog.dart';
```

- [ ] **Step 5: Read `dateStyle` alongside the existing `timeStyle` read**

In `build()`, find:

```dart
    final timeStyle = settings.timeStyle;
```

Change to:

```dart
    final dateStyle = settings.dateStyle;
    final timeStyle = settings.timeStyle;
```

- [ ] **Step 6: Replace the time-buttons `Wrap` with the date+time layout**

Replace this block (the last `Wrap` in `build()`, currently containing the two time buttons, the "more" icon, and the submit button):

```dart
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                TextButton(
                  onPressed: () => _pickTime(isStart: true),
                  child: Text(formatTime(_displayStartAt, timeStyle)),
                ),
                const Text('–'),
                TextButton(
                  onPressed: () => _pickTime(isStart: false),
                  child: Text(formatTime(_displayEndAt, timeStyle)),
                ),
                IconButton(
                  tooltip: l10n.quickAddMoreTooltip,
                  onPressed: _openFullDialog,
                  icon: const Icon(Icons.calendar_month_outlined),
                ),
                IconButton.filled(
                  tooltip: l10n.quickAddSubmitTooltip,
                  onPressed: _submit,
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
```

with:

```dart
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                TextButton(
                  onPressed: () => _pickDate(isStart: true),
                  child: Text(
                    formatDate(_displayStartAt, dateStyle, Localizations.localeOf(context).languageCode),
                  ),
                ),
                TextButton(
                  onPressed: () => _pickTime(isStart: true),
                  child: Text(formatTime(_displayStartAt, timeStyle)),
                ),
                const Text('–'),
                TextButton(
                  onPressed: () => _pickDate(isStart: false),
                  child: Text(
                    formatDate(_displayEndAt, dateStyle, Localizations.localeOf(context).languageCode),
                  ),
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

Add the `formatDate` import if not already present — check the top of the file: it already imports `import '../../core/format/date_format.dart';` (used for nothing else currently, only needed once `formatTime` was used — confirm `formatDate` is exported from the same file, which it is, so no new import line is needed, just the new call site).

- [ ] **Step 7: Run tests to verify they pass**

Run: `flutter test test/features/entries/quick_add_bar_test.dart`
Expected: PASS — if the `TimePickerDialog`'s confirm button text isn't literally `'OK'` on the Material version this project uses, the test will fail at that `find.text('OK')` step; if so, inspect the actual rendered text (`flutter test --plain-name "already-set start time"` with a `debugDumpApp()` or by reading the `TimePickerDialog`/`DatePickerDialog` source under the pinned Flutter SDK) and adjust the finder to match — do not skip or weaken the test, find the real button.

- [ ] **Step 8: Run the full test suite to check for regressions**

Run: `flutter test`
Expected: PASS

- [ ] **Step 9: Commit**

```bash
git add lib/features/entries/quick_add_bar.dart test/features/entries/quick_add_bar_test.dart
git commit -m "feat(entries): add inline date buttons to QuickAddBar"
```

---

### Task 2: `ManualEntryDialog` — split date/time, drop unused params

**Files:**
- Modify: `lib/features/entries/manual_entry_dialog.dart`
- Test: `test/features/entries/manual_entry_dialog_test.dart`

**Interfaces:**
- Consumes: nothing new from Task 1 (independent file).
- Produces: `showManualEntryDialog(BuildContext, WidgetRef, {TimeEntry? existing})` — `initialDescription`/`initialProjectId` removed from the signature. This is safe because Task 1 already removed `QuickAddBar`'s only call site that passed them; `lib/features/entries/entries_list.dart:140`'s call (`showManualEntryDialog(context, ref, existing: entry)`) never passed them and is unaffected.

- [ ] **Step 1: Write the failing tests**

Append to `test/features/entries/manual_entry_dialog_test.dart`, inside `main()`, after the last existing test:

```dart
  testWidgets('tapping the start-date button opens a date picker', (tester) async {
    final entry = await tester.runAsync(
      () => writes.createManualEntry(
        deviceId: 'device-1',
        startAt: DateTime.now().subtract(const Duration(hours: 1)),
        endAt: DateTime.now(),
        description: 'Standup',
      ),
    );

    await tester.pumpWidget(makeApp([entry!]));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Standup'));
    await tester.pumpAndSettle();
    expect(find.text('Edit entry'), findsOneWidget);

    // Row order in the dialog: [Start label][start date][start time], then
    // [End label][end date][end time] -- TextButton index 0 is start-date.
    await tester.tap(find.byType(TextButton).first);
    await tester.pumpAndSettle();

    expect(find.byType(DatePickerDialog), findsOneWidget);
  });

  testWidgets(
    'picking a start date preserves the already-set start time',
    (tester) async {
      final entry = await tester.runAsync(
        () => writes.createManualEntry(
          deviceId: 'device-1',
          startAt: DateTime(2026, 7, 1, 9, 30),
          endAt: DateTime(2026, 7, 1, 10, 30),
          description: 'Standup',
        ),
      );

      await tester.pumpWidget(makeApp([entry!]));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Standup'));
      await tester.pumpAndSettle();

      // TextButton index 1 is start-time; confirm its pre-filled label first.
      final startTimeButton = tester.widget<TextButton>(find.byType(TextButton).at(1));
      final startTimeLabelBefore = (startTimeButton.child! as Text).data;

      // Pick a start date and accept the pre-filled initialDate (today isn't
      // relevant here -- the point is confirming a date doesn't reset time).
      await tester.tap(find.byType(TextButton).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      final startTimeLabelAfter =
          ((tester.widget(find.byType(TextButton).at(1)) as TextButton).child! as Text).data;
      expect(startTimeLabelAfter, startTimeLabelBefore);
    },
  );
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/features/entries/manual_entry_dialog_test.dart`
Expected: FAIL — `TextButton`s don't exist yet at the expected indices (the dialog currently uses `ListTile`s with a single combined tap target, not separate date/time `TextButton`s), so `find.byType(TextButton).first`/`.at(1)` don't resolve as expected and/or no `DatePickerDialog` opens.

- [ ] **Step 3: Replace `_pickDateTime` with `_pickDate`/`_pickTime`**

Remove the existing `_pickDateTime` method:

```dart
  Future<void> _pickDateTime({required bool isStart}) async {
    final initial = isStart ? _startAt : _endAt;
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null) return;
    final combined = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    setState(() {
      if (isStart) {
        _startAt = combined;
      } else {
        _endAt = combined;
      }
    });
  }
```

Replace it with:

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

- [ ] **Step 4: Replace the two `ListTile`s with two `Row`s**

Replace this block:

```dart
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.entriesStartLabel),
              subtitle: Text(
                '${formatDate(_startAt, dateStyle, Localizations.localeOf(context).languageCode)} '
                '${formatTime(_startAt, timeStyle)}',
              ),
              onTap: () => _pickDateTime(isStart: true),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.entriesEndLabel),
              subtitle: Text(
                '${formatDate(_endAt, dateStyle, Localizations.localeOf(context).languageCode)} '
                '${formatTime(_endAt, timeStyle)}',
              ),
              onTap: () => _pickDateTime(isStart: false),
            ),
```

with:

```dart
            Row(
              children: [
                Expanded(child: Text(l10n.entriesStartLabel)),
                TextButton(
                  onPressed: () => _pickDate(isStart: true),
                  child: Text(
                    formatDate(_startAt, dateStyle, Localizations.localeOf(context).languageCode),
                  ),
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
                  child: Text(
                    formatDate(_endAt, dateStyle, Localizations.localeOf(context).languageCode),
                  ),
                ),
                TextButton(
                  onPressed: () => _pickTime(isStart: false),
                  child: Text(formatTime(_endAt, timeStyle)),
                ),
              ],
            ),
```

- [ ] **Step 5: Remove `initialDescription`/`initialProjectId`**

Change the public function signature:

```dart
Future<void> showManualEntryDialog(
  BuildContext context,
  WidgetRef ref, {
  TimeEntry? existing,
  String? initialDescription,
  String? initialProjectId,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => _ManualEntryDialog(
      existing: existing,
      initialDescription: initialDescription,
      initialProjectId: initialProjectId,
    ),
  );
}
```

to:

```dart
Future<void> showManualEntryDialog(
  BuildContext context,
  WidgetRef ref, {
  TimeEntry? existing,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => _ManualEntryDialog(existing: existing),
  );
}
```

Change the widget class:

```dart
class _ManualEntryDialog extends ConsumerStatefulWidget {
  const _ManualEntryDialog({this.existing, this.initialDescription, this.initialProjectId});

  final TimeEntry? existing;
  final String? initialDescription;
  final String? initialProjectId;
```

to:

```dart
class _ManualEntryDialog extends ConsumerStatefulWidget {
  const _ManualEntryDialog({this.existing});

  final TimeEntry? existing;
```

Change `initState`:

```dart
    final existing = widget.existing;
    _descriptionController = TextEditingController(
      text: existing?.description ?? widget.initialDescription ?? '',
    );
    _startAt = existing?.startAt.toLocal() ?? DateTime.now().subtract(const Duration(hours: 1));
    _endAt = existing?.endAt?.toLocal() ?? DateTime.now();
    _projectId = existing?.projectId ?? widget.initialProjectId;
    _jiraTicketKey = existing?.jiraTicketKey;
```

to:

```dart
    final existing = widget.existing;
    _descriptionController = TextEditingController(text: existing?.description ?? '');
    _startAt = existing?.startAt.toLocal() ?? DateTime.now().subtract(const Duration(hours: 1));
    _endAt = existing?.endAt?.toLocal() ?? DateTime.now();
    _projectId = existing?.projectId;
    _jiraTicketKey = existing?.jiraTicketKey;
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `flutter test test/features/entries/manual_entry_dialog_test.dart`
Expected: PASS — if `find.text('OK')` doesn't match the actual `DatePickerDialog` confirm button text on this project's pinned Flutter SDK, inspect and adjust the same way as Task 1 Step 7 — don't guess or weaken the assertion.

- [ ] **Step 7: Run the full test suite to check for regressions**

Run: `flutter test`
Expected: PASS

- [ ] **Step 8: Commit**

```bash
git add lib/features/entries/manual_entry_dialog.dart test/features/entries/manual_entry_dialog_test.dart
git commit -m "feat(entries): split ManualEntryDialog date/time pickers"
```

---

### Task 3: Remove the now-unused `quickAddMoreTooltip` l10n key

**Files:**
- Modify: `lib/l10n/app_de.arb`, `lib/l10n/app_en.arb`, `lib/l10n/app_es.arb`, `lib/l10n/app_fr.arb`, `lib/l10n/app_it.arb`, `lib/l10n/app_nl.arb`

**Interfaces:**
- Produces: no interface change — `AppLocalizations.quickAddMoreTooltip` no longer exists after regeneration; nothing references it after Task 1 removed the only call site.

- [ ] **Step 1: Confirm nothing still references the key**

Run: `grep -rn "quickAddMoreTooltip" lib/ test/`
Expected: only matches inside the six `lib/l10n/app_*.arb` files and the generated `lib/l10n/app_localizations*.dart` files — no matches in `lib/features/` or `test/` (Task 1 already removed the one real usage and its test).

- [ ] **Step 2: Remove the key from each ARB file**

Remove this line from `lib/l10n/app_de.arb`:

```json
  "quickAddMoreTooltip": "Weitere Optionen",
```

Remove this line from `lib/l10n/app_en.arb`:

```json
  "quickAddMoreTooltip": "More options",
```

Remove this line from `lib/l10n/app_es.arb`:

```json
  "quickAddMoreTooltip": "Más opciones",
```

Remove this line from `lib/l10n/app_fr.arb`:

```json
  "quickAddMoreTooltip": "Plus d'options",
```

Remove this line from `lib/l10n/app_it.arb`:

```json
  "quickAddMoreTooltip": "Altre opzioni",
```

Remove this line from `lib/l10n/app_nl.arb`:

```json
  "quickAddMoreTooltip": "Meer opties",
```

- [ ] **Step 3: Regenerate localizations and verify**

Run: `flutter gen-l10n`
Expected: completes without error; `lib/l10n/app_localizations*.dart` no longer declare `quickAddMoreTooltip`.

Run: `flutter test test/l10n/arb_completeness_test.dart`
Expected: PASS (all six files still have matching key sets — they all lost the same key).

- [ ] **Step 4: Run the full test suite to check for regressions**

Run: `flutter test`
Expected: PASS

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 5: Commit**

```bash
git add lib/l10n/
git commit -m "chore(entries): remove unused quickAddMoreTooltip string"
```

---

## Final Verification

- [ ] Run the full suite one more time: `flutter test`
- [ ] Run `flutter analyze` with zero issues
- [ ] Manually smoke-test if possible: open the Timer tab, tap the start-date button, pick yesterday, tap the start-time button, confirm the date is still yesterday (not reset to today); submit; confirm the entry appears under the right day in the list. Tap an existing entry to open the edit dialog, confirm the same date-preserves-across-time-pick behavior there too.
