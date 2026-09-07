# Balance Block Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Finish the Reports tab's balance block — the three tiles that are still
missing beside the existing one, and the dated manual corrections that keep the
number honest.

**Architecture:** The arithmetic stays in `balance_calculations.dart`, pure and
Riverpod-free, and gains range figures plus adjustments. `BalanceAdjustments`
becomes the fourth synced entity of this feature, following the same per-row
event-log pattern as `Absences`. `BalanceCard` grows from one tile into a block
of four, reading one new provider that computes all four figures in a single
pass.

**Tech Stack:** Flutter, Riverpod (plain providers only — riverpod_generator
must not touch drift types, see rrousselGit/riverpod#4323), Drift, flutter_gen-l10n
with German as the template ARB.

**Spec:** `docs/superpowers/specs/2026-09-02-worktime-balance-dashboard-design.md`
(§2 `BalanceAdjustments`, §3 reported figures, §6.1 the four tiles)

## Scope

Phase 3 of the spec covers four independent blocks. This plan covers **only the
balance block**: §6.1's four tiles and the `BalanceAdjustments` behind them. The
trend chart (§6.2), money and billability (§6.3) and tracking quality (§6.4) each
get their own plan, because each is demonstrable on its own and none depends on
the others.

## Global Constraints

- **Every new string goes into all six ARB files.** `test/l10n/arb_completeness_test.dart`
  fails the build otherwise. German (`app_de.arb`) is the template; counted strings
  use ICU plurals.
- **No `@riverpod` code generation.** Every provider in this feature is a plain
  `Provider`/`StreamProvider`.
- **The project and billable filters must not reach the balance.** Blocks 1, 2 and 4
  always compute over every entry in the range; the tiles carry a note while a
  filter is active (§6).
- **Widget tests never mount a live drift stream.** Override `appSettingsProvider`,
  `allEntriesProvider`, `absencesProvider`, `absenceTypesProvider` and the new
  `balanceAdjustmentsProvider` with `Stream.value(...)` fixtures; a real
  `appDatabaseProvider` behind any of them deadlocks `flutter_test` at teardown
  (see `docs/memory/features/work-time-balance.md`).
- **A widget test that mounts anything using `HickoryColors` needs `theme: AppTheme.light`.**
- **Test fixtures for `AppSettingsRow` come from `test/support/app_settings_fixture.dart`**,
  the only place under `test/` allowed to construct one.

---

### Task 1: Range figures in the calculation module

**Files:**
- Modify: `lib/features/reports/balance_calculations.dart`
- Test: `test/features/reports/balance_calculations_test.dart`

**Interfaces:**
- Consumes: `DayBalance`, `dayBalances(...)` (already there).
- Produces:
  ```dart
  class RangeFigures {
    const RangeFigures({
      required this.worked,
      required this.target,
      required this.absenceCredit,
      required this.workDays,
    });
    final Duration worked;
    final Duration target;
    final Duration absenceCredit;
    final int workDays;            // days with a target above zero
    Duration get balance => worked + absenceCredit - target;
    Duration get averagePerWorkDay; // Duration.zero when workDays == 0
    double get completion;          // worked+credit over target, 0 when target is zero
  }

  RangeFigures figuresForRange(List<DayBalance> balances, DateTimeRange range);
  ```
  `range.end` is **exclusive**, matching `rangeForPreset` in `reports_providers.dart`.

- [ ] **Step 1: Write the failing tests**

```dart
test('sums only the days inside the range, end exclusive', () {
  final balances = [
    DayBalance(day: DateTime(2026, 9, 7), worked: const Duration(hours: 9), target: const Duration(hours: 8)),
    DayBalance(day: DateTime(2026, 9, 8), worked: const Duration(hours: 7), target: const Duration(hours: 8)),
    DayBalance(day: DateTime(2026, 9, 9), worked: const Duration(hours: 8), target: const Duration(hours: 8)),
  ];

  final figures = figuresForRange(
    balances,
    DateTimeRange(start: DateTime(2026, 9, 7), end: DateTime(2026, 9, 9)),
  );

  expect(figures.worked, const Duration(hours: 16));
  expect(figures.target, const Duration(hours: 16));
  expect(figures.balance, Duration.zero);
  expect(figures.workDays, 2, reason: 'the 9th is outside the range');
});

test('averages over work days, not calendar days', () {
  final balances = [
    DayBalance(day: DateTime(2026, 9, 7), worked: const Duration(hours: 10), target: const Duration(hours: 8)),
    DayBalance(day: DateTime(2026, 9, 12), worked: const Duration(hours: 2), target: Duration.zero),
  ];

  final figures = figuresForRange(
    balances,
    DateTimeRange(start: DateTime(2026, 9, 7), end: DateTime(2026, 9, 14)),
  );

  expect(figures.workDays, 1, reason: 'Saturday has no target, so it is not a work day');
  expect(figures.averagePerWorkDay, const Duration(hours: 12));
});

test('an empty range reports zeroes rather than dividing by nothing', () {
  final figures = figuresForRange(
    const [],
    DateTimeRange(start: DateTime(2026, 9, 7), end: DateTime(2026, 9, 8)),
  );

  expect(figures.averagePerWorkDay, Duration.zero);
  expect(figures.completion, 0);
});
```

- [ ] **Step 2: Run them and watch them fail**

Run: `flutter test test/features/reports/balance_calculations_test.dart`
Expected: FAIL, `figuresForRange` / `RangeFigures` undefined.

- [ ] **Step 3: Implement `RangeFigures` and `figuresForRange`**

One pass over `balances`, skipping days outside `[range.start, range.end)`.
`averagePerWorkDay` divides the summed balance by `workDays`, guarding zero.
`completion` returns `0` when `target == Duration.zero`, so a range of free days
does not divide by nothing.

- [ ] **Step 4: Run them and watch them pass**

Run: `flutter test test/features/reports/balance_calculations_test.dart`

- [ ] **Step 5: Commit**

```bash
git commit -m "feat(reports): sum worked, target and average over a report range"
```

---

### Task 2: `BalanceAdjustments` — table, DAO, sync

**Files:**
- Create: `lib/data/drift/tables/balance_adjustments_table.dart`
- Create: `lib/data/drift/daos/balance_adjustments_dao.dart`
- Modify: `lib/data/drift/database.dart` (register the table and DAO, `schemaVersion` 12 → 13, `onUpgrade` `if (from < 13) await m.createTable(balanceAdjustments);`)
- Modify: `lib/data/sync/entity_types.dart`, `lib/data/sync/synced_writes.dart`, `lib/data/sync/sync_ingestor.dart`
- Create: `lib/core/di/balance_adjustment_providers.dart`
- Test: `test/data/drift/balance_adjustments_dao_test.dart`, `test/data/sync_round_trip_test.dart`

**Interfaces:**
- Produces:
  ```dart
  // table: id (text, PK), date (dateTime, local midnight), deltaMinutes (int, signed),
  //        note (text, nullable), deviceId, createdAt, updatedAt
  class BalanceAdjustmentsDao {
    Stream<List<BalanceAdjustment>> watchAllAdjustments();      // ascending by date
    Future<BalanceAdjustment> createAdjustment({required String deviceId, required DateTime date, required int deltaMinutes, String? note});
    Future<void> deleteAdjustment(String id);
  }
  // SyncedWrites.createAdjustment(...), SyncedWrites.deleteAdjustment(id)
  // EntityTypes.balanceAdjustment = 'balanceAdjustment'
  final balanceAdjustmentsProvider = StreamProvider<List<BalanceAdjustment>>(...);
  ```
  No update method: a correction is a dated fact, and fixing a wrong one is a
  delete plus a new one — the same call the UI already needs.

- [ ] **Step 1: Write the failing DAO tests**

```dart
test('createAdjustment stores a signed delta and its note', () async {
  final adjustment = await db.balanceAdjustmentsDao.createAdjustment(
    deviceId: 'd', date: DateTime(2026, 9, 7), deltaMinutes: -1440, note: '3 days paid out',
  );

  expect(adjustment.deltaMinutes, -1440);
  expect(adjustment.note, '3 days paid out');
  expect(adjustment.date, DateTime(2026, 9, 7));
});

test('watchAllAdjustments returns rows ascending by date', () async {
  await db.balanceAdjustmentsDao.createAdjustment(deviceId: 'd', date: DateTime(2026, 9, 9), deltaMinutes: 60);
  await db.balanceAdjustmentsDao.createAdjustment(deviceId: 'd', date: DateTime(2026, 9, 7), deltaMinutes: 30);

  final dates = (await db.balanceAdjustmentsDao.watchAllAdjustments().first).map((a) => a.date);
  expect(dates, [DateTime(2026, 9, 7), DateTime(2026, 9, 9)]);
});
```

- [ ] **Step 2: Run them and watch them fail**

Run: `flutter test test/data/drift/balance_adjustments_dao_test.dart`
Expected: FAIL, `balanceAdjustmentsDao` undefined.

- [ ] **Step 3: Add the table, bump the schema, run the generator**

```bash
dart run build_runner build --delete-conflicting-outputs
```

- [ ] **Step 4: Run the DAO tests and watch them pass**

- [ ] **Step 5: Write the failing round-trip test**

```dart
test('a balance adjustment reaches a second device', () async {
  final writerDb = AppDatabase.forTesting(NativeDatabase.memory());
  addTearDown(writerDb.close);
  final writes = SyncedWrites(db: writerDb, logWriter: SyncLogWriter(syncRoot: syncRoot, deviceId: 'writer'));
  await writes.createAdjustment(deviceId: 'writer', date: DateTime(2026, 9, 7), deltaMinutes: -480, note: 'paid out');

  final readerDb = AppDatabase.forTesting(NativeDatabase.memory());
  addTearDown(readerDb.close);
  await SyncIngestor(db: readerDb, syncRoot: syncRoot).syncNow();

  final row = (await readerDb.select(readerDb.balanceAdjustments).get()).single;
  expect(row.deltaMinutes, -480);
  expect(row.note, 'paid out');
});
```

- [ ] **Step 6: Wire `EntityTypes`, `SyncedWrites` and the ingestor case**

`_applyMaterializedEntity` uses `toCompanion(false)` for this table, like
`Absences`: a cleared note must reach the peer as cleared.
`rebuildFromScratch` clears `balanceAdjustments` too.

- [ ] **Step 7: Run the round-trip test and the whole sync suite**

Run: `flutter test test/data/`

- [ ] **Step 8: Commit**

```bash
git commit -m "feat(reports): store dated manual balance corrections"
```

---

### Task 3: Adjustments in the running balance

**Files:**
- Modify: `lib/features/reports/balance_calculations.dart`
- Test: `test/features/reports/balance_calculations_test.dart`

**Interfaces:**
- Produces: `runningBalance(..., {List<BalanceAdjustment> adjustments = const []})`
  and `figuresForRange(..., {List<BalanceAdjustment> adjustments = const []})`.

- [ ] **Step 1: Write the failing tests**

```dart
test('an adjustment is added on its effective date', () {
  final settings = appSettingsFixture(targetMinutesMonday: 480);
  final balances = [
    DayBalance(day: DateTime(2026, 9, 7), worked: const Duration(hours: 8), target: const Duration(hours: 8)),
  ];

  final total = runningBalance(
    balances,
    settings,
    asOf: DateTime(2026, 9, 8),
    adjustments: [_adjustment(DateTime(2026, 9, 7), -120)],
  );

  expect(total, const Duration(hours: -2));
});

test('an adjustment on a cutoff date is applied before the cutoff', () {
  // The spec is explicit: corrections land, then the cutoff clamps or
  // resets -- otherwise a payout booked on 31 December would survive the
  // reset it was meant to settle.
  final settings = appSettingsFixture(
    targetMinutesMonday: 480,
    balanceResetMode: 'resetToZero',
    balanceResetDay: 31,
    balanceResetMonth: 12,
  );
  final balances = [
    DayBalance(day: DateTime(2026, 12, 30), worked: const Duration(hours: 12), target: const Duration(hours: 8)),
  ];

  final total = runningBalance(
    balances,
    settings,
    asOf: DateTime(2027, 1, 5),
    adjustments: [_adjustment(DateTime(2026, 12, 31), -60)],
  );

  expect(total, Duration.zero, reason: 'the cutoff wipes the corrected balance, not the raw one');
});
```

- [ ] **Step 2: Run them and watch them fail**
- [ ] **Step 3: Fold adjustments into the forward pass**

Group adjustments by day; inside the loop add the day's deltas together with
`day.balance`, and apply the cutoffs for a date **after** its adjustments.
Adjustments on days with no `DayBalance` still count: walk the union of both
key sets, in date order.

- [ ] **Step 4: Run them and watch them pass**
- [ ] **Step 5: Commit**

```bash
git commit -m "feat(reports): count manual corrections toward the balance"
```

---

### Task 4: The four tiles

**Files:**
- Modify: `lib/features/reports/balance_card.dart` (grows into the block)
- Modify: `lib/features/reports/reports_providers.dart` (new `balanceFiguresProvider`)
- Modify: `lib/l10n/app_*.arb` (six files)
- Test: `test/features/reports/balance_card_test.dart`

**Interfaces:**
- Produces: `final balanceFiguresProvider = Provider<AsyncValue<RangeFigures>>(...)`,
  computed over the selected range from `reportViewControllerProvider`, ignoring
  its project and billable filters.
- New l10n keys: `reportsBalanceInRange`, `reportsBalanceTargetVsActual`,
  `reportsBalanceAveragePerDay`, `reportsBalanceCompletion` (a percentage).

- [ ] **Step 1: Write the failing widget test**

```dart
testWidgets('shows the range balance, the target and the average', (tester) async {
  await tester.pumpWidget(makeApp(
    settings: appSettingsFixture(targetMinutesMonday: 480, targetMinutesTuesday: 480),
    entries: [
      _entry(start: DateTime(2026, 9, 7, 9), end: DateTime(2026, 9, 7, 18)),  // 9h
      _entry(start: DateTime(2026, 9, 8, 9), end: DateTime(2026, 9, 8, 16)),  // 7h
    ],
  ));
  await tester.pumpAndSettle();

  expect(find.text('+0:00'), findsWidgets, reason: 'nine plus seven against two eight-hour days');
  expect(find.byType(LinearProgressIndicator), findsOneWidget);
  expect(find.textContaining('8:00'), findsWidgets, reason: 'the average over two work days');
});
```

- [ ] **Step 2: Run it and watch it fail**
- [ ] **Step 3: Build the tile row**

A `Wrap` of four cards so the block reflows on a narrow window rather than
overflowing. Each tile keeps the existing sign treatment: icon **and** colour,
never colour alone. The filter note stays on the block, not per tile.

- [ ] **Step 4: Run the widget tests and watch them pass**
- [ ] **Step 5: Run `flutter test test/l10n/` to prove the six ARBs still match**
- [ ] **Step 6: Commit**

```bash
git commit -m "feat(reports): show the range balance, target and daily average"
```

---

### Task 5: The correction dialog

**Files:**
- Create: `lib/features/reports/balance_adjustment_dialog.dart`
- Modify: `lib/features/reports/balance_card.dart` (an "add correction" action on the block)
- Modify: `lib/l10n/app_*.arb`
- Test: `test/features/reports/balance_adjustment_dialog_test.dart`

**Interfaces:**
- Produces: `showBalanceAdjustmentDialog(BuildContext, WidgetRef)`, which pops
  with `({DateTime date, int deltaMinutes, String? note})` or null, and a list of
  the existing corrections with a delete each.
- New l10n keys: `reportsAdjustmentTitle`, `reportsAdjustmentDelta`,
  `reportsAdjustmentNote`, `reportsAdjustmentAdd`, `reportsAdjustmentInvalid`.

- [ ] **Step 1: Write the failing widget tests**

```dart
testWidgets('a correction is entered as signed hours', (tester) async {
  final result = await showDialogUnderTest(tester);
  await tester.enterText(find.byKey(const ValueKey('adjustmentHours')), '-3.5');
  await tester.tap(find.text('Speichern'));
  await tester.pumpAndSettle();

  expect(result()?.deltaMinutes, -210);
});

testWidgets('text that is not a number is refused, not saved as zero', (tester) async {
  final result = await showDialogUnderTest(tester);
  await tester.enterText(find.byKey(const ValueKey('adjustmentHours')), 'drei');
  await tester.tap(find.text('Speichern'));
  await tester.pumpAndSettle();

  expect(result(), isNull);
  expect(find.text('Bitte eine Stundenzahl eingeben.'), findsOneWidget);
});
```

- [ ] **Step 2: Run them and watch them fail**
- [ ] **Step 3: Build the dialog**

Hours in, minutes stored: the field accepts a signed decimal and multiplies by
60, the same `hoursTextToMinutes` the work-time editors use — extended to accept
a leading minus, since a correction can go either way.

- [ ] **Step 4: Run them and watch them pass**
- [ ] **Step 5: Commit**

```bash
git commit -m "feat(reports): correct the balance with a dated, annotated entry"
```

---

### Task 6: Memory and changelog

**Files:**
- Modify: `docs/memory/features/work-time-balance.md`
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Record the decisions**

`BalanceAdjustments` has no update path and why; adjustments land before the
cutoff on their date and why; the tiles ignore the filters and say so.

- [ ] **Step 2: Add the user-facing lines under `## [Unreleased]`**

- [ ] **Step 3: Commit**

```bash
git commit -m "docs(reports): record the balance block's decisions"
```
