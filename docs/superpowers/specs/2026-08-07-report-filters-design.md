# Report Filters & Additional Presets — Design

Date: 2026-08-07
Status: Approved for planning

## 1. Goal & Scope

Reports currently offers four range presets (Diese Woche, Dieser Monat, Letzte 30 Tage,
Alle) plus a custom date-range picker, and shows totals grouped by project for whatever
range is selected — with no way to narrow the result set further, and no memory of the
last-used range across restarts.

This adds:

1. Two more range presets: **Heute** and **Gestern**.
2. A **filter** (Projekt-Mehrfachauswahl, Billable/Non-billable) combinable with the
   range, applied client-side against the already range-filtered entries.
3. **Device-local persistence** of the last-used range and filters, restored on the next
   Reports screen visit.
4. CSV export respects the active filters — it exports exactly what's on screen.

Out of scope (confirmed with user): filtering by **Client** or **Tag** — neither has any
assignment UI yet (`Clients`/`Tags`/`TimeEntryTags` are schema-only; no project has a
client picker, no entry has a tag picker), so filtering by them isn't meaningful yet.
Also out of scope: changing report grouping (stays "always by project"), new export
formats, quarter presets.

## 2. Behavior

### 2.1 Presets

`ReportRangePreset` gains `today` and `yesterday`. Display order:
Heute, Gestern, Diese Woche, Dieser Monat, Letzte 30 Tage, Alle, Benutzerdefiniert…
(unchanged chip style — `ChoiceChip`, single-select, matches the existing four).

### 2.2 Filters

A new filter icon button (`Icons.filter_list`) sits next to the preset row. Tapping it
opens `ReportFilterDialog`:

- **Projekte**: a scrollable checkbox list of every project (active *and* archived —
  reports look at history, and an archived project can still have entries in range).
  Empty selection means "all projects" (no explicit "select all" row needed).
- **Abrechenbar**: a 3-way choice (`Alle` / `Nur abrechenbar` / `Nur nicht abrechenbar`),
  same `ChoiceChip` row style as the presets.
- A `reportsFilterReset` action clears both back to defaults.
- Every control applies immediately (no separate Apply step, consistent with how preset
  chips already behave) via `ReportViewController`; the dialog has a single
  `commonClose` button (new common key — this dialog is a live filter panel, not a
  form with pending changes to cancel).

The filter button shows a small `Badge` (Material 3, no i18n needed — it's just a count)
with the number of active filter dimensions (0, 1, or 2) whenever it's `> 0`.

### 2.3 Persistence

Range (preset or custom start/end) and filters are saved to a per-device JSON file and
restored on the next time `ReportsScreen` builds. Deliberately **not** synced — this is a
UI viewing preference for this device, not data, same reasoning already applied to
`WindowBoundsStore` and `LocaleStore`.

### 2.4 CSV export

`_exportCsv` now receives the already-filtered entry list (range + project + billable),
so the exported CSV always matches what's currently on screen — no separate "export
everything" mode.

### 2.5 Empty state

`_ReportBody`'s empty message becomes filter-aware: `reportsEmptyRange` ("Keine Einträge
in diesem Zeitraum.") when no project/billable filter is active, `reportsEmptyFiltered`
("Keine Einträge für diesen Zeitraum und diese Filter.") when at least one is.

## 3. Data

### 3.1 `lib/features/reports/reports_providers.dart` — extend

```dart
enum ReportRangePreset { today, yesterday, thisWeek, thisMonth, last30Days, all }

enum BillableFilter { all, billableOnly, nonBillableOnly }

DateTimeRange rangeForPreset(ReportRangePreset preset, {DateTime? now}) {
  final today = _startOfDay(now ?? DateTime.now());
  switch (preset) {
    case ReportRangePreset.today:
      return DateTimeRange(start: today, end: today.add(const Duration(days: 1)));
    case ReportRangePreset.yesterday:
      final yesterday = today.subtract(const Duration(days: 1));
      return DateTimeRange(start: yesterday, end: today);
    // ...existing thisWeek / thisMonth / last30Days / all unchanged
  }
}
```

```dart
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

  // customRange is always set together with a null preset (see copyWith call
  // sites in setPreset/setCustomRange below), so the ! here reflects that
  // invariant rather than an unchecked assumption.
  DateTimeRange get range => preset == null ? customRange! : rangeForPreset(preset!);

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

`copyWith`'s function-wrapped nullable params follow the same "explicit null vs. leave
unchanged" shape already needed here (setting a custom range must be able to null out
`preset`, and vice versa) — plain `T?` params can't distinguish "don't change" from "set
to null".

### 3.2 `lib/features/reports/report_view_state_store.dart` (new)

Mirrors `WindowBoundsStore` exactly: JSON file in the app-support directory, directory
injected via constructor for testability.

```dart
class ReportViewStateStore {
  ReportViewStateStore({required this.supportDirectory});

  final Directory supportDirectory;

  File get _file => File(p.join(supportDirectory.path, 'report_view_state.json'));

  /// Returns the default state (this-month preset, no filters) if the file is
  /// missing, unreadable, or contains an unrecognized preset/filter value —
  /// same fall-back-to-defaults contract as WindowBoundsStore.read().
  Future<ReportViewState> read() async { /* jsonDecode, defensive parsing */ }

  Future<void> write(ReportViewState state) async { /* jsonEncode */ }
}
```

JSON shape: `{"preset": "thisMonth"|null, "customRangeStart"/"customRangeEnd":
ISO-8601|absent, "projectIds": [...], "billableFilter": "all"|"billableOnly"|
"nonBillableOnly"}`.

### 3.3 `ReportViewController` (same file as 3.1)

`AsyncNotifier<ReportViewState>`, `keepAlive: true` — same shape as `LocaleController`:

```dart
@Riverpod(keepAlive: true)
class ReportViewController extends _$ReportViewController {
  @override
  Future<ReportViewState> build() async {
    final store = await ref.watch(reportViewStateStoreProvider.future);
    return store.read();
  }

  Future<void> _update(ReportViewState Function(ReportViewState) update) async {
    final next = update(state.value ?? const ReportViewState());
    state = AsyncData(next); // state first, so UI reflects the change even if persisting fails
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
  Future<void> setBillableFilter(BillableFilter f) =>
      _update((s) => s.copyWith(billableFilter: f));
  Future<void> resetFilters() =>
      _update((s) => s.copyWith(projectIds: {}, billableFilter: BillableFilter.all));
}
```

`reportEntriesProvider` switches its range source from the old `reportRangeProvider`
(`StateProvider`, removed) to `ReportViewController`'s resolved `.range`. A new
`reportFilteredEntriesProvider` composes it with `reportProjectsProvider` and the
controller's `projectIds`/`billableFilter` through `filterEntries()` (3.4) — this is what
`ReportsScreen` actually watches and exports.

### 3.4 `lib/features/reports/report_calculations.dart` — new pure function

```dart
/// Narrows [entries] to those matching [projectIds] (empty = no restriction)
/// and [billableFilter]. Effective billable status is [TimeEntry.billableOverride]
/// when set, else the entry's project's [Project.billable] (false if the entry
/// has no project). Pure, no DB/Flutter dependency — same testing shape as
/// totalsByProject.
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
    return billableFilter == BillableFilter.billableOnly
        ? effectiveBillable
        : !effectiveBillable;
  }).toList();
}
```

## 4. UI (`lib/features/reports/reports_screen.dart`)

- Preset `Wrap` gains two more `_presetChip` calls for `today`/`yesterday`, placed first.
- New filter `IconButton` (wrapped in a `Badge`) next to the custom-range `ActionChip`,
  opens `showDialog` → new `report_filter_dialog.dart`'s `ReportFilterDialog` (takes the
  project list already available via `reportProjectsProvider` and reads/writes through
  `ReportViewController`).
- `build()` watches `reportViewControllerProvider` and, while it's loading (first frame,
  before the persisted file is read), shows the same `CircularProgressIndicator` already
  used for the entries/projects `AsyncValue`s — consistent loading treatment.
- `_selectPreset`/`_selectCustomRange` now call `ReportViewController.setPreset` /
  `.setCustomRange` instead of writing a local `StateProvider`; the `_selectedPreset`
  local field is removed in favor of reading the controller's current state directly
  (single source of truth, avoids the two getting out of sync).
- `_exportCsv` takes the filtered list (already computed once in `build()` for display)
  instead of re-deriving it.
- `_ReportBody`'s empty branch picks `reportsEmptyRange` vs. `reportsEmptyFiltered` based
  on whether `projectIds.isNotEmpty || billableFilter != BillableFilter.all`.

## 5. i18n

New ARB keys (all 6 locale files — `test/l10n/arb_completeness_test.dart` enforces
parity): `reportsToday`, `reportsYesterday`, `reportsFilterTooltip`,
`reportsFilterDialogTitle`, `reportsFilterProjectsLabel`, `reportsFilterProjectsHint`,
`reportsFilterBillableLabel`, `reportsFilterBillableAll`, `reportsFilterBillableOnly`,
`reportsFilterBillableNonOnly`, `reportsFilterReset`, `reportsEmptyFiltered`,
`commonClose` (new shared key — reused wherever a live-apply dialog needs a dismiss
action instead of `commonCancel`).

Reused as-is: `reportsThisWeek`, `reportsThisMonth`, `reportsLast30Days`, `reportsAll`,
`reportsCustomRange`, `reportsEmptyRange`.

## 6. Testing

- `test/features/reports/report_calculations_test.dart`: extend with `filterEntries`
  cases — empty filters is a passthrough; project-set filter excludes non-matching and
  no-project entries; billable-only/non-billable-only using both a project's own
  `billable` flag and an entry's `billableOverride` taking precedence over it; combined
  project + billable filter.
- `test/features/reports/reports_providers_test.dart` (new): `rangeForPreset` for
  `today`/`yesterday`; `ReportViewState.range` resolves correctly for both preset and
  custom-range states.
- `test/features/reports/report_view_state_store_test.dart` (new, mirrors
  `window_bounds_store_test.dart`): write-then-read round-trips a state with a preset,
  and separately one with a custom range and non-empty filters; read returns the default
  state for a missing or corrupt file; read falls back to the default preset when the
  file contains an unrecognized preset string (forward-compat if presets are ever
  renamed).
- `test/features/reports/reports_screen_test.dart` (new — first widget test for this
  screen, justified by the new interactive filter dialog): selecting "Heute" narrows the
  shown total; opening the filter dialog, checking a project, and closing it narrows the
  list to that project and updates the empty-state message when it produces no results;
  CSV export button remains wired to the filtered entries (asserted via the existing
  `csv_export.dart` pure function, not by inspecting a written file).

## 7. Out of Scope

Client and Tag filters (no assignment UI exists yet for either — separate future
features), adaptive grouping based on active filters (stays "always by project"), new
export formats, quarter/year presets, syncing report view preferences across devices.
