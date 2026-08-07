# Report Filters & Additional Presets Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Today/Yesterday report presets, a combinable Project + Billable filter with device-local persistence, and make CSV export respect the active filters.

**Architecture:** Two new small pure-Dart files (`report_view_state.dart`, `report_calculations.dart`'s new `filterEntries`) carry the testable logic; a new `ReportViewStateStore` (plain JSON file, mirrors `WindowBoundsStore`) persists it; a new `ReportViewController` (Riverpod `@riverpod` `AsyncNotifier`, mirrors `LocaleController`) is the single source of truth the screen reads and writes through. `reportEntriesProvider` becomes a `.family` provider keyed by the resolved `DateTimeRange` so it never needs to import the controller (avoids a circular import between `reports_providers.dart` and the new controller file).

**Tech Stack:** Flutter (Riverpod 3.x with `riverpod_annotation`/`riverpod_generator` codegen, Drift, `path_provider`), Dart, `flutter_test`.

## Global Constraints

- User-facing strings must be localized via ARB files in `lib/l10n/` (`app_de.arb` is the source locale) — never hardcode UI text. All 6 locale files (`de`, `en`, `es`, `fr`, `it`, `nl`) must define the same keys (`test/l10n/arb_completeness_test.dart` enforces this).
- Never log or persist secrets — not applicable to this feature, no credentials involved.
- Format code with `dart format .`; `flutter analyze` and `flutter test` must pass before each commit.
- Feature-first structure: all new files live under `lib/features/reports/`.
- Device-local UI preferences (this feature's view state) must NOT go through `SyncedWrites`/the event log — same reasoning already applied to `WindowBoundsStore` and `LocaleStore`.
- Commit after every task using Conventional Commits format (`feat(reports): ...`, `test(reports): ...`), imperative mood, lowercase, no trailing period, under 72 chars.

---

## Task 1: Today/Yesterday presets

**Files:**
- Modify: `lib/features/reports/reports_providers.dart`
- Test: `test/features/reports/reports_providers_test.dart` (new)

**Interfaces:**
- Produces: `ReportRangePreset.today`, `ReportRangePreset.yesterday` — consumed by Task 9 (UI) and Task 2 (`ReportViewState`).

- [ ] **Step 1: Write the failing test**

Create `test/features/reports/reports_providers_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/features/reports/reports_providers.dart';

void main() {
  final now = DateTime(2026, 8, 7, 14, 30); // a Friday

  group('rangeForPreset', () {
    test('today returns just the current calendar day', () {
      final range = rangeForPreset(ReportRangePreset.today, now: now);
      expect(range.start, DateTime(2026, 8, 7));
      expect(range.end, DateTime(2026, 8, 8));
    });

    test('yesterday returns the previous calendar day', () {
      final range = rangeForPreset(ReportRangePreset.yesterday, now: now);
      expect(range.start, DateTime(2026, 8, 6));
      expect(range.end, DateTime(2026, 8, 7));
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/reports/reports_providers_test.dart`
Expected: FAIL — compile error, `ReportRangePreset` has no member `today`/`yesterday`.

- [ ] **Step 3: Add the two presets**

In `lib/features/reports/reports_providers.dart`, change:

```dart
enum ReportRangePreset { thisWeek, thisMonth, last30Days, all }
```

to:

```dart
enum ReportRangePreset { today, yesterday, thisWeek, thisMonth, last30Days, all }
```

And change the `switch` in `rangeForPreset` from:

```dart
DateTimeRange rangeForPreset(ReportRangePreset preset, {DateTime? now}) {
  final today = _startOfDay(now ?? DateTime.now());
  switch (preset) {
    case ReportRangePreset.thisWeek:
```

to:

```dart
DateTimeRange rangeForPreset(ReportRangePreset preset, {DateTime? now}) {
  final today = _startOfDay(now ?? DateTime.now());
  switch (preset) {
    case ReportRangePreset.today:
      return DateTimeRange(start: today, end: today.add(const Duration(days: 1)));
    case ReportRangePreset.yesterday:
      final yesterday = today.subtract(const Duration(days: 1));
      return DateTimeRange(start: yesterday, end: today);
    case ReportRangePreset.thisWeek:
```

(leave every other case exactly as-is).

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/reports/reports_providers_test.dart`
Expected: PASS (2 tests)

- [ ] **Step 5: Commit**

```bash
git add lib/features/reports/reports_providers.dart test/features/reports/reports_providers_test.dart
git commit -m "feat(reports): add today and yesterday range presets"
```

---

## Task 2: `ReportViewState` + `BillableFilter` pure model

**Files:**
- Create: `lib/features/reports/report_view_state.dart`
- Test: `test/features/reports/report_view_state_test.dart` (new)

**Interfaces:**
- Consumes: `ReportRangePreset`, `rangeForPreset` from `reports_providers.dart` (Task 1).
- Produces: `enum BillableFilter { all, billableOnly, nonBillableOnly }`; `class ReportViewState` with fields `preset` (`ReportRangePreset?`), `customRange` (`DateTimeRange?`), `projectIds` (`Set<String>`), `billableFilter` (`BillableFilter`); getters `range` (`DateTimeRange`) and `activeFilterCount` (`int`); method `copyWith(...)`. Consumed by Task 3 (store), Task 4 (controller), Task 5 (`filterEntries`), Task 8/9 (UI).

- [ ] **Step 1: Write the failing test**

Create `test/features/reports/report_view_state_test.dart`:

```dart
import 'package:flutter/material.dart' show DateTimeRange;
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/features/reports/report_view_state.dart';
import 'package:hickory/features/reports/reports_providers.dart';

void main() {
  group('ReportViewState.range', () {
    test('resolves via rangeForPreset when preset is set', () {
      const state = ReportViewState(preset: ReportRangePreset.all);
      expect(state.range, rangeForPreset(ReportRangePreset.all));
    });

    test('resolves customRange when preset is null', () {
      final customRange = DateTimeRange(start: DateTime(2026, 1, 1), end: DateTime(2026, 2, 1));
      final state = ReportViewState(preset: null, customRange: customRange);
      expect(state.range, customRange);
    });
  });

  group('ReportViewState.copyWith', () {
    test('setting a custom range together with a null preset nulls out the preset', () {
      const state = ReportViewState(preset: ReportRangePreset.thisWeek);
      final customRange = DateTimeRange(start: DateTime(2026, 1, 1), end: DateTime(2026, 1, 8));

      final next = state.copyWith(preset: () => null, customRange: () => customRange);

      expect(next.preset, isNull);
      expect(next.customRange, customRange);
    });

    test('switching back to a preset together with a null custom range clears it', () {
      final customRange = DateTimeRange(start: DateTime(2026, 1, 1), end: DateTime(2026, 1, 8));
      final state = ReportViewState(preset: null, customRange: customRange);

      final next = state.copyWith(preset: () => ReportRangePreset.thisMonth, customRange: () => null);

      expect(next.preset, ReportRangePreset.thisMonth);
      expect(next.customRange, isNull);
    });

    test('updating projectIds/billableFilter leaves the range untouched', () {
      const state = ReportViewState(preset: ReportRangePreset.thisMonth);

      final next = state.copyWith(projectIds: {'p1'}, billableFilter: BillableFilter.billableOnly);

      expect(next.preset, ReportRangePreset.thisMonth);
      expect(next.projectIds, {'p1'});
      expect(next.billableFilter, BillableFilter.billableOnly);
    });
  });

  group('ReportViewState.activeFilterCount', () {
    test('is 0 with no filters', () {
      expect(const ReportViewState().activeFilterCount, 0);
    });

    test('counts project selection and billable filter independently', () {
      expect(const ReportViewState(projectIds: {'p1'}).activeFilterCount, 1);
      expect(
        const ReportViewState(billableFilter: BillableFilter.nonBillableOnly).activeFilterCount,
        1,
      );
      expect(
        const ReportViewState(
          projectIds: {'p1'},
          billableFilter: BillableFilter.billableOnly,
        ).activeFilterCount,
        2,
      );
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/reports/report_view_state_test.dart`
Expected: FAIL — `report_view_state.dart` doesn't exist yet.

- [ ] **Step 3: Create the model**

Create `lib/features/reports/report_view_state.dart`:

```dart
import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter/material.dart' show DateTimeRange;

import 'reports_providers.dart';

enum BillableFilter { all, billableOnly, nonBillableOnly }

/// Immutable snapshot of everything the Reports screen remembers across
/// restarts: the selected range (as a preset, or explicit custom bounds when
/// [preset] is null) plus the active filters. Empty [projectIds] means "all
/// projects" (not "no projects").
@immutable
class ReportViewState {
  const ReportViewState({
    this.preset = ReportRangePreset.thisMonth,
    this.customRange,
    this.projectIds = const {},
    this.billableFilter = BillableFilter.all,
  });

  final ReportRangePreset? preset;
  final DateTimeRange? customRange;
  final Set<String> projectIds;
  final BillableFilter billableFilter;

  // customRange is always set together with a null preset (see
  // ReportViewController.setPreset/setCustomRange in report_view_controller.dart),
  // so the ! here reflects that invariant rather than an unchecked assumption.
  DateTimeRange get range => preset == null ? customRange! : rangeForPreset(preset!);

  int get activeFilterCount =>
      (projectIds.isNotEmpty ? 1 : 0) + (billableFilter != BillableFilter.all ? 1 : 0);

  ReportViewState copyWith({
    ReportRangePreset? Function()? preset,
    DateTimeRange? Function()? customRange,
    Set<String>? projectIds,
    BillableFilter? billableFilter,
  }) {
    return ReportViewState(
      preset: preset == null ? this.preset : preset(),
      customRange: customRange == null ? this.customRange : customRange(),
      projectIds: projectIds ?? this.projectIds,
      billableFilter: billableFilter ?? this.billableFilter,
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/reports/report_view_state_test.dart`
Expected: PASS (7 tests)

- [ ] **Step 5: Commit**

```bash
git add lib/features/reports/report_view_state.dart test/features/reports/report_view_state_test.dart
git commit -m "feat(reports): add ReportViewState and BillableFilter model"
```

---

## Task 3: `ReportViewStateStore` (device-local JSON persistence)

**Files:**
- Create: `lib/features/reports/report_view_state_store.dart`
- Test: `test/features/reports/report_view_state_store_test.dart` (new)

**Interfaces:**
- Consumes: `ReportViewState`, `BillableFilter` (Task 2); `ReportRangePreset` (Task 1).
- Produces: `class ReportViewStateStore { ReportViewStateStore({required Directory supportDirectory}); Future<ReportViewState> read(); Future<void> write(ReportViewState state); }`. Consumed by Task 4.

- [ ] **Step 1: Write the failing test**

Create `test/features/reports/report_view_state_store_test.dart`:

```dart
import 'dart:io';

import 'package:flutter/material.dart' show DateTimeRange;
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/features/reports/report_view_state.dart';
import 'package:hickory/features/reports/report_view_state_store.dart';
import 'package:hickory/features/reports/reports_providers.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('hickory_report_view_state_test_');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test('read returns the default state before any write', () async {
    final store = ReportViewStateStore(supportDirectory: tempDir);
    final state = await store.read();
    expect(state.preset, ReportRangePreset.thisMonth);
    expect(state.customRange, isNull);
    expect(state.projectIds, isEmpty);
    expect(state.billableFilter, BillableFilter.all);
  });

  test('write then read round-trips a preset-based state, and persists across instances', () async {
    final store = ReportViewStateStore(supportDirectory: tempDir);
    const state = ReportViewState(
      preset: ReportRangePreset.today,
      projectIds: {'p1', 'p2'},
      billableFilter: BillableFilter.billableOnly,
    );

    await store.write(state);

    final read = await store.read();
    expect(read.preset, ReportRangePreset.today);
    expect(read.customRange, isNull);
    expect(read.projectIds, {'p1', 'p2'});
    expect(read.billableFilter, BillableFilter.billableOnly);
    final fresh = await ReportViewStateStore(supportDirectory: tempDir).read();
    expect(fresh.preset, ReportRangePreset.today);
  });

  test('write then read round-trips a custom-range state', () async {
    final store = ReportViewStateStore(supportDirectory: tempDir);
    final range = DateTimeRange(start: DateTime(2026, 1, 1), end: DateTime(2026, 2, 1));
    final state = ReportViewState(preset: null, customRange: range);

    await store.write(state);

    final read = await store.read();
    expect(read.preset, isNull);
    expect(read.customRange, range);
  });

  test('read returns the default state for a corrupt file instead of throwing', () async {
    final file = File('${tempDir.path}/report_view_state.json');
    await file.writeAsString('{not valid json');

    final store = ReportViewStateStore(supportDirectory: tempDir);
    final state = await store.read();
    expect(state.preset, ReportRangePreset.thisMonth);
  });

  test('read returns the default state for an unrecognized preset name', () async {
    final file = File('${tempDir.path}/report_view_state.json');
    await file.writeAsString('{"preset": "someFuturePreset"}');

    final store = ReportViewStateStore(supportDirectory: tempDir);
    final state = await store.read();
    expect(state.preset, ReportRangePreset.thisMonth);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/reports/report_view_state_store_test.dart`
Expected: FAIL — `report_view_state_store.dart` doesn't exist yet.

- [ ] **Step 3: Create the store**

Create `lib/features/reports/report_view_state_store.dart`:

```dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart' show DateTimeRange;
import 'package:path/path.dart' as p;

import 'report_view_state.dart';
import 'reports_providers.dart';

/// Persists the Reports screen's last-used range and filters as a plain
/// JSON file in the app-support directory. Device-local only (deliberately
/// not synced -- this is a UI viewing preference for this device, not data,
/// same reasoning as WindowBoundsStore/LocaleStore). Takes the support
/// directory as a constructor parameter so it's trivially testable against
/// a temp directory -- the real caller passes
/// `await getApplicationSupportDirectory()`.
class ReportViewStateStore {
  ReportViewStateStore({required this.supportDirectory});

  final Directory supportDirectory;

  File get _file => File(p.join(supportDirectory.path, 'report_view_state.json'));

  /// Returns the default state (this-month preset, no filters) if the file
  /// is missing, unreadable, or contains an unrecognized preset/billable
  /// value -- same fall-back-to-defaults contract as WindowBoundsStore.read().
  Future<ReportViewState> read() async {
    try {
      final content = await _file.readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;

      final presetName = json['preset'] as String?;
      final preset = presetName == null ? null : ReportRangePreset.values.byName(presetName);

      final customStart = json['customRangeStart'] as String?;
      final customEnd = json['customRangeEnd'] as String?;
      final customRange = (customStart != null && customEnd != null)
          ? DateTimeRange(start: DateTime.parse(customStart), end: DateTime.parse(customEnd))
          : null;

      final billableName = json['billableFilter'] as String?;
      final billableFilter =
          billableName == null ? BillableFilter.all : BillableFilter.values.byName(billableName);

      final projectIds =
          (json['projectIds'] as List<dynamic>?)?.cast<String>().toSet() ?? const <String>{};

      return ReportViewState(
        preset: preset,
        customRange: customRange,
        projectIds: projectIds,
        billableFilter: billableFilter,
      );
    } on Object {
      // Missing file, corrupt JSON, or an unrecognized preset/billable-filter
      // name (e.g. from a newer/older app version) -- fall back to defaults
      // rather than surfacing a broken state to the Reports screen.
      return const ReportViewState();
    }
  }

  Future<void> write(ReportViewState state) async {
    await _file.create(recursive: true);
    await _file.writeAsString(
      jsonEncode({
        'preset': state.preset?.name,
        'customRangeStart': state.customRange?.start.toIso8601String(),
        'customRangeEnd': state.customRange?.end.toIso8601String(),
        'projectIds': state.projectIds.toList(),
        'billableFilter': state.billableFilter.name,
      }),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/reports/report_view_state_store_test.dart`
Expected: PASS (5 tests)

- [ ] **Step 5: Commit**

```bash
git add lib/features/reports/report_view_state_store.dart test/features/reports/report_view_state_store_test.dart
git commit -m "feat(reports): add ReportViewStateStore for local persistence"
```

---

## Task 4: `ReportViewController` (Riverpod codegen `AsyncNotifier`)

**Files:**
- Create: `lib/features/reports/report_view_controller.dart`
- Test: `test/features/reports/report_view_controller_test.dart` (new)

**Interfaces:**
- Consumes: `ReportViewState`, `BillableFilter` (Task 2); `ReportViewStateStore` (Task 3); `ReportRangePreset` (Task 1).
- Produces: `reportViewStateStoreProvider` (`FutureProvider`-shaped, `.overrideWith((ref) async => store)`); `reportViewControllerProvider` (`AsyncNotifierProvider<ReportViewController, ReportViewState>`) with methods `setPreset`, `setCustomRange`, `setProjectIds`, `setBillableFilter`, `resetFilters`. Consumed by Task 6 is NOT needed (see Task 6 note on avoiding a circular import) — consumed by Task 8 (dialog) and Task 9 (screen).

- [ ] **Step 1: Write the failing test**

Create `test/features/reports/report_view_controller_test.dart`:

```dart
import 'dart:io';

import 'package:flutter/material.dart' show DateTimeRange;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/features/reports/report_view_controller.dart';
import 'package:hickory/features/reports/report_view_state.dart';
import 'package:hickory/features/reports/report_view_state_store.dart';
import 'package:hickory/features/reports/reports_providers.dart';

void main() {
  late Directory tempDir;

  setUp(() => tempDir = Directory.systemTemp.createTempSync('report_view_controller_test'));
  tearDown(() => tempDir.deleteSync(recursive: true));

  ProviderContainer makeContainer() => ProviderContainer(
        overrides: [
          reportViewStateStoreProvider.overrideWith(
            (ref) async => ReportViewStateStore(supportDirectory: tempDir),
          ),
        ],
      );

  test('starts at the default state when nothing is stored', () async {
    final container = makeContainer();
    addTearDown(container.dispose);
    final state = await container.read(reportViewControllerProvider.future);
    expect(state.preset, ReportRangePreset.thisMonth);
    expect(state.projectIds, isEmpty);
  });

  test('setPreset updates state and persists across containers', () async {
    final first = makeContainer();
    await first.read(reportViewControllerProvider.future);
    await first.read(reportViewControllerProvider.notifier).setPreset(ReportRangePreset.today);
    expect(first.read(reportViewControllerProvider).value?.preset, ReportRangePreset.today);
    first.dispose();

    final second = makeContainer();
    addTearDown(second.dispose);
    final state = await second.read(reportViewControllerProvider.future);
    expect(state.preset, ReportRangePreset.today);
  });

  test('setCustomRange clears the preset and persists', () async {
    final container = makeContainer();
    addTearDown(container.dispose);
    await container.read(reportViewControllerProvider.future);
    final range = DateTimeRange(start: DateTime(2026, 1, 1), end: DateTime(2026, 1, 8));

    await container.read(reportViewControllerProvider.notifier).setCustomRange(range);

    final state = container.read(reportViewControllerProvider).value!;
    expect(state.preset, isNull);
    expect(state.customRange, range);
  });

  test('setProjectIds and setBillableFilter update independently of range', () async {
    final container = makeContainer();
    addTearDown(container.dispose);
    await container.read(reportViewControllerProvider.future);
    final controller = container.read(reportViewControllerProvider.notifier);

    await controller.setProjectIds({'p1'});
    await controller.setBillableFilter(BillableFilter.nonBillableOnly);

    final state = container.read(reportViewControllerProvider).value!;
    expect(state.preset, ReportRangePreset.thisMonth);
    expect(state.projectIds, {'p1'});
    expect(state.billableFilter, BillableFilter.nonBillableOnly);
  });

  test('resetFilters clears filters but keeps the current range', () async {
    final container = makeContainer();
    addTearDown(container.dispose);
    await container.read(reportViewControllerProvider.future);
    final controller = container.read(reportViewControllerProvider.notifier);
    await controller.setPreset(ReportRangePreset.today);
    await controller.setProjectIds({'p1'});
    await controller.setBillableFilter(BillableFilter.billableOnly);

    await controller.resetFilters();

    final state = container.read(reportViewControllerProvider).value!;
    expect(state.preset, ReportRangePreset.today);
    expect(state.projectIds, isEmpty);
    expect(state.billableFilter, BillableFilter.all);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/reports/report_view_controller_test.dart`
Expected: FAIL — `report_view_controller.dart` doesn't exist yet.

- [ ] **Step 3: Create the controller**

Create `lib/features/reports/report_view_controller.dart`:

```dart
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/material.dart' show DateTimeRange;
import 'package:path_provider/path_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'report_view_state.dart';
import 'report_view_state_store.dart';
import 'reports_providers.dart';

part 'report_view_controller.g.dart';

@Riverpod(keepAlive: true)
Future<ReportViewStateStore> reportViewStateStore(Ref ref) async =>
    ReportViewStateStore(supportDirectory: await getApplicationSupportDirectory());

/// The Reports screen's remembered range + filters (see [ReportViewState]).
/// Loaded once from disk on first use and kept alive for the app's
/// lifetime -- same pattern as LocaleController.
@Riverpod(keepAlive: true)
class ReportViewController extends _$ReportViewController {
  @override
  Future<ReportViewState> build() async {
    final store = await ref.watch(reportViewStateStoreProvider.future);
    return store.read();
  }

  Future<void> _update(ReportViewState Function(ReportViewState) update) async {
    final next = update(state.value ?? const ReportViewState());
    // State first: the change applies to the running session even when
    // persisting fails (same precaution as LocaleController.setLocale).
    state = AsyncData(next);
    try {
      final store = await ref.read(reportViewStateStoreProvider.future);
      await store.write(next);
    } catch (error) {
      debugPrint('Failed to persist report view state: $error');
    }
  }

  Future<void> setPreset(ReportRangePreset preset) =>
      _update((s) => s.copyWith(preset: () => preset, customRange: () => null));

  Future<void> setCustomRange(DateTimeRange range) =>
      _update((s) => s.copyWith(preset: () => null, customRange: () => range));

  Future<void> setProjectIds(Set<String> ids) => _update((s) => s.copyWith(projectIds: ids));

  Future<void> setBillableFilter(BillableFilter filter) =>
      _update((s) => s.copyWith(billableFilter: filter));

  Future<void> resetFilters() =>
      _update((s) => s.copyWith(projectIds: {}, billableFilter: BillableFilter.all));
}
```

- [ ] **Step 4: Generate the `.g.dart` part file**

Run: `dart run build_runner build --delete-conflicting-outputs`
Expected: completes with `lib/features/reports/report_view_controller.g.dart` created.

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/features/reports/report_view_controller_test.dart`
Expected: PASS (5 tests)

- [ ] **Step 6: Commit**

```bash
git add lib/features/reports/report_view_controller.dart lib/features/reports/report_view_controller.g.dart test/features/reports/report_view_controller_test.dart
git commit -m "feat(reports): add ReportViewController for persisted range and filters"
```

---

## Task 5: `filterEntries` pure function

**Files:**
- Modify: `lib/features/reports/report_calculations.dart`
- Modify: `test/features/reports/report_calculations_test.dart`

**Interfaces:**
- Consumes: `BillableFilter` (Task 2).
- Produces: `List<TimeEntry> filterEntries(List<TimeEntry> entries, List<Project> projects, {required Set<String> projectIds, required BillableFilter billableFilter})`. Consumed by Task 9.

- [ ] **Step 1: Write the failing test**

In `test/features/reports/report_calculations_test.dart`, first extend the existing `_entry` helper (currently missing a `billableOverride` parameter) — change:

```dart
TimeEntry _entry({
  required String id,
  String? projectId,
  required DateTime startAt,
  required DateTime endAt,
  String? description,
}) {
  final now = DateTime.utc(2026, 7, 1);
  return TimeEntry(
    id: id,
    projectId: projectId,
    description: description,
    startAt: startAt,
    endAt: endAt,
    source: 'manual',
    deviceId: 'dev_a',
    createdAt: now,
    updatedAt: now,
    totalPausedSeconds: 0,
  );
}
```

to:

```dart
TimeEntry _entry({
  required String id,
  String? projectId,
  required DateTime startAt,
  required DateTime endAt,
  String? description,
  bool? billableOverride,
}) {
  final now = DateTime.utc(2026, 7, 1);
  return TimeEntry(
    id: id,
    projectId: projectId,
    description: description,
    startAt: startAt,
    endAt: endAt,
    source: 'manual',
    deviceId: 'dev_a',
    createdAt: now,
    updatedAt: now,
    totalPausedSeconds: 0,
    billableOverride: billableOverride,
  );
}
```

Then add the import `import 'package:hickory/features/reports/report_view_state.dart';` at the top, and append this new group at the end of `main()`, before the closing `}`:

```dart
  group('filterEntries', () {
    final billableProject = _project(id: 'p1', name: 'Billable Co');
    final nonBillableProject = _project(id: 'p2', name: 'Internal', billable: false);
    final projects = [billableProject, nonBillableProject];

    test('returns entries unchanged when no filters are active', () {
      final entries = [
        _entry(
          id: 'e1',
          projectId: 'p1',
          startAt: DateTime.utc(2026, 7, 7, 9),
          endAt: DateTime.utc(2026, 7, 7, 10),
        ),
      ];
      final result =
          filterEntries(entries, projects, projectIds: {}, billableFilter: BillableFilter.all);
      expect(result, entries);
    });

    test('project filter excludes non-matching and no-project entries', () {
      final entries = [
        _entry(
          id: 'e1',
          projectId: 'p1',
          startAt: DateTime.utc(2026, 7, 7, 9),
          endAt: DateTime.utc(2026, 7, 7, 10),
        ),
        _entry(
          id: 'e2',
          projectId: 'p2',
          startAt: DateTime.utc(2026, 7, 7, 9),
          endAt: DateTime.utc(2026, 7, 7, 10),
        ),
        _entry(
          id: 'e3',
          startAt: DateTime.utc(2026, 7, 7, 9),
          endAt: DateTime.utc(2026, 7, 7, 10),
        ),
      ];
      final result = filterEntries(
        entries,
        projects,
        projectIds: {'p1'},
        billableFilter: BillableFilter.all,
      );
      expect(result.map((e) => e.id), ['e1']);
    });

    test('billableOnly uses the project billable flag when no override is set', () {
      final entries = [
        _entry(
          id: 'e1',
          projectId: 'p1',
          startAt: DateTime.utc(2026, 7, 7, 9),
          endAt: DateTime.utc(2026, 7, 7, 10),
        ),
        _entry(
          id: 'e2',
          projectId: 'p2',
          startAt: DateTime.utc(2026, 7, 7, 9),
          endAt: DateTime.utc(2026, 7, 7, 10),
        ),
      ];
      final result = filterEntries(
        entries,
        projects,
        projectIds: {},
        billableFilter: BillableFilter.billableOnly,
      );
      expect(result.map((e) => e.id), ['e1']);
    });

    test('nonBillableOnly uses the project billable flag when no override is set', () {
      final entries = [
        _entry(
          id: 'e1',
          projectId: 'p1',
          startAt: DateTime.utc(2026, 7, 7, 9),
          endAt: DateTime.utc(2026, 7, 7, 10),
        ),
        _entry(
          id: 'e2',
          projectId: 'p2',
          startAt: DateTime.utc(2026, 7, 7, 9),
          endAt: DateTime.utc(2026, 7, 7, 10),
        ),
      ];
      final result = filterEntries(
        entries,
        projects,
        projectIds: {},
        billableFilter: BillableFilter.nonBillableOnly,
      );
      expect(result.map((e) => e.id), ['e2']);
    });

    test('billableOverride takes precedence over the project billable flag', () {
      final entries = [
        // Billable project, but this entry overrides to non-billable.
        _entry(
          id: 'e1',
          projectId: 'p1',
          startAt: DateTime.utc(2026, 7, 7, 9),
          endAt: DateTime.utc(2026, 7, 7, 10),
          billableOverride: false,
        ),
        // Non-billable project, but this entry overrides to billable.
        _entry(
          id: 'e2',
          projectId: 'p2',
          startAt: DateTime.utc(2026, 7, 7, 9),
          endAt: DateTime.utc(2026, 7, 7, 10),
          billableOverride: true,
        ),
      ];
      final billableOnly = filterEntries(
        entries,
        projects,
        projectIds: {},
        billableFilter: BillableFilter.billableOnly,
      );
      expect(billableOnly.map((e) => e.id), ['e2']);
      final nonBillableOnly = filterEntries(
        entries,
        projects,
        projectIds: {},
        billableFilter: BillableFilter.nonBillableOnly,
      );
      expect(nonBillableOnly.map((e) => e.id), ['e1']);
    });

    test('combines project and billable filters', () {
      final entries = [
        _entry(
          id: 'e1',
          projectId: 'p1',
          startAt: DateTime.utc(2026, 7, 7, 9),
          endAt: DateTime.utc(2026, 7, 7, 10),
        ),
        _entry(
          id: 'e2',
          projectId: 'p1',
          startAt: DateTime.utc(2026, 7, 7, 9),
          endAt: DateTime.utc(2026, 7, 7, 10),
          billableOverride: false,
        ),
      ];
      final result = filterEntries(
        entries,
        projects,
        projectIds: {'p1'},
        billableFilter: BillableFilter.billableOnly,
      );
      expect(result.map((e) => e.id), ['e1']);
    });
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/reports/report_calculations_test.dart`
Expected: FAIL — `filterEntries` is undefined.

- [ ] **Step 3: Implement `filterEntries`**

In `lib/features/reports/report_calculations.dart`, add the import:

```dart
import 'report_view_state.dart';
```

and append this function at the end of the file:

```dart
/// Narrows [entries] to those matching [projectIds] (empty = no
/// restriction) and [billableFilter]. Effective billable status is
/// [TimeEntry.billableOverride] when set, else the entry's project's
/// [Project.billable] (false if the entry has no project). Pure, no
/// DB/Flutter dependency -- same testing shape as [totalsByProject].
List<TimeEntry> filterEntries(
  List<TimeEntry> entries,
  List<Project> projects, {
  required Set<String> projectIds,
  required BillableFilter billableFilter,
}) {
  if (projectIds.isEmpty && billableFilter == BillableFilter.all) return entries;
  final projectsById = {for (final p in projects) p.id: p};
  return entries.where((entry) {
    if (projectIds.isNotEmpty && !projectIds.contains(entry.projectId)) return false;
    if (billableFilter == BillableFilter.all) return true;
    final effectiveBillable =
        entry.billableOverride ?? projectsById[entry.projectId]?.billable ?? false;
    return billableFilter == BillableFilter.billableOnly ? effectiveBillable : !effectiveBillable;
  }).toList();
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/reports/report_calculations_test.dart`
Expected: PASS (all existing `totalsByProject`/`totalsByDay` tests plus 6 new `filterEntries` tests)

- [ ] **Step 5: Commit**

```bash
git add lib/features/reports/report_calculations.dart test/features/reports/report_calculations_test.dart
git commit -m "feat(reports): add filterEntries for project and billable filtering"
```

---

## Task 6: Convert `reportEntriesProvider` to a range-keyed family, drop `reportRangeProvider`

**Files:**
- Modify: `lib/features/reports/reports_providers.dart`

**Interfaces:**
- Produces: `reportEntriesProvider` becomes `StreamProvider.family<List<TimeEntry>, DateTimeRange>`, invoked as `reportEntriesProvider(range)`. `reportRangeProvider` is removed. Consumed by Task 9.
- Note: this keeps `reports_providers.dart` independent of `report_view_controller.dart` (which itself imports `reports_providers.dart` for `ReportRangePreset`) — avoiding a circular import. The screen supplies the resolved range from `ReportViewController`'s state as the family argument instead.

- [ ] **Step 1: Change the provider**

In `lib/features/reports/reports_providers.dart`, remove the `flutter_riverpod/legacy.dart` import and its comment, and replace `reportRangeProvider` + `reportEntriesProvider`. Change:

```dart
import 'package:flutter/material.dart' show DateTimeRange;
import 'package:flutter_riverpod/flutter_riverpod.dart';
// StateProvider moved to this entry point in Riverpod 3.x; still the right
// tool for a single piece of simple, directly-settable UI state like the
// selected report date range.
import 'package:flutter_riverpod/legacy.dart';

import '../../core/di/database_provider.dart';
import '../../data/drift/database.dart';
```

to:

```dart
import 'package:flutter/material.dart' show DateTimeRange;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/database_provider.dart';
import '../../data/drift/database.dart';
```

And change:

```dart
final reportRangeProvider = StateProvider<DateTimeRange>(
  (ref) => rangeForPreset(ReportRangePreset.thisMonth),
);

final reportEntriesProvider = StreamProvider<List<TimeEntry>>((ref) {
  final range = ref.watch(reportRangeProvider);
  return ref
      .watch(appDatabaseProvider)
      .timeEntriesDao
      .watchEntriesInRange(range.start.toUtc(), range.end.toUtc());
});
```

to:

```dart
final reportEntriesProvider = StreamProvider.family<List<TimeEntry>, DateTimeRange>(
  (ref, range) {
    return ref
        .watch(appDatabaseProvider)
        .timeEntriesDao
        .watchEntriesInRange(range.start.toUtc(), range.end.toUtc());
  },
);
```

(leave `reportProjectsProvider` below it untouched).

- [ ] **Step 2: Verify the codebase still compiles**

Run: `flutter analyze lib/features/reports/reports_providers.dart`
Expected: errors in `reports_screen.dart` (still calling the old `reportRangeProvider`/`reportEntriesProvider` shape) — this is expected and fixed in Task 9. Confirm there are no errors reported *inside* `reports_providers.dart` itself.

- [ ] **Step 3: Commit**

```bash
git add lib/features/reports/reports_providers.dart
git commit -m "refactor(reports): key reportEntriesProvider by range instead of a StateProvider"
```

(`reports_screen.dart` is intentionally left broken until Task 9 — the working tree won't fully `flutter analyze` clean until then; this is a deliberate intermediate step so each provider/model change stays reviewable on its own. If your workflow requires green-at-every-commit, merge this task into Task 9 instead.)

---

## Task 7: Localization keys

**Files:**
- Modify: `lib/l10n/app_de.arb`, `lib/l10n/app_en.arb`, `lib/l10n/app_es.arb`, `lib/l10n/app_fr.arb`, `lib/l10n/app_it.arb`, `lib/l10n/app_nl.arb`

**Interfaces:**
- Produces: `l10n.reportsToday`, `l10n.reportsYesterday`, `l10n.reportsFilterTooltip`, `l10n.reportsFilterDialogTitle`, `l10n.reportsFilterProjectsLabel`, `l10n.reportsFilterProjectsHint`, `l10n.reportsFilterBillableLabel`, `l10n.reportsFilterBillableAll`, `l10n.reportsFilterBillableOnly`, `l10n.reportsFilterBillableNonOnly`, `l10n.reportsFilterReset`, `l10n.reportsEmptyFiltered`, `l10n.commonClose`. Consumed by Task 8 (dialog) and Task 9 (screen).

- [ ] **Step 1: Add keys to `app_de.arb`**

Find `"commonDelete": "Löschen",` and insert directly after it:

```json
  "commonClose": "Schließen",
```

Find `"reportsCustomRange": "Benutzerdefiniert…",` and insert directly after it:

```json
  "reportsToday": "Heute",
  "reportsYesterday": "Gestern",
```

Find `"reportsEmptyRange": "Keine Einträge in diesem Zeitraum.",` and insert directly after it:

```json
  "reportsEmptyFiltered": "Keine Einträge für diesen Zeitraum und diese Filter.",
  "reportsFilterTooltip": "Filter",
  "reportsFilterDialogTitle": "Filter",
  "reportsFilterProjectsLabel": "Projekte",
  "reportsFilterProjectsHint": "Keine Auswahl entspricht allen Projekten.",
  "reportsFilterBillableLabel": "Abrechenbar",
  "reportsFilterBillableAll": "Alle",
  "reportsFilterBillableOnly": "Nur abrechenbar",
  "reportsFilterBillableNonOnly": "Nur nicht abrechenbar",
  "reportsFilterReset": "Filter zurücksetzen",
```

- [ ] **Step 2: Add keys to `app_en.arb`**

After `"commonDelete": "Delete",`:

```json
  "commonClose": "Close",
```

After `"reportsCustomRange": "Custom…",`:

```json
  "reportsToday": "Today",
  "reportsYesterday": "Yesterday",
```

After `"reportsEmptyRange": "No entries in this period.",`:

```json
  "reportsEmptyFiltered": "No entries for this period and these filters.",
  "reportsFilterTooltip": "Filter",
  "reportsFilterDialogTitle": "Filter",
  "reportsFilterProjectsLabel": "Projects",
  "reportsFilterProjectsHint": "No selection means all projects.",
  "reportsFilterBillableLabel": "Billable",
  "reportsFilterBillableAll": "All",
  "reportsFilterBillableOnly": "Billable only",
  "reportsFilterBillableNonOnly": "Non-billable only",
  "reportsFilterReset": "Reset filters",
```

- [ ] **Step 3: Add keys to `app_es.arb`**

After `"commonDelete": "Eliminar",`:

```json
  "commonClose": "Cerrar",
```

After `"reportsCustomRange": "Personalizado…",`:

```json
  "reportsToday": "Hoy",
  "reportsYesterday": "Ayer",
```

After `"reportsEmptyRange": "No hay entradas en este período.",`:

```json
  "reportsEmptyFiltered": "No hay entradas para este período y estos filtros.",
  "reportsFilterTooltip": "Filtro",
  "reportsFilterDialogTitle": "Filtro",
  "reportsFilterProjectsLabel": "Proyectos",
  "reportsFilterProjectsHint": "Ninguna selección equivale a todos los proyectos.",
  "reportsFilterBillableLabel": "Facturable",
  "reportsFilterBillableAll": "Todo",
  "reportsFilterBillableOnly": "Solo facturable",
  "reportsFilterBillableNonOnly": "Solo no facturable",
  "reportsFilterReset": "Restablecer filtros",
```

- [ ] **Step 4: Add keys to `app_fr.arb`**

After `"commonDelete": "Supprimer",`:

```json
  "commonClose": "Fermer",
```

After `"reportsCustomRange": "Personnalisé…",`:

```json
  "reportsToday": "Aujourd'hui",
  "reportsYesterday": "Hier",
```

After `"reportsEmptyRange": "Aucune entrée sur cette période.",`:

```json
  "reportsEmptyFiltered": "Aucune entrée pour cette période et ces filtres.",
  "reportsFilterTooltip": "Filtre",
  "reportsFilterDialogTitle": "Filtre",
  "reportsFilterProjectsLabel": "Projets",
  "reportsFilterProjectsHint": "Aucune sélection équivaut à tous les projets.",
  "reportsFilterBillableLabel": "Facturable",
  "reportsFilterBillableAll": "Tout",
  "reportsFilterBillableOnly": "Facturable uniquement",
  "reportsFilterBillableNonOnly": "Non facturable uniquement",
  "reportsFilterReset": "Réinitialiser les filtres",
```

- [ ] **Step 5: Add keys to `app_it.arb`**

After `"commonDelete": "Elimina",`:

```json
  "commonClose": "Chiudi",
```

After `"reportsCustomRange": "Personalizzato…",`:

```json
  "reportsToday": "Oggi",
  "reportsYesterday": "Ieri",
```

After `"reportsEmptyRange": "Nessuna voce in questo periodo.",`:

```json
  "reportsEmptyFiltered": "Nessuna voce per questo periodo e questi filtri.",
  "reportsFilterTooltip": "Filtro",
  "reportsFilterDialogTitle": "Filtro",
  "reportsFilterProjectsLabel": "Progetti",
  "reportsFilterProjectsHint": "Nessuna selezione equivale a tutti i progetti.",
  "reportsFilterBillableLabel": "Fatturabile",
  "reportsFilterBillableAll": "Tutti",
  "reportsFilterBillableOnly": "Solo fatturabile",
  "reportsFilterBillableNonOnly": "Solo non fatturabile",
  "reportsFilterReset": "Reimposta filtri",
```

- [ ] **Step 6: Add keys to `app_nl.arb`**

After `"commonDelete": "Verwijderen",`:

```json
  "commonClose": "Sluiten",
```

After `"reportsCustomRange": "Aangepast…",`:

```json
  "reportsToday": "Vandaag",
  "reportsYesterday": "Gisteren",
```

After `"reportsEmptyRange": "Geen invoer in deze periode.",`:

```json
  "reportsEmptyFiltered": "Geen invoer voor deze periode en deze filters.",
  "reportsFilterTooltip": "Filter",
  "reportsFilterDialogTitle": "Filter",
  "reportsFilterProjectsLabel": "Projecten",
  "reportsFilterProjectsHint": "Geen selectie betekent alle projecten.",
  "reportsFilterBillableLabel": "Factureerbaar",
  "reportsFilterBillableAll": "Alles",
  "reportsFilterBillableOnly": "Alleen factureerbaar",
  "reportsFilterBillableNonOnly": "Alleen niet-factureerbaar",
  "reportsFilterReset": "Filters resetten",
```

- [ ] **Step 7: Regenerate localization delegates**

Run: `flutter gen-l10n`
Expected: completes without error, regenerates `lib/l10n/app_localizations*.dart` with the new getters.

- [ ] **Step 8: Verify ARB parity**

Run: `flutter test test/l10n/arb_completeness_test.dart`
Expected: PASS

- [ ] **Step 9: Commit**

```bash
git add lib/l10n/
git commit -m "feat(reports): add i18n keys for report filters and presets"
```

---

## Task 8: `ReportFilterDialog` widget

**Files:**
- Create: `lib/features/reports/report_filter_dialog.dart`

**Interfaces:**
- Consumes: `reportViewControllerProvider` (Task 4), `BillableFilter` (Task 2), `Project` (drift).
- Produces: `class ReportFilterDialog extends ConsumerWidget { const ReportFilterDialog({super.key, required List<Project> projects}); }`. Consumed by Task 9.

No dedicated test for this file — its behavior is covered end-to-end by Task 10's `reports_screen_test.dart` (matches this codebase's convention of not unit-testing thin dialog widgets in isolation, e.g. `project_form_dialog.dart` has no standalone widget-construction test either, only the screen that opens it is tested).

- [ ] **Step 1: Create the dialog**

Create `lib/features/reports/report_filter_dialog.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/drift/database.dart';
import '../../l10n/app_localizations.dart';
import 'report_view_controller.dart';
import 'report_view_state.dart';

/// Live filter panel for the Reports screen: project multi-select and a
/// billable/non-billable choice, both applied immediately through
/// [ReportViewController] as the user toggles them (no separate Apply step,
/// matching how the range presets already behave). [projects] is passed in
/// by the caller (already loaded via reportProjectsProvider) rather than
/// re-fetched here.
class ReportFilterDialog extends ConsumerWidget {
  const ReportFilterDialog({super.key, required this.projects});

  final List<Project> projects;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final viewState = ref.watch(reportViewControllerProvider).value;
    final controller = ref.read(reportViewControllerProvider.notifier);
    final selectedProjectIds = viewState?.projectIds ?? const <String>{};
    final billableFilter = viewState?.billableFilter ?? BillableFilter.all;

    return AlertDialog(
      title: Text(l10n.reportsFilterDialogTitle),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.reportsFilterProjectsLabel, style: Theme.of(context).textTheme.titleSmall),
              Text(l10n.reportsFilterProjectsHint, style: Theme.of(context).textTheme.bodySmall),
              ...projects.map(
                (project) => CheckboxListTile(
                  dense: true,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: selectedProjectIds.contains(project.id),
                  title: Row(
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(
                          color: Color(int.parse(project.colorHex.replaceFirst('#', '0xFF'))),
                          shape: BoxShape.circle,
                        ),
                      ),
                      Expanded(child: Text(project.name)),
                    ],
                  ),
                  onChanged: (checked) {
                    final next = Set<String>.from(selectedProjectIds);
                    if (checked ?? false) {
                      next.add(project.id);
                    } else {
                      next.remove(project.id);
                    }
                    controller.setProjectIds(next);
                  },
                ),
              ),
              const SizedBox(height: 16),
              Text(
                l10n.reportsFilterBillableLabel,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: Text(l10n.reportsFilterBillableAll),
                    selected: billableFilter == BillableFilter.all,
                    onSelected: (_) => controller.setBillableFilter(BillableFilter.all),
                  ),
                  ChoiceChip(
                    label: Text(l10n.reportsFilterBillableOnly),
                    selected: billableFilter == BillableFilter.billableOnly,
                    onSelected: (_) => controller.setBillableFilter(BillableFilter.billableOnly),
                  ),
                  ChoiceChip(
                    label: Text(l10n.reportsFilterBillableNonOnly),
                    selected: billableFilter == BillableFilter.nonBillableOnly,
                    onSelected: (_) =>
                        controller.setBillableFilter(BillableFilter.nonBillableOnly),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => controller.resetFilters(),
          child: Text(l10n.reportsFilterReset),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonClose),
        ),
      ],
    );
  }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `flutter analyze lib/features/reports/report_filter_dialog.dart`
Expected: no errors reported inside this file (unrelated pre-existing errors in `reports_screen.dart` from Task 6 are expected until Task 9).

- [ ] **Step 3: Commit**

```bash
git add lib/features/reports/report_filter_dialog.dart
git commit -m "feat(reports): add ReportFilterDialog"
```

---

## Task 9: Wire `ReportsScreen`

**Files:**
- Modify: `lib/features/reports/reports_screen.dart` (full rewrite — the range/filter source of truth moves from local widget state to `ReportViewController`, so most of `build()` changes)

**Interfaces:**
- Consumes: `reportViewControllerProvider`, `ReportFilterDialog` (Task 8), `filterEntries` (Task 5), `reportEntriesProvider(range)` (Task 6), all new l10n keys (Task 7).

- [ ] **Step 1: Replace the file**

Replace the full contents of `lib/features/reports/reports_screen.dart` with:

```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/app_settings_provider.dart';
import '../../core/format/date_format.dart';
import '../../core/format/duration_format.dart';
import '../../core/theme/hickory_colors.dart';
import '../../data/drift/database.dart';
import '../../l10n/app_localizations.dart';
import 'csv_export.dart';
import 'report_calculations.dart';
import 'report_filter_dialog.dart';
import 'report_view_controller.dart';
import 'report_view_state.dart';
import 'reports_providers.dart';

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  String? _exportStatus;

  Future<void> _selectCustomRange(DateTimeRange currentRange) async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 1),
      initialDateRange: currentRange,
    );
    if (picked == null) return;
    // showDateRangePicker's end date is inclusive-at-midnight; our range end
    // is exclusive, so push it one day forward to include the whole day.
    final range = DateTimeRange(
      start: DateTime(picked.start.year, picked.start.month, picked.start.day),
      end: DateTime(
        picked.end.year,
        picked.end.month,
        picked.end.day,
      ).add(const Duration(days: 1)),
    );
    await ref.read(reportViewControllerProvider.notifier).setCustomRange(range);
  }

  Future<void> _exportCsv(List<TimeEntry> entries, List<Project> projects) async {
    final l10n = AppLocalizations.of(context);
    final settings = ref.read(appSettingsProvider).value;
    final csv = entriesToCsv(
      entries,
      projects,
      l10n: l10n,
      dateFormatStyle: settings.dateStyle,
      timeFormatStyle: settings.timeStyle,
    );
    final path = await FilePicker.saveFile(
      dialogTitle: l10n.reportsExportCsv,
      fileName: 'hickory-export.csv',
      type: FileType.custom,
      allowedExtensions: ['csv'],
      bytes: Uint8List.fromList(utf8.encode(csv)),
    );
    if (!mounted) return;
    setState(() => _exportStatus = path == null ? null : l10n.reportsExportedTo(path));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final viewAsync = ref.watch(reportViewControllerProvider);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.reportsTitle, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 12),
          Expanded(
            child: viewAsync.when(
              data: (viewState) => _ReportRangeAndBody(
                viewState: viewState,
                exportStatus: _exportStatus,
                onSelectCustomRange: () => _selectCustomRange(viewState.range),
                onExport: _exportCsv,
              ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text(l10n.reportsError(e.toString()))),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReportRangeAndBody extends ConsumerWidget {
  const _ReportRangeAndBody({
    required this.viewState,
    required this.exportStatus,
    required this.onSelectCustomRange,
    required this.onExport,
  });

  final ReportViewState viewState;
  final String? exportStatus;
  final VoidCallback onSelectCustomRange;
  final Future<void> Function(List<TimeEntry> entries, List<Project> projects) onExport;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final tokens = HickoryColors.of(context);
    final entriesAsync = ref.watch(reportEntriesProvider(viewState.range));
    final projectsAsync = ref.watch(reportProjectsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _presetChip(context, ref, l10n.reportsToday, ReportRangePreset.today, tokens),
                  _presetChip(
                    context,
                    ref,
                    l10n.reportsYesterday,
                    ReportRangePreset.yesterday,
                    tokens,
                  ),
                  _presetChip(
                    context,
                    ref,
                    l10n.reportsThisWeek,
                    ReportRangePreset.thisWeek,
                    tokens,
                  ),
                  _presetChip(
                    context,
                    ref,
                    l10n.reportsThisMonth,
                    ReportRangePreset.thisMonth,
                    tokens,
                  ),
                  _presetChip(
                    context,
                    ref,
                    l10n.reportsLast30Days,
                    ReportRangePreset.last30Days,
                    tokens,
                  ),
                  _presetChip(context, ref, l10n.reportsAll, ReportRangePreset.all, tokens),
                  ActionChip(label: Text(l10n.reportsCustomRange), onPressed: onSelectCustomRange),
                ],
              ),
            ),
            Badge(
              label: Text('${viewState.activeFilterCount}'),
              isLabelVisible: viewState.activeFilterCount > 0,
              child: IconButton(
                icon: const Icon(Icons.filter_list),
                tooltip: l10n.reportsFilterTooltip,
                onPressed: () {
                  final projects = projectsAsync.value;
                  if (projects == null) return;
                  showDialog<void>(
                    context: context,
                    builder: (_) => ReportFilterDialog(projects: projects),
                  );
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Expanded(
          child: entriesAsync.when(
            data: (entries) => projectsAsync.when(
              data: (projects) {
                final filtered = filterEntries(
                  entries,
                  projects,
                  projectIds: viewState.projectIds,
                  billableFilter: viewState.billableFilter,
                );
                return _ReportBody(
                  entries: filtered,
                  projects: projects,
                  hasActiveFilters: viewState.activeFilterCount > 0,
                  onExport: () => onExport(filtered, projects),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text(l10n.reportsError(e.toString()))),
            ),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text(l10n.reportsError(e.toString()))),
          ),
        ),
        if (exportStatus != null) ...[
          const SizedBox(height: 8),
          Text(exportStatus!, style: Theme.of(context).textTheme.bodySmall),
        ],
      ],
    );
  }

  Widget _presetChip(
    BuildContext context,
    WidgetRef ref,
    String label,
    ReportRangePreset preset,
    HickoryColors tokens,
  ) {
    final selected = viewState.preset == preset;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      selectedColor: tokens.navActiveIcon.withValues(alpha: 0.22),
      onSelected: (_) => ref.read(reportViewControllerProvider.notifier).setPreset(preset),
    );
  }
}

class _ReportBody extends StatelessWidget {
  const _ReportBody({
    required this.entries,
    required this.projects,
    required this.hasActiveFilters,
    required this.onExport,
  });

  final List<TimeEntry> entries;
  final List<Project> projects;
  final bool hasActiveFilters;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final totals = totalsByProject(entries, projects, noProjectLabel: l10n.commonNoProject);
    final totalDuration = totals.fold<Duration>(Duration.zero, (sum, t) => sum + t.duration);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              l10n.reportsTotal(formatDuration(totalDuration)),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            FilledButton.icon(
              onPressed: entries.isEmpty ? null : onExport,
              icon: const Icon(Icons.download),
              label: Text(l10n.reportsExportCsv),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: totals.isEmpty
              ? Center(
                  child: Text(
                    hasActiveFilters ? l10n.reportsEmptyFiltered : l10n.reportsEmptyRange,
                  ),
                )
              : ListView.builder(
                  itemCount: totals.length,
                  itemBuilder: (context, index) {
                    final total = totals[index];
                    final amount = total.amountCents == null
                        ? null
                        : '${(total.amountCents! / 100).toStringAsFixed(2)} ${total.currency ?? ''}';
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      shape: const StadiumBorder(),
                      child: ListTile(
                        shape: const StadiumBorder(),
                        title: Text(total.projectName),
                        subtitle: amount == null ? null : Text(amount),
                        trailing: Text(formatDuration(total.duration)),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
```

- [ ] **Step 2: Verify the feature compiles clean**

Run: `flutter analyze lib/features/reports/`
Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add lib/features/reports/reports_screen.dart
git commit -m "feat(reports): wire ReportsScreen to ReportViewController and add filter UI"
```

---

## Task 10: `reports_screen_test.dart`

**Files:**
- Create: `test/features/reports/reports_screen_test.dart`

**Interfaces:**
- Consumes: everything from Tasks 1–9.

- [ ] **Step 1: Write the test**

Create `test/features/reports/reports_screen_test.dart`:

```dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/core/theme/app_theme.dart';
import 'package:hickory/data/drift/database.dart';
import 'package:hickory/features/reports/report_view_controller.dart';
import 'package:hickory/features/reports/report_view_state_store.dart';
import 'package:hickory/features/reports/reports_providers.dart';
import 'package:hickory/features/reports/reports_screen.dart';
import 'package:hickory/l10n/app_localizations.dart';

Project _project({required String id, required String name, bool billable = true}) {
  final now = DateTime.utc(2026, 1, 1);
  return Project(
    id: id,
    name: name,
    colorHex: '#5B8DEF',
    archived: false,
    billable: billable,
    hourlyRateCents: null,
    currency: null,
    createdAt: now,
    updatedAt: now,
  );
}

TimeEntry _entry({required String id, String? projectId}) {
  final now = DateTime.utc(2026, 8, 7, 9);
  return TimeEntry(
    id: id,
    projectId: projectId,
    description: null,
    startAt: now,
    endAt: now.add(const Duration(hours: 1)),
    pausedAt: null,
    totalPausedSeconds: 0,
    billableOverride: null,
    source: 'manual',
    deviceId: 'device-1',
    jiraTicketKey: null,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  late Directory tempDir;

  setUp(() => tempDir = Directory.systemTemp.createTempSync('reports_screen_test_'));
  tearDown(() => tempDir.deleteSync(recursive: true));

  final projectA = _project(id: 'p1', name: 'Project A');
  final projectB = _project(id: 'p2', name: 'Project B', billable: false);
  final entries = [
    _entry(id: 'e1', projectId: 'p1'),
    _entry(id: 'e2', projectId: 'p2'),
  ];

  // Same static-override pattern used throughout this codebase's other
  // widget tests (see timer_screen_test.dart) to avoid subscribing to a
  // live drift-backed StreamProvider, which hits a known flutter_test false
  // positive at teardown (flutter/flutter#144472).
  // reportViewStateStoreProvider is left live (real file IO against tempDir,
  // not drift) so the test exercises real ReportViewController wiring, same
  // as language_dropdown_test.dart.
  Widget makeApp() => ProviderScope(
        overrides: [
          reportEntriesProvider.overrideWith((ref, range) => Stream.value(entries)),
          reportProjectsProvider.overrideWith((ref) => Stream.value([projectA, projectB])),
          reportViewStateStoreProvider.overrideWith(
            (ref) async => ReportViewStateStore(supportDirectory: tempDir),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: const Scaffold(body: ReportsScreen()),
        ),
      );

  // ReportViewController.build() does a real dart:io file read, which can't
  // complete inside testWidgets' fake-async zone on its own -- same issue
  // and same fix as language_dropdown_test.dart's pumpRealIo.
  Future<void> pumpRealIo(WidgetTester tester) async {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump();
  }

  Future<void> pumpUntilReady(WidgetTester tester) async {
    for (var i = 0; i < 50 && find.byIcon(Icons.filter_list).evaluate().isEmpty; i++) {
      await pumpRealIo(tester);
    }
  }

  testWidgets('shows Today/Yesterday presets and both projects with no filter active', (
    tester,
  ) async {
    await tester.pumpWidget(makeApp());
    await pumpUntilReady(tester);

    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Yesterday'), findsOneWidget);
    expect(find.text('Project A'), findsOneWidget);
    expect(find.text('Project B'), findsOneWidget);
  });

  testWidgets('tapping Today selects it and deselects This month', (tester) async {
    await tester.pumpWidget(makeApp());
    await pumpUntilReady(tester);

    final thisMonthBefore = tester.widget<ChoiceChip>(
      find.ancestor(of: find.text('This month'), matching: find.byType(ChoiceChip)),
    );
    expect(thisMonthBefore.selected, isTrue);

    await tester.tap(find.text('Today'));
    await tester.pumpAndSettle();

    final todayAfter = tester.widget<ChoiceChip>(
      find.ancestor(of: find.text('Today'), matching: find.byType(ChoiceChip)),
    );
    final thisMonthAfter = tester.widget<ChoiceChip>(
      find.ancestor(of: find.text('This month'), matching: find.byType(ChoiceChip)),
    );
    expect(todayAfter.selected, isTrue);
    expect(thisMonthAfter.selected, isFalse);
  });

  testWidgets(
    'filtering to one project narrows the list, and a further billable filter reaches '
    'the filtered empty state',
    (tester) async {
      await tester.pumpWidget(makeApp());
      await pumpUntilReady(tester);

      await tester.tap(find.byIcon(Icons.filter_list));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(CheckboxListTile, 'Project A'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      expect(find.text('Project A'), findsOneWidget);
      expect(find.text('Project B'), findsNothing);

      // Project A is billable, so filtering to non-billable-only on top of
      // the project filter leaves no matching entries.
      await tester.tap(find.byIcon(Icons.filter_list));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Non-billable only'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      expect(find.text('No entries for this period and these filters.'), findsOneWidget);
    },
  );

  testWidgets('Reset filters clears the project and billable selection', (tester) async {
    await tester.pumpWidget(makeApp());
    await pumpUntilReady(tester);

    await tester.tap(find.byIcon(Icons.filter_list));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CheckboxListTile, 'Project A'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reset filters'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    expect(find.text('Project A'), findsOneWidget);
    expect(find.text('Project B'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run the test**

Run: `flutter test test/features/reports/reports_screen_test.dart`
Expected: PASS (4 tests)

- [ ] **Step 3: Commit**

```bash
git add test/features/reports/reports_screen_test.dart
git commit -m "test(reports): add ReportsScreen filter and preset widget tests"
```

---

## Task 11: Full verification pass

**Files:** none (verification only)

- [ ] **Step 1: Format**

Run: `dart format .`
Expected: no files need reformatting (or only newly-added files get formatted — re-check the diff if so, and fold any formatting-only changes into the relevant task's commit rather than leaving them stray).

- [ ] **Step 2: Analyze**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 3: Full test suite**

Run: `flutter test`
Expected: all tests pass, including the untouched suites (regression check).

- [ ] **Step 4: Manual smoke check (desktop)**

Run: `flutter run -d macos` (or `-d windows`) and in the running app: open Reports, confirm Today/Yesterday appear and narrow the total correctly against real data; open the filter dialog, check a project, confirm the list and CSV export both narrow; set a billable-only filter that yields no results and confirm the filtered empty message appears; quit and relaunch the app, open Reports again, and confirm the previously-selected range and filters are restored.

- [ ] **Step 5: Update the changelog**

In `CHANGELOG.md`, under `## [Unreleased]`, add an `### Added` section (create it if absent) with:

```markdown
- Add "Today" and "Yesterday" report presets, plus a combinable project and billable/non-billable filter that's remembered across restarts and respected by CSV export.
```

- [ ] **Step 6: Commit**

```bash
git add CHANGELOG.md
git commit -m "docs: note report filters and additional presets in the changelog"
```
