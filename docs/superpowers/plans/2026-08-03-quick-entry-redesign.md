# Quick Entry & Overview Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the manual-entry FAB with an always-visible quick-add bar on the Timer tab (duration-chip presets instead of two date+time pickers), make the presets user-configurable in Settings, and group the entries list by day with a per-day total.

**Architecture:** Two new pure-Dart modules (`quick_add_durations.dart`, `day_grouping.dart`) carry the testable logic; a new `QuickAddBar` widget and a modified `EntriesList` consume them. The existing full manual-entry dialog, its DAOs, and `SyncedWrites` are extended (not replaced) so editing and "other day" entry creation keep working unchanged.

**Tech Stack:** Flutter (desktop), Riverpod (plain top-level providers — this codebase avoids `@riverpod` codegen for anything touching drift-generated types, see `timer_providers.dart`), Drift/SQLite, `flutter gen-l10n` for the 6 supported locales (de/en/es/fr/it/nl; `app_de.arb` is the source template).

## Global Constraints

- Flutter 3.38+ / Dart 3.12+ (from `README.md`) — no new pub dependencies; every widget/helper below uses only packages already in `pubspec.yaml`.
- Every new user-facing string is added to **all six** ARB files (`lib/l10n/app_{de,en,es,fr,it,nl}.arb`) — never just the source locale.
- Feature-first structure: new files live under the feature directory they belong to (`lib/features/entries/`, `lib/features/settings/`), or `lib/core/format/` for cross-feature pure logic.
- Icon-only buttons get a `tooltip` (Flutter's `tooltip` param also sets the accessibility label).
- Commit messages follow Conventional Commits: `type(scope): imperative, lowercase, no period, <72 chars`.
- TDD: write the failing test, watch it fail, implement, watch it pass, then commit.

---

## Task 1: `AppSettings.quickAddDurationsMinutes` column + parse/format module

**Files:**
- Modify: `lib/data/drift/tables/app_settings_table.dart`
- Modify: `lib/data/drift/database.dart`
- Modify: `lib/data/drift/daos/app_settings_dao.dart`
- Modify: `lib/data/sync/synced_writes.dart`
- Modify: `test/data/drift/app_settings_dao_test.dart`
- Create: `lib/core/format/quick_add_durations.dart`
- Test: `test/core/format/quick_add_durations_test.dart`

**Interfaces:**
- Produces: `const defaultQuickAddDurationsMinutes = [15, 30, 45, 60]`; `List<int> parseQuickAddDurations(String? raw)`; `String formatQuickAddDurations(List<int> minutes)`; extension getter `AppSettingsRow?.quickAddDurations -> List<int>`; new field `AppSettingsRow.quickAddDurationsMinutes` (String, drift-generated); `AppSettingsDao.updateSettings({..., String? quickAddDurationsMinutes})`; `SyncedWrites.updateAppSettings({..., String? quickAddDurationsMinutes})`.
- Consumed by: Task 4 (`QuickAddBar`), Task 5 (settings editor).

**Note on ordering:** adding a required-by-default drift column changes the generated `AppSettingsRow` constructor everywhere it's called (`AppSettingsDao._defaultRow()`/`updateSettings()`). Steps 1–4 below do the schema change and that forced fix together as one atomic "keep the project compiling" unit — TDD proper (write pure-function tests first) starts at Step 5, once the project builds again. Step 13's DAO tests are written after Step 3's DAO fix (which the schema change already forced), so they're confirmation rather than a fail-first cycle; that's noted inline.

- [ ] **Step 1: Add the new column to the `AppSettings` table**

Edit `lib/data/drift/tables/app_settings_table.dart` — add a line after `timeFormat`:

```dart
  TextColumn get dateFormat => text().withDefault(const Constant('iso'))();
  TextColumn get timeFormat => text().withDefault(const Constant('24h'))();
  TextColumn get quickAddDurationsMinutes =>
      text().withDefault(const Constant('15,30,45,60'))();
  DateTimeColumn get updatedAt => dateTime()();
```

- [ ] **Step 2: Regenerate drift code**

Run: `dart run build_runner build --delete-conflicting-outputs`
Expected: succeeds; `lib/data/drift/database.g.dart` and `lib/data/drift/daos/app_settings_dao.g.dart` now include `quickAddDurationsMinutes`. `flutter analyze` at this point will report errors in `app_settings_dao.dart` (missing required constructor argument) — expected, fixed in the next step.

- [ ] **Step 3: Fix the DAO and bump the schema version**

The regenerated `AppSettingsRow` constructor now requires `quickAddDurationsMinutes`, so `AppSettingsDao` no longer compiles until it's updated. Edit `lib/data/drift/daos/app_settings_dao.dart`:

```dart
  Future<AppSettingsRow> updateSettings({
    String? dateFormat,
    String? timeFormat,
    String? quickAddDurationsMinutes,
  }) async {
    final current =
        await (select(appSettings)..where((s) => s.id.equals(appSettingsRowId))).getSingleOrNull() ??
            _defaultRow();
    final updated = AppSettingsRow(
      id: appSettingsRowId,
      dateFormat: dateFormat ?? current.dateFormat,
      timeFormat: timeFormat ?? current.timeFormat,
      quickAddDurationsMinutes: quickAddDurationsMinutes ?? current.quickAddDurationsMinutes,
      updatedAt: DateTime.now().toUtc(),
    );
    await into(appSettings).insertOnConflictUpdate(updated);
    return updated;
  }

  AppSettingsRow _defaultRow() => AppSettingsRow(
        id: appSettingsRowId,
        dateFormat: 'iso',
        timeFormat: '24h',
        quickAddDurationsMinutes: '15,30,45,60',
        updatedAt: DateTime.now().toUtc(),
      );
```

Edit `lib/data/drift/database.dart`:

```dart
  @override
  int get schemaVersion => 5;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.addColumn(timeEntries, timeEntries.pausedAt);
        await m.addColumn(timeEntries, timeEntries.totalPausedSeconds);
      }
      if (from < 3) {
        await m.createTable(appSettings);
      }
      if (from < 4) {
        await m.addColumn(timeEntries, timeEntries.jiraTicketKey);
        await m.createTable(jiraWorklogs);
      }
      if (from < 5) {
        await m.addColumn(appSettings, appSettings.quickAddDurationsMinutes);
      }
    },
  );
```

Edit `lib/data/sync/synced_writes.dart`:

```dart
  Future<AppSettingsRow> updateAppSettings({
    String? dateFormat,
    String? timeFormat,
    String? quickAddDurationsMinutes,
  }) async {
    final updated = await db.appSettingsDao.updateSettings(
      dateFormat: dateFormat,
      timeFormat: timeFormat,
      quickAddDurationsMinutes: quickAddDurationsMinutes,
    );
    await logWriter.appendEvent(
      entityType: EntityTypes.appSettings,
      entityId: appSettingsRowId,
      op: EventOp.update,
      payload: updated.toJson(),
    );
    return updated;
  }
```

- [ ] **Step 4: Confirm the project compiles again**

Run: `flutter analyze lib/data/`
Expected: no issues.

- [ ] **Step 5: Write the failing test for parse/format**

Create `test/core/format/quick_add_durations_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/core/format/quick_add_durations.dart';

void main() {
  test('parseQuickAddDurations returns the default list when raw is null', () {
    expect(parseQuickAddDurations(null), [15, 30, 45, 60]);
  });

  test('parseQuickAddDurations returns the default list when raw is empty', () {
    expect(parseQuickAddDurations(''), [15, 30, 45, 60]);
  });

  test('parseQuickAddDurations parses and sorts a comma-separated list', () {
    expect(parseQuickAddDurations('60,15,45'), [15, 45, 60]);
  });

  test('parseQuickAddDurations drops invalid and non-positive entries', () {
    expect(parseQuickAddDurations('15,abc,-5,0,30'), [15, 30]);
  });

  test('parseQuickAddDurations de-duplicates values', () {
    expect(parseQuickAddDurations('15,15,30'), [15, 30]);
  });

  test('parseQuickAddDurations falls back to defaults when nothing valid remains', () {
    expect(parseQuickAddDurations('abc,-5,0'), [15, 30, 45, 60]);
  });

  test('formatQuickAddDurations joins minutes with commas', () {
    expect(formatQuickAddDurations([15, 30, 45]), '15,30,45');
  });
}
```

- [ ] **Step 6: Run the test, verify it fails**

Run: `flutter test test/core/format/quick_add_durations_test.dart`
Expected: FAIL — `Error: Couldn't resolve the package 'hickory'` / target library not found (the module doesn't exist yet).

- [ ] **Step 7: Implement parse/format**

Create `lib/core/format/quick_add_durations.dart`:

```dart
/// Default presets shown as quick-add duration chips before the user
/// customizes them in Settings, and the fallback used whenever the stored
/// value is missing or unparseable.
const defaultQuickAddDurationsMinutes = [15, 30, 45, 60];

/// Parses the comma-separated minutes list stored in
/// `AppSettings.quickAddDurationsMinutes`. Invalid, non-positive, and
/// duplicate entries are dropped; falls back to
/// [defaultQuickAddDurationsMinutes] if nothing valid remains (including a
/// null/empty [raw]) so a corrupted value never breaks the quick-add bar.
List<int> parseQuickAddDurations(String? raw) {
  if (raw == null || raw.trim().isEmpty) return defaultQuickAddDurationsMinutes;
  final values = raw
      .split(',')
      .map((s) => int.tryParse(s.trim()))
      .where((v) => v != null && v > 0)
      .map((v) => v!)
      .toSet()
      .toList()
    ..sort();
  return values.isEmpty ? defaultQuickAddDurationsMinutes : values;
}

/// Inverse of [parseQuickAddDurations], for writing the setting back.
String formatQuickAddDurations(List<int> minutes) => minutes.join(',');
```

- [ ] **Step 8: Run the test, verify it passes**

Run: `flutter test test/core/format/quick_add_durations_test.dart`
Expected: PASS (7 tests).

- [ ] **Step 9: Write the failing test for the `AppSettingsRow` extension**

Append to `test/core/format/quick_add_durations_test.dart` (add import + two tests inside `main()`):

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/core/format/quick_add_durations.dart';
import 'package:hickory/data/drift/database.dart';

void main() {
  // ...existing tests above stay unchanged...

  test('quickAddDurations extension parses the settings row field', () {
    final row = AppSettingsRow(
      id: 'default',
      dateFormat: 'iso',
      timeFormat: '24h',
      quickAddDurationsMinutes: '20,40',
      updatedAt: DateTime.utc(2026, 1, 1),
    );
    expect(row.quickAddDurations, [20, 40]);
  });

  test('quickAddDurations extension falls back to defaults for a null row', () {
    const AppSettingsRow? row = null;
    expect(row.quickAddDurations, [15, 30, 45, 60]);
  });
}
```

- [ ] **Step 10: Run the test, verify it fails**

Run: `flutter test test/core/format/quick_add_durations_test.dart`
Expected: FAIL — `The getter 'quickAddDurations' isn't defined for the type 'AppSettingsRow'`.

- [ ] **Step 11: Implement the extension**

Append to `lib/core/format/quick_add_durations.dart`:

```dart
import '../../data/drift/database.dart' show AppSettingsRow;

extension AppSettingsQuickAddDurations on AppSettingsRow? {
  List<int> get quickAddDurations => parseQuickAddDurations(this?.quickAddDurationsMinutes);
}
```

(Put the `import` at the top of the file with the other imports — Dart requires imports before declarations.)

- [ ] **Step 12: Run the test, verify it passes**

Run: `flutter test test/core/format/quick_add_durations_test.dart`
Expected: PASS (9 tests).

- [ ] **Step 13: Write DAO tests for the new field**

Step 3 already implemented `updateSettings`/`_defaultRow` support for `quickAddDurationsMinutes` (forced by the schema change), so this step is confirmation rather than a fail-first cycle. Append to `test/data/drift/app_settings_dao_test.dart`, inside `main()`:

```dart
  test('watchSettings default row includes the default quick-add durations', () async {
    final settings = await db.appSettingsDao.watchSettings().first;
    expect(settings.quickAddDurationsMinutes, '15,30,45,60');
  });

  test('updateSettings updates quickAddDurationsMinutes independently of other fields', () async {
    final first = await db.appSettingsDao.updateSettings(quickAddDurationsMinutes: '10,20');
    expect(first.quickAddDurationsMinutes, '10,20');
    expect(first.dateFormat, 'iso');

    final second = await db.appSettingsDao.updateSettings(dateFormat: 'de');
    expect(second.quickAddDurationsMinutes, '10,20', reason: 'must not be reset by an unrelated update');
  });
```

- [ ] **Step 14: Run the DAO tests, verify they pass**

Run: `flutter test test/data/drift/app_settings_dao_test.dart`
Expected: PASS (5 tests total — the 3 existing plus the 2 new ones).

- [ ] **Step 15: Run the full test suite for touched files**

Run: `flutter test test/core/format/quick_add_durations_test.dart test/data/drift/app_settings_dao_test.dart`
Expected: PASS (all tests).

- [ ] **Step 16: Commit**

```bash
git add lib/data/drift/tables/app_settings_table.dart lib/data/drift/database.dart lib/data/drift/database.g.dart lib/data/drift/daos/app_settings_dao.dart lib/data/drift/daos/app_settings_dao.g.dart lib/data/sync/synced_writes.dart lib/core/format/quick_add_durations.dart test/core/format/quick_add_durations_test.dart test/data/drift/app_settings_dao_test.dart
git commit -m "feat(settings): add configurable quick-add duration presets"
```

---

## Task 2: Day-grouping pure module

**Files:**
- Create: `lib/features/entries/day_grouping.dart`
- Test: `test/features/entries/day_grouping_test.dart`

**Interfaces:**
- Consumes: `TimeEntry` (`hickory/data/drift/database.dart`), `TimeEntryDuration.workedDuration` (`hickory/data/drift/time_entry_extensions.dart`).
- Produces: `class EntryDayGroup { final DateTime day; final List<TimeEntry> entries; final Duration totalDuration; }`; `List<EntryDayGroup> groupEntriesByDay(List<TimeEntry> entries)`.
- Consumed by: Task 3 (`EntriesList`).

- [ ] **Step 1: Write the failing test**

Create `test/features/entries/day_grouping_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/data/drift/database.dart';
import 'package:hickory/features/entries/day_grouping.dart';

TimeEntry _entry({required String id, required DateTime startAt, required DateTime endAt}) {
  final now = DateTime.utc(2026, 1, 1);
  return TimeEntry(
    id: id,
    projectId: null,
    description: null,
    startAt: startAt,
    endAt: endAt,
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
  test('groups entries by local calendar day, most recent day first', () {
    final entries = [
      _entry(id: '1', startAt: DateTime(2026, 8, 1, 9), endAt: DateTime(2026, 8, 1, 10)),
      _entry(id: '2', startAt: DateTime(2026, 8, 2, 9), endAt: DateTime(2026, 8, 2, 11)),
    ];
    final groups = groupEntriesByDay(entries);
    expect(groups, hasLength(2));
    expect(groups[0].day, DateTime(2026, 8, 2));
    expect(groups[0].entries.single.id, '2');
    expect(groups[1].day, DateTime(2026, 8, 1));
    expect(groups[1].entries.single.id, '1');
  });

  test("sums workedDuration across a day's entries into totalDuration", () {
    final entries = [
      _entry(id: '1', startAt: DateTime(2026, 8, 1, 9), endAt: DateTime(2026, 8, 1, 10)),
      _entry(id: '2', startAt: DateTime(2026, 8, 1, 11), endAt: DateTime(2026, 8, 1, 11, 30)),
    ];
    final groups = groupEntriesByDay(entries);
    expect(groups, hasLength(1));
    expect(groups.single.totalDuration, const Duration(hours: 1, minutes: 30));
  });

  test('keeps multiple entries on the same day together and in input order', () {
    final entries = [
      _entry(id: 'a', startAt: DateTime(2026, 8, 1, 14), endAt: DateTime(2026, 8, 1, 15)),
      _entry(id: 'b', startAt: DateTime(2026, 8, 1, 9), endAt: DateTime(2026, 8, 1, 10)),
    ];
    final groups = groupEntriesByDay(entries);
    expect(groups.single.entries.map((e) => e.id), ['a', 'b']);
  });

  test('returns an empty list for no entries', () {
    expect(groupEntriesByDay(const []), isEmpty);
  });
}
```

- [ ] **Step 2: Run the test, verify it fails**

Run: `flutter test test/features/entries/day_grouping_test.dart`
Expected: FAIL — target library `hickory/features/entries/day_grouping.dart` doesn't exist.

- [ ] **Step 3: Implement**

Create `lib/features/entries/day_grouping.dart`:

```dart
import '../../data/drift/database.dart';
import '../../data/drift/time_entry_extensions.dart';

/// One calendar day's worth of entries for [EntriesList], with a
/// pre-summed [totalDuration] so the widget doesn't recompute it per frame.
class EntryDayGroup {
  const EntryDayGroup({required this.day, required this.entries, required this.totalDuration});

  /// Local midnight for this group's calendar day.
  final DateTime day;
  final List<TimeEntry> entries;
  final Duration totalDuration;
}

/// Groups [entries] by the local calendar day of [TimeEntry.startAt],
/// newest day first; entries within a day keep their input order. Each
/// group's [EntryDayGroup.totalDuration] is the sum of
/// [TimeEntryDuration.workedDuration] across that day's entries.
List<EntryDayGroup> groupEntriesByDay(List<TimeEntry> entries) {
  final entriesByDay = <DateTime, List<TimeEntry>>{};
  for (final entry in entries) {
    final local = entry.startAt.toLocal();
    final day = DateTime(local.year, local.month, local.day);
    entriesByDay.putIfAbsent(day, () => []).add(entry);
  }
  final sortedDays = entriesByDay.keys.toList()..sort((a, b) => b.compareTo(a));
  return [
    for (final day in sortedDays)
      EntryDayGroup(
        day: day,
        entries: entriesByDay[day]!,
        totalDuration: entriesByDay[day]!.fold(
          Duration.zero,
          (sum, entry) => sum + entry.workedDuration,
        ),
      ),
  ];
}
```

- [ ] **Step 4: Run the test, verify it passes**

Run: `flutter test test/features/entries/day_grouping_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/features/entries/day_grouping.dart test/features/entries/day_grouping_test.dart
git commit -m "feat(entries): add pure day-grouping logic for the entries list"
```

---

## Task 3: `EntriesList` renders day headers with totals

**Files:**
- Modify: `lib/features/entries/entries_list.dart`
- Modify: `lib/l10n/app_de.arb`, `lib/l10n/app_en.arb`, `lib/l10n/app_es.arb`, `lib/l10n/app_fr.arb`, `lib/l10n/app_it.arb`, `lib/l10n/app_nl.arb`
- Test: `test/features/entries/entries_list_test.dart`

**Interfaces:**
- Consumes: `groupEntriesByDay` (Task 2), `l10n.entriesToday`, `l10n.entriesYesterday`, `l10n.entriesDayHeader(String day, String total)`.

- [ ] **Step 1: Add the new l10n keys to all six ARB files**

In each of `lib/l10n/app_de.arb`, `app_en.arb`, `app_es.arb`, `app_fr.arb`, `app_it.arb`, `app_nl.arb`, insert the following lines immediately after the existing `"entriesEndBeforeStartError"` line (keep that line's trailing comma):

`app_de.arb`:
```json
  "entriesToday": "Heute",
  "entriesYesterday": "Gestern",
  "entriesDayHeader": "{day} · {total}",
  "@entriesDayHeader": {
    "placeholders": {
      "day": { "type": "String" },
      "total": { "type": "String" }
    }
  },
```

`app_en.arb`:
```json
  "entriesToday": "Today",
  "entriesYesterday": "Yesterday",
  "entriesDayHeader": "{day} · {total}",
  "@entriesDayHeader": {
    "placeholders": {
      "day": { "type": "String" },
      "total": { "type": "String" }
    }
  },
```

`app_es.arb`:
```json
  "entriesToday": "Hoy",
  "entriesYesterday": "Ayer",
  "entriesDayHeader": "{day} · {total}",
  "@entriesDayHeader": {
    "placeholders": {
      "day": { "type": "String" },
      "total": { "type": "String" }
    }
  },
```

`app_fr.arb`:
```json
  "entriesToday": "Aujourd'hui",
  "entriesYesterday": "Hier",
  "entriesDayHeader": "{day} · {total}",
  "@entriesDayHeader": {
    "placeholders": {
      "day": { "type": "String" },
      "total": { "type": "String" }
    }
  },
```

`app_it.arb`:
```json
  "entriesToday": "Oggi",
  "entriesYesterday": "Ieri",
  "entriesDayHeader": "{day} · {total}",
  "@entriesDayHeader": {
    "placeholders": {
      "day": { "type": "String" },
      "total": { "type": "String" }
    }
  },
```

`app_nl.arb`:
```json
  "entriesToday": "Vandaag",
  "entriesYesterday": "Gisteren",
  "entriesDayHeader": "{day} · {total}",
  "@entriesDayHeader": {
    "placeholders": {
      "day": { "type": "String" },
      "total": { "type": "String" }
    }
  },
```

- [ ] **Step 2: Regenerate localization code**

Run: `flutter gen-l10n`
Expected: succeeds; `lib/l10n/app_localizations*.dart` now expose `entriesToday`, `entriesYesterday`, `entriesDayHeader`.

- [ ] **Step 3: Write the failing widget test**

Create `test/features/entries/entries_list_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/core/di/app_settings_provider.dart';
import 'package:hickory/core/di/jira_providers.dart';
import 'package:hickory/data/drift/database.dart';
import 'package:hickory/features/entries/entries_list.dart';
import 'package:hickory/features/projects/projects_providers.dart';
import 'package:hickory/features/timer/timer_providers.dart';
import 'package:hickory/l10n/app_localizations.dart';

TimeEntry _entry({required String id, required DateTime startAt, required DateTime endAt}) {
  final now = DateTime.utc(2026, 1, 1);
  return TimeEntry(
    id: id,
    projectId: null,
    description: 'Entry $id',
    startAt: startAt,
    endAt: endAt,
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
  Widget makeApp(List<TimeEntry> entries) => ProviderScope(
        overrides: [
          allEntriesProvider.overrideWith((ref) => Stream.value(entries)),
          activeProjectsProvider.overrideWith((ref) => Stream.value(const [])),
          jiraWorklogsByEntryIdProvider.overrideWith((ref) => Stream.value(const {})),
          appSettingsProvider.overrideWith(
            (ref) => Stream.value(
              AppSettingsRow(
                id: 'default',
                dateFormat: 'iso',
                timeFormat: '24h',
                quickAddDurationsMinutes: '15,30,45,60',
                updatedAt: DateTime.utc(2026, 1, 1),
              ),
            ),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: const Scaffold(body: EntriesList()),
        ),
      );

  testWidgets('groups entries under Today/Yesterday headers with totals', (tester) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day, 9);
    final yesterday = today.subtract(const Duration(days: 1));
    await tester.pumpWidget(
      makeApp([
        _entry(id: '1', startAt: today, endAt: today.add(const Duration(hours: 1))),
        _entry(id: '2', startAt: yesterday, endAt: yesterday.add(const Duration(minutes: 30))),
      ]),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Today'), findsOneWidget);
    expect(find.textContaining('Yesterday'), findsOneWidget);
    expect(find.textContaining('01:00:00'), findsOneWidget);
    expect(find.textContaining('00:30:00'), findsOneWidget);
  });

  testWidgets('shows the empty state when there are no finished entries', (tester) async {
    await tester.pumpWidget(makeApp(const []));
    await tester.pumpAndSettle();
    expect(find.text('No entries yet.'), findsOneWidget);
  });
}
```

- [ ] **Step 4: Run the test, verify it fails**

Run: `flutter test test/features/entries/entries_list_test.dart`
Expected: FAIL — no `_entry`-day grouping headers are rendered yet (the current flat list has no "Today"/"Yesterday" text).

- [ ] **Step 5: Implement the grouped rendering**

Edit `lib/features/entries/entries_list.dart` — add an import and replace the `build` method plus add helper classes at the bottom of the file.

Add near the top, with the other imports:

```dart
import 'day_grouping.dart';
```

Replace the entire `build` method of `EntriesList` with:

```dart
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final entriesAsync = ref.watch(allEntriesProvider);
    final projectsAsync = ref.watch(activeProjectsProvider);
    final jiraWorklogsAsync = ref.watch(jiraWorklogsByEntryIdProvider);
    final settings = ref.watch(appSettingsProvider).value;
    final dateStyle = settings.dateStyle;
    final timeStyle = settings.timeStyle;

    return entriesAsync.when(
      data: (entries) {
        final finished = entries.where((e) => e.endAt != null).toList();
        if (finished.isEmpty) {
          return Center(child: Text(l10n.entriesEmpty));
        }
        final projectsById = {
          for (final p in projectsAsync.value ?? const <Project>[]) p.id: p,
        };
        final groups = groupEntriesByDay(finished);
        final rows = <_ListRow>[
          for (final group in groups) ...[
            _HeaderRow(group.day, group.totalDuration),
            for (final entry in group.entries) _EntryRow(entry),
          ],
        ];
        final localeName = Localizations.localeOf(context).languageCode;
        return ListView.builder(
          padding: const EdgeInsets.only(bottom: _bottomPaddingForFab),
          itemCount: rows.length,
          itemBuilder: (context, index) {
            final row = rows[index];
            if (row is _HeaderRow) {
              return _DayHeader(
                day: row.day,
                total: row.total,
                l10n: l10n,
                dateStyle: dateStyle,
                localeName: localeName,
              );
            }
            final entry = (row as _EntryRow).entry;
            final project = entry.projectId == null ? null : projectsById[entry.projectId];
            final jiraWorklog = jiraWorklogsAsync.value?[entry.id];
            final jiraStatusIcon = _jiraStatusIcon(l10n, entry.jiraTicketKey, jiraWorklog);
            final duration = entry.workedDuration;
            return Dismissible(
              key: ValueKey(entry.id),
              direction: DismissDirection.endToStart,
              background: Container(
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(999),
                ),
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: const Icon(Icons.delete_outline),
              ),
              onDismissed: (_) {
                ref.read(syncedWritesProvider.future).then((w) => w.deleteEntry(entry.id));
              },
              child: Card(
                margin: const EdgeInsets.only(bottom: 8),
                shape: const StadiumBorder(),
                child: ListTile(
                  shape: const StadiumBorder(),
                  leading: CircleAvatar(
                    backgroundColor: project != null
                        ? Color(int.parse(project.colorHex.replaceFirst('#', '0xFF')))
                        : Colors.grey,
                    radius: 8,
                    child: const SizedBox.shrink(),
                  ),
                  title: Text(entry.description?.isNotEmpty == true
                      ? entry.description!
                      : (project?.name ?? l10n.entriesNoDescription)),
                  subtitle: Text(
                    '${project?.name ?? l10n.commonNoProject} · '
                    '${formatDate(entry.startAt, dateStyle, localeName)} '
                    '${formatTime(entry.startAt, timeStyle)}',
                  ),
                  trailing: jiraStatusIcon == null
                      ? Text(formatDuration(duration))
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            jiraStatusIcon,
                            const SizedBox(width: 6),
                            Text(formatDuration(duration)),
                          ],
                        ),
                  onTap: () => showManualEntryDialog(context, ref, existing: entry),
                ),
              ),
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => Center(child: Text(l10n.entriesError(error.toString()))),
    );
  }
```

Add these private classes at the bottom of the file, after `_jiraStatusIcon`:

```dart
sealed class _ListRow {}

class _HeaderRow extends _ListRow {
  _HeaderRow(this.day, this.total);
  final DateTime day;
  final Duration total;
}

class _EntryRow extends _ListRow {
  _EntryRow(this.entry);
  final TimeEntry entry;
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({
    required this.day,
    required this.total,
    required this.l10n,
    required this.dateStyle,
    required this.localeName,
  });

  final DateTime day;
  final Duration total;
  final AppLocalizations l10n;
  final DateFormatStyle dateStyle;
  final String localeName;

  String _label() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (day == today) return l10n.entriesToday;
    final yesterday = today.subtract(const Duration(days: 1));
    if (day == yesterday) return l10n.entriesYesterday;
    return formatDate(day, dateStyle, localeName);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 8),
      child: Text(
        l10n.entriesDayHeader(_label(), formatDuration(total)),
        style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }
}
```

- [ ] **Step 6: Run the test, verify it passes**

Run: `flutter test test/features/entries/entries_list_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 7: Run static analysis**

Run: `flutter analyze lib/features/entries/entries_list.dart`
Expected: no issues.

- [ ] **Step 8: Commit**

```bash
git add lib/l10n/app_de.arb lib/l10n/app_en.arb lib/l10n/app_es.arb lib/l10n/app_fr.arb lib/l10n/app_it.arb lib/l10n/app_nl.arb lib/features/entries/entries_list.dart test/features/entries/entries_list_test.dart
git commit -m "feat(entries): group the entries list by day with a daily total"
```

---

## Task 4: `QuickAddBar` — replaces the FAB

**Files:**
- Modify: `lib/features/entries/manual_entry_dialog.dart`
- Create: `lib/features/entries/quick_add_bar.dart`
- Modify: `lib/features/timer/timer_screen.dart`
- Modify: `lib/features/shell/app_shell.dart`
- Modify: `lib/core/widgets/gradient_buttons.dart`
- Modify: `test/core/widgets/gradient_buttons_test.dart`
- Modify: `lib/l10n/app_de.arb`, `app_en.arb`, `app_es.arb`, `app_fr.arb`, `app_it.arb`, `app_nl.arb`
- Test: `test/features/entries/quick_add_bar_test.dart`

**Interfaces:**
- Consumes: `syncedWritesProvider`, `deviceIdProvider`, `activeProjectsProvider`, `appSettingsProvider`, `AppSettingsRow?.quickAddDurations` (Task 1), `JiraTicketField`, `showManualEntryDialog` (extended in Step 1 below).
- Produces: `class QuickAddBar extends ConsumerStatefulWidget` (`const QuickAddBar({super.key})`); `showManualEntryDialog(context, ref, {TimeEntry? existing, String? initialDescription, String? initialProjectId})`.

- [ ] **Step 1: Add prefill support to the existing manual-entry dialog**

Edit `lib/features/entries/manual_entry_dialog.dart` — replace the top-level function and the widget's constructor/state fields:

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

class _ManualEntryDialog extends ConsumerStatefulWidget {
  const _ManualEntryDialog({this.existing, this.initialDescription, this.initialProjectId});

  final TimeEntry? existing;
  final String? initialDescription;
  final String? initialProjectId;

  @override
  ConsumerState<_ManualEntryDialog> createState() => _ManualEntryDialogState();
}
```

Replace `initState`:

```dart
  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _descriptionController = TextEditingController(
      text: existing?.description ?? widget.initialDescription ?? '',
    );
    _startAt = existing?.startAt.toLocal() ?? DateTime.now().subtract(const Duration(hours: 1));
    _endAt = existing?.endAt?.toLocal() ?? DateTime.now();
    _projectId = existing?.projectId ?? widget.initialProjectId;
    _jiraTicketKey = existing?.jiraTicketKey;
  }
```

- [ ] **Step 2: Add the new l10n keys to all six ARB files**

Insert after the `entriesDayHeader`/`@entriesDayHeader` block added in Task 3 (same insertion point works in all six files):

`app_de.arb`:
```json
  "quickAddDurationChipLabel": "{minutes} Min",
  "@quickAddDurationChipLabel": {
    "placeholders": {
      "minutes": { "type": "int" }
    }
  },
  "quickAddJiraTooltip": "Jira-Ticket verknüpfen",
  "quickAddMoreTooltip": "Weitere Optionen",
  "quickAddSubmitTooltip": "Eintrag hinzufügen",
```

`app_en.arb`:
```json
  "quickAddDurationChipLabel": "{minutes} min",
  "@quickAddDurationChipLabel": {
    "placeholders": {
      "minutes": { "type": "int" }
    }
  },
  "quickAddJiraTooltip": "Link Jira ticket",
  "quickAddMoreTooltip": "More options",
  "quickAddSubmitTooltip": "Add entry",
```

`app_es.arb`:
```json
  "quickAddDurationChipLabel": "{minutes} min",
  "@quickAddDurationChipLabel": {
    "placeholders": {
      "minutes": { "type": "int" }
    }
  },
  "quickAddJiraTooltip": "Vincular ticket de Jira",
  "quickAddMoreTooltip": "Más opciones",
  "quickAddSubmitTooltip": "Añadir entrada",
```

`app_fr.arb`:
```json
  "quickAddDurationChipLabel": "{minutes} min",
  "@quickAddDurationChipLabel": {
    "placeholders": {
      "minutes": { "type": "int" }
    }
  },
  "quickAddJiraTooltip": "Lier un ticket Jira",
  "quickAddMoreTooltip": "Plus d'options",
  "quickAddSubmitTooltip": "Ajouter une entrée",
```

`app_it.arb`:
```json
  "quickAddDurationChipLabel": "{minutes} min",
  "@quickAddDurationChipLabel": {
    "placeholders": {
      "minutes": { "type": "int" }
    }
  },
  "quickAddJiraTooltip": "Collega ticket Jira",
  "quickAddMoreTooltip": "Altre opzioni",
  "quickAddSubmitTooltip": "Aggiungi voce",
```

`app_nl.arb`:
```json
  "quickAddDurationChipLabel": "{minutes} min",
  "@quickAddDurationChipLabel": {
    "placeholders": {
      "minutes": { "type": "int" }
    }
  },
  "quickAddJiraTooltip": "Jira-ticket koppelen",
  "quickAddMoreTooltip": "Meer opties",
  "quickAddSubmitTooltip": "Invoer toevoegen",
```

Run: `flutter gen-l10n`
Expected: succeeds.

- [ ] **Step 3: Write the failing widget test**

Create `test/features/entries/quick_add_bar_test.dart`:

```dart
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/core/di/database_provider.dart';
import 'package:hickory/core/di/device_id_provider.dart';
import 'package:hickory/core/di/sync_providers.dart';
import 'package:hickory/data/drift/database.dart';
import 'package:hickory/data/sync/sync_log_writer.dart';
import 'package:hickory/data/sync/synced_writes.dart';
import 'package:hickory/features/entries/entries_list.dart';
import 'package:hickory/features/entries/quick_add_bar.dart';
import 'package:hickory/l10n/app_localizations.dart';

Future<void> pumpUntilFound(WidgetTester tester, Finder finder, {int maxTries = 50}) async {
  for (var i = 0; i < maxTries; i++) {
    if (finder.evaluate().isNotEmpty) return;
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump();
  }
}

void main() {
  late AppDatabase db;
  late Directory syncRoot;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    syncRoot = Directory.systemTemp.createTempSync('hickory_quick_add_test_');
  });

  tearDown(() async {
    await db.close();
    if (syncRoot.existsSync()) syncRoot.deleteSync(recursive: true);
  });

  Widget makeApp() => ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          deviceIdProvider.overrideWith((ref) async => 'device-1'),
          syncedWritesProvider.overrideWith(
            (ref) async => SyncedWrites(
              db: db,
              logWriter: SyncLogWriter(syncRoot: syncRoot, deviceId: 'device-1'),
            ),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: const Scaffold(
            body: Column(children: [QuickAddBar(), Expanded(child: EntriesList())]),
          ),
        ),
      );

  testWidgets(
    'tapping a duration chip then submit creates an entry visible under Today',
    (tester) async {
      await tester.pumpWidget(makeApp());
      await tester.pumpAndSettle();

      expect(find.text('No entries yet.'), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, 'Standup');
      await tester.tap(find.text('30 min'));
      await tester.pump();
      await tester.tap(find.byTooltip('Add entry'));
      await tester.pump();
      await pumpUntilFound(tester, find.text('Standup'));

      expect(find.text('Standup'), findsOneWidget);
      expect(find.textContaining('Today'), findsOneWidget);
    },
  );

  testWidgets('tapping the Jira icon reveals the Jira ticket field', (tester) async {
    await tester.pumpWidget(makeApp());
    await tester.pumpAndSettle();

    expect(find.text('Jira ticket'), findsNothing);
    await tester.tap(find.byTooltip('Link Jira ticket'));
    await tester.pumpAndSettle();
    expect(find.text('Jira ticket'), findsOneWidget);
  });

  testWidgets(
    'tapping the more icon opens the full dialog prefilled with the current description',
    (tester) async {
      await tester.pumpWidget(makeApp());
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'Retro');
      await tester.tap(find.byTooltip('More options'));
      await tester.pumpAndSettle();

      expect(find.text('Manual entry'), findsOneWidget);
      expect(find.text('Retro'), findsWidgets);
    },
  );
}
```

- [ ] **Step 4: Run the test, verify it fails**

Run: `flutter test test/features/entries/quick_add_bar_test.dart`
Expected: FAIL — target library `hickory/features/entries/quick_add_bar.dart` doesn't exist.

- [ ] **Step 5: Implement `QuickAddBar`**

Create `lib/features/entries/quick_add_bar.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/app_settings_provider.dart';
import '../../core/di/device_id_provider.dart';
import '../../core/di/sync_providers.dart';
import '../../core/format/date_format.dart';
import '../../core/format/quick_add_durations.dart';
import '../../l10n/app_localizations.dart';
import '../jira/widgets/jira_ticket_field.dart';
import '../projects/projects_providers.dart';
import 'manual_entry_dialog.dart';

/// Pinned above [EntriesList] on the Timer tab; creates today's manual
/// entries in as few taps as possible (duration chips instead of the full
/// dialog's two date+time pickers). Replaces the old FAB — anything the bar
/// can't do (a different day, exact timestamps) is reached via its "more"
/// icon, which opens the existing full dialog prefilled with the bar's
/// current description/project. See
/// docs/superpowers/specs/2026-08-03-quick-entry-redesign-design.md.
class QuickAddBar extends ConsumerStatefulWidget {
  const QuickAddBar({super.key});

  @override
  ConsumerState<QuickAddBar> createState() => _QuickAddBarState();
}

class _QuickAddBarState extends ConsumerState<QuickAddBar> {
  final _descriptionController = TextEditingController();
  String? _projectId;
  String? _jiraTicketKey;
  bool _jiraExpanded = false;
  late DateTime _startAt;
  late DateTime _endAt;

  @override
  void initState() {
    super.initState();
    _resetTimeRange(const Duration(minutes: 30));
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  void _resetTimeRange(Duration duration) {
    final now = DateTime.now();
    _endAt = now;
    _startAt = now.subtract(duration);
  }

  void _applyDuration(int minutes) {
    setState(() => _resetTimeRange(Duration(minutes: minutes)));
  }

  Future<void> _pickTime({required bool isStart}) async {
    final initial = isStart ? _startAt : _endAt;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(initial));
    if (time == null || !mounted) return;
    final now = DateTime.now();
    final combined = DateTime(now.year, now.month, now.day, time.hour, time.minute);
    setState(() {
      if (isStart) {
        _startAt = combined;
      } else {
        _endAt = combined;
      }
    });
  }

  Future<void> _submit() async {
    if (_endAt.isBefore(_startAt)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).entriesEndBeforeStartError)),
      );
      return;
    }
    final deviceId = await ref.read(deviceIdProvider.future);
    final writes = await ref.read(syncedWritesProvider.future);
    final description = _descriptionController.text.trim().isEmpty
        ? null
        : _descriptionController.text.trim();
    await writes.createManualEntry(
      deviceId: deviceId,
      startAt: _startAt,
      endAt: _endAt,
      projectId: _projectId,
      description: description,
      jiraTicketKey: _jiraTicketKey,
    );
    if (!mounted) return;
    _descriptionController.clear();
    setState(() => _resetTimeRange(const Duration(minutes: 30)));
  }

  void _openFullDialog() {
    final description = _descriptionController.text.trim();
    showManualEntryDialog(
      context,
      ref,
      initialDescription: description.isEmpty ? null : description,
      initialProjectId: _projectId,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final projectsAsync = ref.watch(activeProjectsProvider);
    final settings = ref.watch(appSettingsProvider).value;
    final timeStyle = settings.timeStyle;
    final durations = settings.quickAddDurations;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _descriptionController,
                    decoration: InputDecoration(labelText: l10n.entriesDescriptionLabel, isDense: true),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 140,
                  child: projectsAsync.when(
                    data: (projects) => DropdownButtonFormField<String?>(
                      initialValue: _projectId,
                      isDense: true,
                      decoration: InputDecoration(labelText: l10n.entriesProjectLabel, isDense: true),
                      items: [
                        DropdownMenuItem<String?>(value: null, child: Text(l10n.commonNoProject)),
                        ...projects.map(
                          (p) => DropdownMenuItem<String?>(value: p.id, child: Text(p.name)),
                        ),
                      ],
                      onChanged: (value) => setState(() => _projectId = value),
                    ),
                    loading: () => const LinearProgressIndicator(),
                    error: (e, _) => Text(l10n.entriesError(e.toString())),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (final minutes in durations)
                  ActionChip(
                    label: Text(l10n.quickAddDurationChipLabel(minutes)),
                    onPressed: () => _applyDuration(minutes),
                  ),
                TextButton(
                  onPressed: () => _pickTime(isStart: true),
                  child: Text(formatTime(_startAt, timeStyle)),
                ),
                const Text('–'),
                TextButton(
                  onPressed: () => _pickTime(isStart: false),
                  child: Text(formatTime(_endAt, timeStyle)),
                ),
                IconButton(
                  tooltip: l10n.quickAddJiraTooltip,
                  onPressed: () => setState(() => _jiraExpanded = !_jiraExpanded),
                  icon: const Icon(Icons.confirmation_number_outlined),
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
            if (_jiraExpanded) ...[
              const SizedBox(height: 8),
              JiraTicketField(
                initialValue: _jiraTicketKey,
                onChanged: (value) => setState(() => _jiraTicketKey = value),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 6: Run the test, verify it passes**

Run: `flutter test test/features/entries/quick_add_bar_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 7: Wire the bar into `TimerScreen`**

Edit `lib/features/timer/timer_screen.dart` — add the import next to the other `entries` import:

```dart
import '../entries/entries_list.dart';
import '../entries/quick_add_bar.dart';
```

Replace this fragment of the `build` method:

```dart
          const SizedBox(height: 16),
          const Expanded(child: EntriesList()),
```

with:

```dart
          const SizedBox(height: 16),
          const QuickAddBar(),
          const SizedBox(height: 16),
          const Expanded(child: EntriesList()),
```

- [ ] **Step 8: Remove the FAB from `AppShell`**

Replace the entire contents of `lib/features/shell/app_shell.dart`:

```dart
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../reports/reports_screen.dart';
import '../settings/settings_screen.dart';
import '../sync/sync_screen.dart';
import '../timer/timer_screen.dart';
import 'nav_shell.dart';

/// Wires the real Timer/Reports/Sync/Settings screens into NavShell. This
/// is Hickory's app-level navigation root (used as MaterialApp.home in
/// lib/app.dart). Manual-entry creation lives in QuickAddBar (pinned to
/// the Timer tab), not a shell-level FAB — see
/// docs/superpowers/specs/2026-08-03-quick-entry-redesign-design.md.
class AppShell extends StatelessWidget {
  const AppShell({super.key});

  static List<NavigationDestination> _destinations(AppLocalizations l10n) => [
    NavigationDestination(
      icon: const Icon(Icons.timer_outlined),
      selectedIcon: const Icon(Icons.timer),
      label: l10n.navTimer,
    ),
    NavigationDestination(
      icon: const Icon(Icons.bar_chart_outlined),
      selectedIcon: const Icon(Icons.bar_chart),
      label: l10n.navReports,
    ),
    NavigationDestination(
      icon: const Icon(Icons.sync_outlined),
      selectedIcon: const Icon(Icons.sync),
      label: l10n.navSync,
    ),
    NavigationDestination(
      icon: const Icon(Icons.settings_outlined),
      selectedIcon: const Icon(Icons.settings),
      label: l10n.navSettings,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return NavShell(
      destinations: _destinations(l10n),
      children: const [TimerScreen(), ReportsScreen(), SyncScreen(), SettingsScreen()],
    );
  }
}
```

- [ ] **Step 9: Remove the now-unused `_bottomPaddingForFab` reservation from `EntriesList`**

Edit `lib/features/entries/entries_list.dart` — delete the constant and its doc comment:

```dart
/// Reserves space so the shell's floating action button (56px + margin)
/// never overlaps the last entry — caught during design review, when an
/// early mockup had the FAB sitting on top of list content.
const _bottomPaddingForFab = 88.0;
```

and remove its one usage, changing:

```dart
        return ListView.builder(
          padding: const EdgeInsets.only(bottom: _bottomPaddingForFab),
          itemCount: rows.length,
```

to:

```dart
        return ListView.builder(
          itemCount: rows.length,
```

- [ ] **Step 10: Remove the now-unused `GradientFab`**

Edit `lib/core/widgets/gradient_buttons.dart` — delete the `GradientFab` class (everything from its doc comment through its closing brace, i.e. from `/// A circular, gradient-filled floating action button` to the end of the file), leaving only `GradientPillButton`.

Edit `test/core/widgets/gradient_buttons_test.dart` — remove the `'GradientFab renders its icon and invokes onPressed'` test, leaving only the `GradientPillButton` test:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/core/widgets/gradient_buttons.dart';

void main() {
  testWidgets('GradientPillButton renders its label and invokes onPressed', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GradientPillButton(
            label: 'Stop',
            icon: Icons.stop,
            gradient: const [Color(0xFFB678FF), Color(0xFFFF6FA9)],
            foregroundColor: const Color(0xFF160A22),
            onPressed: () => tapped = true,
          ),
        ),
      ),
    );

    expect(find.text('Stop'), findsOneWidget);

    await tester.tap(find.text('Stop'));
    await tester.pump();

    expect(tapped, isTrue);
  });
}
```

- [ ] **Step 11: Run the full touched-area test suite**

Run: `flutter test test/features/entries/ test/core/widgets/gradient_buttons_test.dart`
Expected: PASS (all tests).

- [ ] **Step 12: Run static analysis on all touched files**

Run: `flutter analyze lib/features/entries/ lib/features/timer/timer_screen.dart lib/features/shell/app_shell.dart lib/core/widgets/gradient_buttons.dart`
Expected: no issues (in particular: no unused-import warnings on `app_shell.dart` now that `ConsumerWidget`, `HickoryColors`, `GradientFab`, and `showManualEntryDialog` are no longer referenced there).

- [ ] **Step 13: Commit**

```bash
git add lib/features/entries/manual_entry_dialog.dart lib/features/entries/quick_add_bar.dart lib/features/entries/entries_list.dart lib/features/timer/timer_screen.dart lib/features/shell/app_shell.dart lib/core/widgets/gradient_buttons.dart test/core/widgets/gradient_buttons_test.dart test/features/entries/quick_add_bar_test.dart lib/l10n/app_de.arb lib/l10n/app_en.arb lib/l10n/app_es.arb lib/l10n/app_fr.arb lib/l10n/app_it.arb lib/l10n/app_nl.arb
git commit -m "feat(timer): replace the manual-entry FAB with a quick-add bar"
```

---

## Task 5: Settings — configurable quick-add duration presets

**Files:**
- Create: `lib/features/settings/quick_add_durations_editor.dart`
- Modify: `lib/features/settings/settings_screen.dart`
- Modify: `lib/l10n/app_de.arb`, `app_en.arb`, `app_es.arb`, `app_fr.arb`, `app_it.arb`, `app_nl.arb`
- Test: `test/features/settings/quick_add_durations_editor_test.dart`

**Interfaces:**
- Consumes: `appSettingsProvider`, `syncedWritesProvider`, `AppSettingsRow?.quickAddDurations`, `parseQuickAddDurations`/`formatQuickAddDurations` (Task 1).
- Produces: `class QuickAddDurationsEditor extends ConsumerWidget` (`const QuickAddDurationsEditor({super.key})`).

- [ ] **Step 1: Add the new l10n keys to all six ARB files**

Insert after the `quickAddSubmitTooltip` line added in Task 4 (same insertion point in all six files):

`app_de.arb`:
```json
  "settingsQuickAddTitle": "Schnelleingabe",
  "settingsQuickAddDescription": "Diese Zeitdauern erscheinen als Schnellauswahl im Timer-Tab.",
  "settingsQuickAddAddTooltip": "Hinzufügen",
  "settingsQuickAddRemoveTooltip": "Entfernen",
  "settingsQuickAddNewDurationLabel": "Minuten",
```

`app_en.arb`:
```json
  "settingsQuickAddTitle": "Quick Add",
  "settingsQuickAddDescription": "These durations appear as quick-add buttons on the Timer tab.",
  "settingsQuickAddAddTooltip": "Add",
  "settingsQuickAddRemoveTooltip": "Remove",
  "settingsQuickAddNewDurationLabel": "Minutes",
```

`app_es.arb`:
```json
  "settingsQuickAddTitle": "Entrada rápida",
  "settingsQuickAddDescription": "Estas duraciones aparecen como botones de entrada rápida en la pestaña Timer.",
  "settingsQuickAddAddTooltip": "Añadir",
  "settingsQuickAddRemoveTooltip": "Eliminar",
  "settingsQuickAddNewDurationLabel": "Minutos",
```

`app_fr.arb`:
```json
  "settingsQuickAddTitle": "Ajout rapide",
  "settingsQuickAddDescription": "Ces durées apparaissent comme boutons d'ajout rapide dans l'onglet Minuteur.",
  "settingsQuickAddAddTooltip": "Ajouter",
  "settingsQuickAddRemoveTooltip": "Supprimer",
  "settingsQuickAddNewDurationLabel": "Minutes",
```

`app_it.arb`:
```json
  "settingsQuickAddTitle": "Aggiunta rapida",
  "settingsQuickAddDescription": "Queste durate compaiono come pulsanti di aggiunta rapida nella scheda Timer.",
  "settingsQuickAddAddTooltip": "Aggiungi",
  "settingsQuickAddRemoveTooltip": "Rimuovi",
  "settingsQuickAddNewDurationLabel": "Minuti",
```

`app_nl.arb`:
```json
  "settingsQuickAddTitle": "Snel toevoegen",
  "settingsQuickAddDescription": "Deze duren verschijnen als snelkeuzeknoppen op het tabblad Timer.",
  "settingsQuickAddAddTooltip": "Toevoegen",
  "settingsQuickAddRemoveTooltip": "Verwijderen",
  "settingsQuickAddNewDurationLabel": "Minuten",
```

Run: `flutter gen-l10n`
Expected: succeeds.

- [ ] **Step 2: Write the failing widget test**

Create `test/features/settings/quick_add_durations_editor_test.dart`:

```dart
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/core/di/database_provider.dart';
import 'package:hickory/core/di/device_id_provider.dart';
import 'package:hickory/core/di/sync_providers.dart';
import 'package:hickory/data/drift/database.dart';
import 'package:hickory/data/sync/sync_log_writer.dart';
import 'package:hickory/data/sync/synced_writes.dart';
import 'package:hickory/features/settings/quick_add_durations_editor.dart';
import 'package:hickory/l10n/app_localizations.dart';

Future<void> pumpUntilFound(WidgetTester tester, Finder finder, {int maxTries = 50}) async {
  for (var i = 0; i < maxTries; i++) {
    if (finder.evaluate().isNotEmpty) return;
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump();
  }
}

void main() {
  late AppDatabase db;
  late Directory syncRoot;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    syncRoot = Directory.systemTemp.createTempSync('hickory_quick_add_settings_test_');
  });

  tearDown(() async {
    await db.close();
    if (syncRoot.existsSync()) syncRoot.deleteSync(recursive: true);
  });

  Widget makeApp() => ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          deviceIdProvider.overrideWith((ref) async => 'device-1'),
          syncedWritesProvider.overrideWith(
            (ref) async => SyncedWrites(
              db: db,
              logWriter: SyncLogWriter(syncRoot: syncRoot, deviceId: 'device-1'),
            ),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: const Scaffold(body: QuickAddDurationsEditor()),
        ),
      );

  testWidgets('shows the default duration chips', (tester) async {
    await tester.pumpWidget(makeApp());
    await tester.pumpAndSettle();
    expect(find.text('15 min'), findsOneWidget);
    expect(find.text('30 min'), findsOneWidget);
    expect(find.text('45 min'), findsOneWidget);
    expect(find.text('60 min'), findsOneWidget);
  });

  testWidgets('removing a chip persists the updated list', (tester) async {
    await tester.pumpWidget(makeApp());
    await tester.pumpAndSettle();

    await tester.tap(find.descendant(
      of: find.widgetWithText(Chip, '30 min'),
      matching: find.byIcon(Icons.cancel),
    ));

    AppSettingsRow? settings;
    for (var i = 0; i < 50 && settings?.quickAddDurationsMinutes != '15,45,60'; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
      settings = await db.appSettingsDao.watchSettings().first;
    }

    expect(settings?.quickAddDurationsMinutes, '15,45,60');
    expect(find.text('30 min'), findsNothing);
  });

  testWidgets('adding a duration persists the updated list', (tester) async {
    await tester.pumpWidget(makeApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '90');
    await tester.tap(find.text('Save'));
    await tester.pump();
    await pumpUntilFound(tester, find.text('90 min'));

    expect(find.text('90 min'), findsOneWidget);
    final settings = await db.appSettingsDao.watchSettings().first;
    expect(settings.quickAddDurationsMinutes, '15,30,45,60,90');
  });
}
```

- [ ] **Step 3: Run the test, verify it fails**

Run: `flutter test test/features/settings/quick_add_durations_editor_test.dart`
Expected: FAIL — target library `hickory/features/settings/quick_add_durations_editor.dart` doesn't exist.

- [ ] **Step 4: Implement `QuickAddDurationsEditor`**

Create `lib/features/settings/quick_add_durations_editor.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/app_settings_provider.dart';
import '../../core/di/sync_providers.dart';
import '../../core/format/quick_add_durations.dart';
import '../../l10n/app_localizations.dart';

/// Settings-screen editor for the Timer tab's quick-add duration presets
/// (see QuickAddBar). Persists through the same synced AppSettings row as
/// date/time format, so the presets follow the user across devices.
class QuickAddDurationsEditor extends ConsumerWidget {
  const QuickAddDurationsEditor({super.key});

  Future<void> _remove(WidgetRef ref, List<int> current, int minutes) async {
    final updated = List<int>.from(current)..remove(minutes);
    final writes = await ref.read(syncedWritesProvider.future);
    await writes.updateAppSettings(quickAddDurationsMinutes: formatQuickAddDurations(updated));
  }

  Future<void> _add(BuildContext context, WidgetRef ref, List<int> current) async {
    final l10n = AppLocalizations.of(context);
    final controller = TextEditingController();
    final minutes = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.settingsQuickAddNewDurationLabel),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: InputDecoration(labelText: l10n.settingsQuickAddNewDurationLabel),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(l10n.commonCancel)),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(int.tryParse(controller.text.trim())),
            child: Text(l10n.commonSave),
          ),
        ],
      ),
    );
    if (minutes == null || minutes <= 0 || current.contains(minutes)) return;
    final updated = List<int>.from(current)..add(minutes);
    final writes = await ref.read(syncedWritesProvider.future);
    await writes.updateAppSettings(quickAddDurationsMinutes: formatQuickAddDurations(updated));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final settings = ref.watch(appSettingsProvider).value;
    final durations = settings.quickAddDurations;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.settingsQuickAddTitle, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(l10n.settingsQuickAddDescription, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final minutes in durations)
              Chip(
                label: Text(l10n.quickAddDurationChipLabel(minutes)),
                onDeleted: () => _remove(ref, durations, minutes),
                deleteButtonTooltipMessage: l10n.settingsQuickAddRemoveTooltip,
              ),
            ActionChip(
              avatar: const Icon(Icons.add, size: 18),
              label: Text(l10n.settingsQuickAddAddTooltip),
              onPressed: () => _add(context, ref, durations),
            ),
          ],
        ),
      ],
    );
  }
}
```

- [ ] **Step 5: Run the test, verify it passes**

Run: `flutter test test/features/settings/quick_add_durations_editor_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 6: Wire the editor into the Settings screen**

Edit `lib/features/settings/settings_screen.dart` — add the import:

```dart
import 'quick_add_durations_editor.dart';
```

Add a new `Card` after the existing date/time-format `Card`'s closing `SizedBox(height: 16)` — i.e. insert immediately before the final `],\n      ),\n    );\n  }\n}` of the `build` method's `Column`:

```dart
                  const SizedBox(height: 12),
                  const LanguageDropdown(),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: QuickAddDurationsEditor(),
            ),
          ),
        ],
      ),
    );
  }
}
```

(This replaces the previous ending, which was `const LanguageDropdown(),` followed directly by the closing `],\n              ),\n            ),\n          ),\n        ],\n      ),\n    );\n  }\n}` — the new `Card` is inserted between the existing date/time-format card and the end of the screen's `Column`.)

- [ ] **Step 7: Run static analysis**

Run: `flutter analyze lib/features/settings/`
Expected: no issues.

- [ ] **Step 8: Commit**

```bash
git add lib/features/settings/quick_add_durations_editor.dart lib/features/settings/settings_screen.dart test/features/settings/quick_add_durations_editor_test.dart lib/l10n/app_de.arb lib/l10n/app_en.arb lib/l10n/app_es.arb lib/l10n/app_fr.arb lib/l10n/app_it.arb lib/l10n/app_nl.arb
git commit -m "feat(settings): add quick-add duration presets editor"
```

---

## Final Verification

- [ ] Run the full suite: `flutter test`
- [ ] Run full analysis: `flutter analyze`
- [ ] Manually launch the app (`flutter run -d macos` or `-d windows`), confirm: the Timer tab shows the quick-add bar (no FAB), tapping a duration chip and the submit icon creates an entry that appears under a "Today · <total>" header, the Jira icon reveals the ticket field, the "more" icon opens the full dialog prefilled, and Settings → Quick Add lets you add/remove duration presets that immediately update the bar's chips.
