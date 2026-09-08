# Remaining Dashboard Blocks Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Finish the Reports dashboard — the three blocks the balance block left
behind: money and billability, tracking quality, and the trend chart.

**Architecture:** Each block is a pure calculation module plus a widget, in that
order, mirroring `balance_calculations.dart` / `balance_card.dart`. Money reuses
`totalsByProject`; quality reuses `break_rule_calculations.dart` and
`failed_pushes.dart`; the trend is drawn with a `CustomPainter` because the
project deliberately carries no charting dependency.

**Tech Stack:** Flutter, Riverpod (plain providers only), Drift,
flutter_gen-l10n with German as the template ARB.

**Spec:** `docs/superpowers/specs/2026-09-02-worktime-balance-dashboard-design.md`
(§6.2 trend, §6.3 money and billability, §6.4 tracking quality)

## Global Constraints

- **Every new string goes into all six ARB files**; `test/l10n/arb_completeness_test.dart`
  enforces it. German is the template, counted strings use ICU plurals.
- **No `@riverpod` code generation** anywhere near a drift type.
- **Filters:** blocks 2 (trend) and 4 (quality) compute over **every** entry in the
  range; only block 3 (money) follows the project and billable filters, like the
  project list. §6 is explicit about this split.
- **Widget tests** override every drift-backed provider with `Stream.value(...)`
  fixtures and mount `theme: AppTheme.light`.
- **Money is integer cents throughout.** No double arithmetic on amounts, and no
  summing across currencies — a total per currency, never one number.

---

### Task 1: Money and billability

**Files:**
- Create: `lib/features/reports/money_calculations.dart`
- Create: `lib/features/reports/money_card.dart`
- Modify: `lib/features/reports/reports_screen.dart` (mount the block)
- Modify: `lib/l10n/app_*.arb`
- Test: `test/features/reports/money_calculations_test.dart`,
  `test/features/reports/money_card_test.dart`

**Interfaces:**
- Produces:
  ```dart
  class MoneyFigures {
    final Duration billableDuration;
    final Duration totalDuration;
    final Map<String, int> revenueCentsByCurrency;  // key: currency code
    final List<ClientRevenue> topClients;           // by revenue, richest first
    double get billableShare;                       // 0 when nothing was tracked
  }
  typedef ClientRevenue = ({String clientName, int amountCents, String currency});

  MoneyFigures moneyFigures(
    List<TimeEntry> entries,
    List<Project> projects,
    List<Client> clients, {
    String noClientLabel = '—',
    int topClientCount = 3,
  });
  ```

- [ ] **Step 1: Write the failing calculation tests**

```dart
test('the billable share is of tracked time, not of the range', () {
  final figures = moneyFigures(
    [_entry(projectId: 'billable-p', minutes: 60), _entry(projectId: 'internal-p', minutes: 180)],
    [_project(id: 'billable-p', billable: true, rateCents: 10000, currency: 'EUR'),
     _project(id: 'internal-p', billable: false)],
    const [],
  );

  expect(figures.billableShare, 0.25);
  expect(figures.revenueCentsByCurrency, {'EUR': 10000});
});

test('currencies are kept apart rather than added up', () {
  final figures = moneyFigures(
    [_entry(projectId: 'eur', minutes: 60), _entry(projectId: 'usd', minutes: 60)],
    [_project(id: 'eur', billable: true, rateCents: 10000, currency: 'EUR'),
     _project(id: 'usd', billable: true, rateCents: 20000, currency: 'USD')],
    const [],
  );

  expect(figures.revenueCentsByCurrency, {'EUR': 10000, 'USD': 20000});
});

test('a billable project without a rate earns nothing and still counts as billable', () {
  final figures = moneyFigures(
    [_entry(projectId: 'p', minutes: 60)],
    [_project(id: 'p', billable: true)],
    const [],
  );

  expect(figures.billableShare, 1.0);
  expect(figures.revenueCentsByCurrency, isEmpty);
});

test('nothing tracked is a share of zero, not a division by zero', () {
  expect(moneyFigures(const [], const [], const []).billableShare, 0);
});

test('top clients are ordered by revenue and capped', () {
  final figures = moneyFigures(entries, projects, clients, topClientCount: 2);
  expect(figures.topClients.map((c) => c.clientName), ['Big', 'Medium']);
});
```

- [ ] **Step 2: Run them and watch them fail** — `flutter test test/features/reports/money_calculations_test.dart`
- [ ] **Step 3: Implement `moneyFigures`**

Reuse `totalsByProject` for the per-project amounts, then fold by currency and by
client. An entry whose project is unknown is non-billable and earns nothing.

- [ ] **Step 4: Run them and watch them pass**
- [ ] **Step 5: Write the failing widget test**

```dart
testWidgets('shows the billable share, revenue per currency and the top clients', (tester) async {
  await pumpCard(tester, entries: [...], projects: [...], clients: [...]);

  expect(find.text('25 %'), findsOneWidget);
  expect(find.text('100,00 €'), findsOneWidget);
  expect(find.text('Acme'), findsOneWidget);
});
```

- [ ] **Step 6: Build `MoneyCard`** — the same tile shapes the balance block uses;
  amounts formatted with `NumberFormat.currency` for the app's locale.
- [ ] **Step 7: Run the widget test, then `flutter test test/l10n/`**
- [ ] **Step 8: Commit**

```bash
git commit -m "feat(reports): show the billable share, revenue and top clients"
```

---

### Task 2: Tracking quality

**Files:**
- Create: `lib/features/reports/quality_calculations.dart`
- Create: `lib/features/reports/quality_card.dart`
- Modify: `lib/features/reports/reports_screen.dart`, `lib/l10n/app_*.arb`
- Test: `test/features/reports/quality_calculations_test.dart`,
  `test/features/reports/quality_card_test.dart`

**Interfaces:**
- Consumes: `DayBalance` (for the work-day set), `dayBreakDuration` and
  `requiredBreakForWorked` from `break_rule_calculations.dart`, `failedPushes`
  from `failed_pushes.dart`.
- Produces:
  ```dart
  class QualityFigures {
    final List<DateTime> unbookedWorkDays;     // work days with neither entry nor absence
    final List<DateTime> shortBreakDays;
    final int failedPushCount;
    final Map<String, int> absenceDaysByTypeName;
  }

  QualityFigures qualityFigures({
    required List<DayBalance> balances,
    required List<TimeEntry> entries,
    required List<Absence> absences,
    required Map<String, AbsenceType> absenceTypesById,
    required List<BreakRuleTier> tiers,
    required bool includePausedTimeInBreak,
    required int failedPushCount,
    required DateTimeRange range,
  });
  ```

- [ ] **Step 1: Write the failing calculation tests**

```dart
test('a work day with neither an entry nor an absence is unbooked', () {
  final figures = qualityFigures(
    balances: [DayBalance(day: monday, worked: Duration.zero, target: const Duration(hours: 8))],
    entries: const [], absences: const [], absenceTypesById: const {},
    tiers: const [], includePausedTimeInBreak: false, failedPushCount: 0,
    range: DateTimeRange(start: monday, end: monday.add(const Duration(days: 1))),
  );

  expect(figures.unbookedWorkDays, [monday]);
});

test('a day covered by an absence is not unbooked', () { ... expect(figures.unbookedWorkDays, isEmpty); });

test('a day whose break falls short of the rule is listed', () {
  // Six hours worked with a five-minute break against a tier demanding 30.
  expect(figures.shortBreakDays, [monday]);
});

test('absence days are counted per type name', () {
  expect(figures.absenceDaysByTypeName, {'Urlaub': 2, 'Krank': 1});
});
```

- [ ] **Step 2: Run them and watch them fail**
- [ ] **Step 3: Implement `qualityFigures`** — one pass over the days in range.
- [ ] **Step 4: Run them and watch them pass**
- [ ] **Step 5: Write the failing widget test**

```dart
testWidgets('names what is missing rather than only counting it', (tester) async {
  await pumpCard(tester, ...);
  expect(find.text('1 Arbeitstag ohne Buchung'), findsOneWidget);
  expect(find.textContaining('Urlaub'), findsOneWidget);
});
```

- [ ] **Step 6: Build `QualityCard`** — counted strings use ICU plurals; each row
  states the figure and what it means, never a bare number.
- [ ] **Step 7: Run the widget test, then `flutter test test/l10n/`**
- [ ] **Step 8: Commit**

```bash
git commit -m "feat(reports): show what the tracking is missing"
```

---

### Task 3: The trend chart

**Files:**
- Create: `lib/features/reports/trend_calculations.dart`
- Create: `lib/features/reports/trend_chart.dart`
- Modify: `lib/features/reports/reports_screen.dart`, `lib/l10n/app_*.arb`
- Test: `test/features/reports/trend_calculations_test.dart`,
  `test/features/reports/trend_chart_test.dart`

**Interfaces:**
- Produces:
  ```dart
  enum TrendGranularity { day, week }
  typedef TrendBar = ({DateTime start, Duration worked, Duration target, String label});

  /// Switches to weeks beyond [dayLimit] days, so a year does not become 365 bars.
  TrendGranularity granularityFor(DateTimeRange range, {int dayLimit = 62});
  List<TrendBar> trendBars(List<DayBalance> balances, DateTimeRange range, TrendGranularity granularity);
  ```

- [ ] **Step 1: Write the failing calculation tests**

```dart
test('a range of two months or less is drawn per day', () {
  expect(granularityFor(DateTimeRange(start: DateTime(2026, 9, 1), end: DateTime(2026, 9, 30))),
      TrendGranularity.day);
});

test('a longer range is drawn per week', () {
  expect(granularityFor(DateTimeRange(start: DateTime(2026, 1, 1), end: DateTime(2026, 12, 31))),
      TrendGranularity.week);
});

test('weekly bars sum the days of their ISO week', () {
  final bars = trendBars(balances, range, TrendGranularity.week);
  expect(bars.single.worked, const Duration(hours: 40));
  expect(bars.single.target, const Duration(hours: 40));
});

test('a day with no entry is still a bar, so a gap is visible as a gap', () {
  expect(bars, hasLength(3));
  expect(bars[1].worked, Duration.zero);
});
```

- [ ] **Step 2: Run them and watch them fail**
- [ ] **Step 3: Implement `granularityFor` and `trendBars`**
- [ ] **Step 4: Run them and watch them pass**
- [ ] **Step 5: Write the failing widget test**

```dart
testWidgets('draws one labelled bar per period with a target line', (tester) async {
  await pumpChart(tester, bars: [...]);

  // The painter is not readable from a test, so the accessible labels are
  // what proves each bar exists and carries its figures.
  expect(find.bySemanticsLabel(RegExp('07.09.2026')), findsOneWidget);
  expect(find.byType(CustomPaint), findsWidgets);
});
```

- [ ] **Step 6: Build `TrendChart`**

A `CustomPainter` for the bars and the target line, wrapped in a `Semantics`
container with one `Semantics` child per bar carrying "date, worked of target" —
the accessible equivalent of the hover tooltip, as §6.2 requires. Bars scale to
the tallest of worked and target so the target line always falls inside the box.

- [ ] **Step 7: Run the widget test, then `flutter test test/l10n/`**
- [ ] **Step 8: Commit**

```bash
git commit -m "feat(reports): chart worked time against the target over the range"
```

---

### Task 4: Memory and changelog

**Files:**
- Modify: `docs/memory/features/work-time-balance.md`, `CHANGELOG.md`

- [ ] **Step 1: Record the decisions** — why money follows the filters while the
  other blocks do not; why currencies are never summed; the day/week switch
  threshold; why the chart carries per-bar semantics instead of a tooltip alone.
- [ ] **Step 2: Add the user-facing lines under `## [Unreleased]`**
- [ ] **Step 3: Commit**

```bash
git commit -m "docs(reports): record the dashboard blocks' decisions"
```
