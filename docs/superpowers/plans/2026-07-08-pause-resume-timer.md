# Pause/Resume for the Running Timer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a running `TimeEntry` be paused and resumed any number of times before it's stopped, with all paused time correctly excluded from the displayed elapsed time, reports, and CSV export.

**Architecture:** Two new drift columns (`pausedAt`, `totalPausedSeconds`) capture pause state directly on `TimeEntry`, with a schema migration since this changes an existing table. A single `workedDuration` extension getter becomes the one place that turns start/end/pause data into a `Duration`, replacing four separate ad-hoc `endAt.difference(startAt)` calculations. New DAO methods (`pauseEntry`/`resumeEntry`) sit alongside the existing `startEntry`/`stopEntry`, with `stopEntry` extended to finalize at the pause point when stopping a paused entry. The Timer screen gets a second button and two tracking-suspension guards; reports/CSV/entries-list swap their duration math for the new getter.

**Tech Stack:** Flutter/Dart, Riverpod, drift (SQLite ORM) — same stack as the rest of the app, no new dependencies.

## Global Constraints

- Every task must leave `flutter analyze` clean and the existing test suite green.
- No new `testWidgets` tests — this codebase avoids widget-pumping screens wired to real Riverpod providers with live timers/streams (documented flutter_test false-positive risk, 5-10 minute runtime cost). Use plain `test()` wherever no widget pump is genuinely needed; the Timer screen's UI change (Task 5) has no dedicated widget test, matching the existing lack of one for `_RunningCard`/`_StartCard`.
- `DateTime.now()` calls in the DAO are always immediately converted `.toUtc()`, matching every existing DAO method (`startEntry`, `stopEntry`) — stay consistent with that, don't introduce local-time timestamps.
- Sync/event-log layer (`packages/sync_engine`, `lib/data/sync/sync_ingestor.dart`) needs no changes: event payloads are drift-generated `toJson()` full snapshots, so new columns flow through automatically.

---

## File Structure

New files:
- `lib/data/drift/time_entry_extensions.dart` — `workedDuration` getter, the single source of truth for turning a `TimeEntry` into a `Duration`.
- `test/data/drift/time_entry_extensions_test.dart` — unit tests for `workedDuration` across running/paused/stopped states.
- `test/data/drift/time_entries_dao_test.dart` — DAO tests for `pauseEntry`/`resumeEntry`/`stopEntry`-while-paused (no such DAO test file exists yet).

Modified files:
- `lib/data/drift/tables/time_entries_table.dart` — add `pausedAt`, `totalPausedSeconds` columns.
- `lib/data/drift/database.dart` — bump `schemaVersion`, add a `migration` override.
- `lib/data/drift/daos/time_entries_dao.dart` — add `pauseEntry`/`resumeEntry`, extend `stopEntry`.
- `lib/data/sync/synced_writes.dart` — add `pauseEntry`/`resumeEntry` wrappers.
- `lib/features/timer/timer_screen.dart` — Pause/Resume/Stop buttons, tracking-suspension guards.
- `lib/features/entries/entries_list.dart` — use `workedDuration`.
- `lib/features/reports/report_calculations.dart` — use `workedDuration` (two call sites).
- `lib/features/reports/csv_export.dart` — use `workedDuration`.
- `test/features/reports/report_calculations_test.dart` — fixture updates (new required field) + one new pause-exclusion assertion.
- `test/features/reports/csv_export_test.dart` — fixture update (new required field) + one new pause-exclusion assertion.

---

### Task 1: Schema migration — pausedAt and totalPausedSeconds columns

**Files:**
- Modify: `lib/data/drift/tables/time_entries_table.dart`
- Modify: `lib/data/drift/database.dart`

**Interfaces:**
- Produces: `TimeEntry.pausedAt` (`DateTime?`), `TimeEntry.totalPausedSeconds` (`int`, non-nullable) — every later task depends on these two fields existing on the generated `TimeEntry` data class and `TimeEntriesCompanion`.

This task has no automated test of its own (a schema migration for a fresh `:memory:` test database always takes the `onCreate` path, never `onUpgrade` — there's nothing meaningful to unit-test here without a dedicated schema-version fixture, which is out of scope for two straightforward column additions). Verification is `flutter analyze` plus confirming the full existing suite still passes after regenerating drift's code.

- [ ] **Step 1: Add the two columns**

In `lib/data/drift/tables/time_entries_table.dart`, add two new column getters after `endAt`:

```dart
import 'package:drift/drift.dart';

import 'projects_table.dart';

/// Values used in [TimeEntries.source]: 'manual' (timer/manual entry) or
/// 'auto' (desktop activity-tracking, added in a later milestone).
@DataClassName('TimeEntry')
class TimeEntries extends Table {
  TextColumn get id => text()();
  TextColumn get projectId => text().nullable().references(Projects, #id)();
  TextColumn get description => text().nullable()();
  DateTimeColumn get startAt => dateTime()();
  // Null endAt means this is the currently running entry.
  DateTimeColumn get endAt => dateTime().nullable()();
  // Set while the entry is paused (endAt still null); null while running or
  // stopped. Cleared back to null on resume.
  DateTimeColumn get pausedAt => dateTime().nullable()();
  // Sum of every pause span for this entry, across as many pause/resume
  // cycles as the user performs. Subtracted from (endAt ?? pausedAt ?? now)
  // - startAt to get the actual worked duration — see workedDuration in
  // lib/data/drift/time_entry_extensions.dart.
  IntColumn get totalPausedSeconds => integer().withDefault(const Constant(0))();
  BoolColumn get billableOverride => boolean().nullable()();
  TextColumn get source => text().withDefault(const Constant('manual'))();
  TextColumn get deviceId => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
```

- [ ] **Step 2: Add the migration**

In `lib/data/drift/database.dart`, bump the schema version and add a `migration` override:

```dart
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'daos/activity_samples_dao.dart';
import 'daos/events_dao.dart';
import 'daos/projects_dao.dart';
import 'daos/time_entries_dao.dart';
import 'tables/activity_samples_table.dart';
import 'tables/clients_table.dart';
import 'tables/events_table.dart';
import 'tables/projects_table.dart';
import 'tables/sync_file_states_table.dart';
import 'tables/tags_table.dart';
import 'tables/time_entries_table.dart';
import 'tables/time_entry_tags_table.dart';

part 'database.g.dart';

@DriftDatabase(
  tables: [
    Clients,
    Projects,
    Tags,
    TimeEntries,
    TimeEntryTags,
    Events,
    SyncFileStates,
    ActivitySamples,
  ],
  daos: [ProjectsDao, TimeEntriesDao, EventsDao, ActivitySamplesDao],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  AppDatabase.forTesting(super.connection);

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.addColumn(timeEntries, timeEntries.pausedAt);
        await m.addColumn(timeEntries, timeEntries.totalPausedSeconds);
      }
    },
  );

  static LazyDatabase _openConnection() {
    return LazyDatabase(() async {
      final dbFolder = await getApplicationDocumentsDirectory();
      final file = File(p.join(dbFolder.path, 'hickory.sqlite'));
      return NativeDatabase.createInBackground(file);
    });
  }
}
```

- [ ] **Step 3: Regenerate drift's generated code**

Run: `dart run build_runner build --delete-conflicting-outputs`
Expected: completes without errors; `lib/data/drift/database.g.dart` is regenerated with `pausedAt`/`totalPausedSeconds` on the `TimeEntry` data class and `TimeEntriesCompanion`.

- [ ] **Step 4: Analyze**

Run: `flutter analyze`
Expected: errors in every file that directly constructs `TimeEntry(...)` without the new required `totalPausedSeconds` field (`test/features/reports/report_calculations_test.dart`, `test/features/reports/csv_export_test.dart`). This is expected at this point in the plan — Task 6 fixes them. Confirm no *other* errors exist (e.g. nothing in `lib/` itself should error, since production code doesn't construct `TimeEntry` directly anywhere yet).

- [ ] **Step 5: Commit**

```bash
git add lib/data/drift/tables/time_entries_table.dart lib/data/drift/database.dart lib/data/drift/database.g.dart
git commit -m "Add pausedAt/totalPausedSeconds columns with a schema migration"
```

---

### Task 2: workedDuration extension

**Files:**
- Create: `lib/data/drift/time_entry_extensions.dart`
- Test: `test/data/drift/time_entry_extensions_test.dart`

**Interfaces:**
- Consumes: `TimeEntry.pausedAt`, `TimeEntry.totalPausedSeconds` (Task 1).
- Produces: `extension TimeEntryDuration on TimeEntry { Duration get workedDuration; }` — every later task that computes an entry's duration uses this instead of raw `endAt.difference(startAt)`.

- [ ] **Step 1: Write the failing tests**

```dart
// test/data/drift/time_entry_extensions_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/data/drift/database.dart';
import 'package:hickory/data/drift/time_entry_extensions.dart';

TimeEntry _entry({
  required DateTime startAt,
  DateTime? endAt,
  DateTime? pausedAt,
  int totalPausedSeconds = 0,
}) {
  final now = DateTime.utc(2026, 7, 1);
  return TimeEntry(
    id: 'e1',
    startAt: startAt,
    endAt: endAt,
    pausedAt: pausedAt,
    totalPausedSeconds: totalPausedSeconds,
    source: 'manual',
    deviceId: 'dev_a',
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  test('stopped entry: worked duration is endAt minus startAt minus paused time', () {
    final entry = _entry(
      startAt: DateTime.utc(2026, 7, 7, 9),
      endAt: DateTime.utc(2026, 7, 7, 11),
      totalPausedSeconds: 600, // 10 minutes
    );

    expect(entry.workedDuration, const Duration(hours: 1, minutes: 50));
  });

  test('paused entry: worked duration is frozen at pausedAt, ignoring time since', () {
    final entry = _entry(
      startAt: DateTime.utc(2026, 7, 7, 9),
      pausedAt: DateTime.utc(2026, 7, 7, 10),
    );

    expect(entry.workedDuration, const Duration(hours: 1));
  });

  test('running entry: worked duration counts up to now, minus prior paused time', () {
    final entry = _entry(
      startAt: DateTime.now().toUtc().subtract(const Duration(minutes: 5)),
      totalPausedSeconds: 60,
    );

    final duration = entry.workedDuration;
    expect(duration.inSeconds, greaterThanOrEqualTo(4 * 60));
    expect(duration.inSeconds, lessThanOrEqualTo(5 * 60));
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/data/drift/time_entry_extensions_test.dart`
Expected: FAIL — `package:hickory/data/drift/time_entry_extensions.dart` doesn't exist yet.

- [ ] **Step 3: Write the implementation**

```dart
// lib/data/drift/time_entry_extensions.dart
import 'database.dart';

/// Duration actually worked on this entry, with all paused time excluded.
/// While running this counts up live (re-evaluate the getter on each timer
/// tick to see it change); while paused it's frozen at the moment
/// [TimeEntry.pausedAt] was set; while stopped it's fixed.
extension TimeEntryDuration on TimeEntry {
  Duration get workedDuration {
    final effectiveEnd = endAt ?? pausedAt ?? DateTime.now().toUtc();
    return effectiveEnd.difference(startAt) - Duration(seconds: totalPausedSeconds);
  }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/data/drift/time_entry_extensions_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Analyze and commit**

Run: `flutter analyze`
Expected: same pre-existing errors as Task 1 Step 4 (fixed in Task 6), nothing new.

```bash
git add lib/data/drift/time_entry_extensions.dart test/data/drift/time_entry_extensions_test.dart
git commit -m "Add workedDuration: the single source of truth for pause-excluded duration"
```

---

### Task 3: DAO pauseEntry/resumeEntry, and stopEntry-while-paused

**Files:**
- Modify: `lib/data/drift/daos/time_entries_dao.dart`
- Test: `test/data/drift/time_entries_dao_test.dart`

**Interfaces:**
- Consumes: `TimeEntry.pausedAt`, `TimeEntry.totalPausedSeconds` (Task 1).
- Produces: `TimeEntriesDao.pauseEntry(String id)`, `TimeEntriesDao.resumeEntry(String id)` — both `Future<void>`. `stopEntry`'s existing signature (`Future<void> stopEntry(String id)`) is unchanged but its behavior when the entry is currently paused changes (see below) — `lib/data/sync/synced_writes.dart` (Task 4) and `lib/features/timer/timer_screen.dart` (Task 5) call these by name.

- [ ] **Step 1: Write the failing tests**

```dart
// test/data/drift/time_entries_dao_test.dart
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/data/drift/database.dart';

// Plain test() (not testWidgets): no widget pumping needed.
void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  test('pauseEntry sets pausedAt on a running entry', () async {
    final entry = await db.timeEntriesDao.startEntry(deviceId: 'dev_a');
    await db.timeEntriesDao.pauseEntry(entry.id);

    final paused =
        await (db.select(db.timeEntries)..where((t) => t.id.equals(entry.id))).getSingle();
    expect(paused.pausedAt, isNotNull);
    expect(paused.endAt, isNull);
  });

  test('resumeEntry clears pausedAt and accumulates totalPausedSeconds', () async {
    final entry = await db.timeEntriesDao.startEntry(deviceId: 'dev_a');
    await db.timeEntriesDao.pauseEntry(entry.id);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await db.timeEntriesDao.resumeEntry(entry.id);

    final resumed =
        await (db.select(db.timeEntries)..where((t) => t.id.equals(entry.id))).getSingle();
    expect(resumed.pausedAt, isNull);
    expect(resumed.totalPausedSeconds, greaterThan(0));
  });

  test('multiple pause/resume cycles accumulate totalPausedSeconds monotonically', () async {
    final entry = await db.timeEntriesDao.startEntry(deviceId: 'dev_a');

    await db.timeEntriesDao.pauseEntry(entry.id);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    await db.timeEntriesDao.resumeEntry(entry.id);
    final afterFirstCycle =
        await (db.select(db.timeEntries)..where((t) => t.id.equals(entry.id))).getSingle();

    await db.timeEntriesDao.pauseEntry(entry.id);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    await db.timeEntriesDao.resumeEntry(entry.id);
    final afterSecondCycle =
        await (db.select(db.timeEntries)..where((t) => t.id.equals(entry.id))).getSingle();

    expect(
      afterSecondCycle.totalPausedSeconds,
      greaterThanOrEqualTo(afterFirstCycle.totalPausedSeconds),
    );
    expect(afterSecondCycle.pausedAt, isNull);
  });

  test('stopEntry while paused finalizes endAt to the pausedAt timestamp, not now', () async {
    final entry = await db.timeEntriesDao.startEntry(deviceId: 'dev_a');
    await db.timeEntriesDao.pauseEntry(entry.id);
    final pausedRow =
        await (db.select(db.timeEntries)..where((t) => t.id.equals(entry.id))).getSingle();
    final pausedAt = pausedRow.pausedAt!;

    await Future<void>.delayed(const Duration(milliseconds: 50));
    await db.timeEntriesDao.stopEntry(entry.id);

    final stopped =
        await (db.select(db.timeEntries)..where((t) => t.id.equals(entry.id))).getSingle();
    expect(stopped.endAt, pausedAt);
    expect(stopped.pausedAt, isNull);
  });

  test('stopEntry on a running (not paused) entry sets endAt to now, as before', () async {
    final entry = await db.timeEntriesDao.startEntry(deviceId: 'dev_a');
    await db.timeEntriesDao.stopEntry(entry.id);

    final stopped =
        await (db.select(db.timeEntries)..where((t) => t.id.equals(entry.id))).getSingle();
    expect(stopped.endAt, isNotNull);
    expect(stopped.pausedAt, isNull);
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/data/drift/time_entries_dao_test.dart`
Expected: FAIL — `pauseEntry`/`resumeEntry` don't exist yet on `TimeEntriesDao`.

- [ ] **Step 3: Write the implementation**

Replace `stopEntry` and add the two new methods in `lib/data/drift/daos/time_entries_dao.dart` (everything else in the file is unchanged):

```dart
  Future<void> pauseEntry(String id) {
    final now = DateTime.now().toUtc();
    return (update(timeEntries)..where((t) => t.id.equals(id))).write(
      TimeEntriesCompanion(pausedAt: Value(now), updatedAt: Value(now)),
    );
  }

  Future<void> resumeEntry(String id) async {
    final current = await (select(timeEntries)..where((t) => t.id.equals(id))).getSingle();
    final pausedAt = current.pausedAt;
    if (pausedAt == null) return;
    final now = DateTime.now().toUtc();
    final additionalPausedSeconds = now.difference(pausedAt).inSeconds;
    await (update(timeEntries)..where((t) => t.id.equals(id))).write(
      TimeEntriesCompanion(
        pausedAt: const Value(null),
        totalPausedSeconds: Value(current.totalPausedSeconds + additionalPausedSeconds),
        updatedAt: Value(now),
      ),
    );
  }

  Future<void> stopEntry(String id) async {
    final now = DateTime.now().toUtc();
    final current = await (select(timeEntries)..where((t) => t.id.equals(id))).getSingle();
    final endAt = current.pausedAt ?? now;
    await (update(timeEntries)..where((t) => t.id.equals(id))).write(
      TimeEntriesCompanion(endAt: Value(endAt), pausedAt: const Value(null), updatedAt: Value(now)),
    );
  }
```

Place `pauseEntry` and `resumeEntry` immediately after the replaced `stopEntry`, before `createManualEntry`, so the four entry-lifecycle methods (`startEntry`, `stopEntry`, `pauseEntry`, `resumeEntry`) stay grouped.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/data/drift/time_entries_dao_test.dart`
Expected: PASS (5 tests).

- [ ] **Step 5: Analyze, run the full suite, and commit**

Run: `flutter analyze`
Expected: same pre-existing errors as before (fixed in Task 6), nothing new.

Run: `flutter test`
Expected: all tests pass except the two report/csv test files with the known pending fixture errors from Task 1 (fixed in Task 6).

```bash
git add lib/data/drift/daos/time_entries_dao.dart test/data/drift/time_entries_dao_test.dart
git commit -m "Add TimeEntriesDao.pauseEntry/resumeEntry; stopEntry finalizes at pausedAt when paused"
```

---

### Task 4: SyncedWrites wiring

**Files:**
- Modify: `lib/data/sync/synced_writes.dart`

**Interfaces:**
- Consumes: `TimeEntriesDao.pauseEntry`/`resumeEntry` (Task 3).
- Produces: `SyncedWrites.pauseEntry(String id)`, `SyncedWrites.resumeEntry(String id)` — both `Future<void>`, called directly by `lib/features/timer/timer_screen.dart` (Task 5).

This is a thin wrapper matching the existing `stopEntry` wrapper exactly (DAO call + `_logCurrentState` to append the sync event) — no new test needed, same as `stopEntry`'s wrapper has none beyond incidental coverage elsewhere.

- [ ] **Step 1: Add the two methods**

In `lib/data/sync/synced_writes.dart`, add immediately after the existing `stopEntry` method:

```dart
  Future<void> pauseEntry(String id) async {
    await db.timeEntriesDao.pauseEntry(id);
    await _logCurrentState(id, EventOp.update);
  }

  Future<void> resumeEntry(String id) async {
    await db.timeEntriesDao.resumeEntry(id);
    await _logCurrentState(id, EventOp.update);
  }
```

- [ ] **Step 2: Analyze**

Run: `flutter analyze`
Expected: same pre-existing errors as before (fixed in Task 6), nothing new.

- [ ] **Step 3: Commit**

```bash
git add lib/data/sync/synced_writes.dart
git commit -m "Wire pauseEntry/resumeEntry through SyncedWrites"
```

---

### Task 5: TimerScreen — Pause/Resume/Stop buttons and tracking suspension

**Files:**
- Modify: `lib/features/timer/timer_screen.dart`

**Interfaces:**
- Consumes: `SyncedWrites.pauseEntry`/`resumeEntry` (Task 4), `TimeEntry.workedDuration` (Task 2), `TimeEntry.pausedAt` (Task 1).

No new test for this file — matches the existing lack of a widget test for `_RunningCard`/`_StartCard` (Global Constraints: no `testWidgets` against the real Riverpod-wired tree). Verified via `flutter analyze` plus the manual check in this task's last step.

- [ ] **Step 1: Add `_pause`/`_resume` methods and suspend tracking while paused**

In `lib/features/timer/timer_screen.dart`, update `_handleIdleSecondsChanged` and `_recordActivitySample` to bail out while paused, and add `_pause`/`_resume` alongside the existing `_stop`:

```dart
  Future<void> _handleIdleSecondsChanged(int idleSeconds) async {
    if (idleSeconds < _idleThresholdSeconds) {
      _idlePromptShowing = false;
      return;
    }
    if (_idlePromptShowing) return;
    final running = ref.read(runningEntryProvider).value;
    if (running == null || running.pausedAt != null) return;

    _idlePromptShowing = true;
    final idleDuration = Duration(seconds: idleSeconds);
    final shouldTrim = await showIdlePromptDialog(context, idleDuration);
    if (!mounted) return;
    if (shouldTrim) {
      final writes = await ref.read(syncedWritesProvider.future);
      final idleStart = DateTime.now().subtract(idleDuration);
      await writes.updateEntry(running.id, endAt: Value(idleStart.toUtc()));
    }
    _idlePromptShowing = false;
  }

  Future<void> _recordActivitySample(ActivitySample sample) async {
    final running = ref.read(runningEntryProvider).value;
    if (running == null || running.pausedAt != null) return;
    final deviceId = await ref.read(deviceIdProvider.future);
    final writes = await ref.read(syncedWritesProvider.future);
    await writes.recordActivitySample(
      deviceId: deviceId,
      appName: sample.appName,
      windowTitle: sample.windowTitle,
      observedAt: sample.observedAt,
    );
  }

  Future<void> _start() async {
    final deviceId = await ref.read(deviceIdProvider.future);
    final writes = await ref.read(syncedWritesProvider.future);
    await writes.startEntry(
      deviceId: deviceId,
      projectId: _selectedProjectId,
      description: _descriptionController.text.trim().isEmpty
          ? null
          : _descriptionController.text.trim(),
    );
    _descriptionController.clear();
  }

  Future<void> _stop(TimeEntry running) async {
    final writes = await ref.read(syncedWritesProvider.future);
    await writes.stopEntry(running.id);
  }

  Future<void> _pause(TimeEntry running) async {
    final writes = await ref.read(syncedWritesProvider.future);
    await writes.pauseEntry(running.id);
  }

  Future<void> _resume(TimeEntry running) async {
    final writes = await ref.read(syncedWritesProvider.future);
    await writes.resumeEntry(running.id);
  }
```

- [ ] **Step 2: Wire the new callbacks into `_RunningCard` and update its buttons**

Update the `build` method's `_RunningCard` construction:

```dart
          runningAsync.when(
            data: (running) => running != null
                ? _RunningCard(
                    running: running,
                    onPause: () => _pause(running),
                    onResume: () => _resume(running),
                    onStop: () => _stop(running),
                  )
                : _StartCard(
                    descriptionController: _descriptionController,
                    selectedProjectId: _selectedProjectId,
                    onProjectChanged: (id) => setState(() => _selectedProjectId = id),
                    onStart: _start,
                  ),
            loading: () => const CircularProgressIndicator(),
            error: (e, _) => Text('Fehler: $e'),
          ),
```

Replace the `_RunningCard` class entirely:

```dart
class _RunningCard extends ConsumerWidget {
  const _RunningCard({
    required this.running,
    required this.onPause,
    required this.onResume,
    required this.onStop,
  });

  final TimeEntry running;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isPaused = running.pausedAt != null;
    final elapsed = running.workedDuration;
    final tokens = HickoryColors.of(context);
    final projectsAsync = ref.watch(activeProjectsProvider);
    final projectsById = {
      for (final p in projectsAsync.value ?? const <Project>[]) p.id: p,
    };
    final project = running.projectId == null ? null : projectsById[running.projectId];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: tokens.surfaceGradient,
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            formatDuration(elapsed),
            style: TextStyle(
              fontFamily: Theme.of(context).textTheme.displayLarge?.fontFamily,
              fontWeight: FontWeight.w700,
              fontSize: 34,
              color: tokens.timerNumeral,
            ),
          ),
          if (running.description?.isNotEmpty ?? false) ...[
            const SizedBox(height: 6),
            Text(running.description!),
          ],
          if (project != null) ...[
            const SizedBox(height: 8),
            Chip(label: Text(project.name)),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: GradientPillButton(
                  label: isPaused ? 'Fortsetzen' : 'Pause',
                  icon: isPaused ? Icons.play_arrow : Icons.pause,
                  gradient: tokens.primaryGradient,
                  foregroundColor: tokens.onPrimaryGradient,
                  onPressed: isPaused ? onResume : onPause,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onStop,
                  icon: const Icon(Icons.stop),
                  label: const Text('Stop'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 3: Add the import**

Add to the top of `lib/features/timer/timer_screen.dart`, alongside the other `data/drift` import:

```dart
import '../../data/drift/time_entry_extensions.dart';
```

- [ ] **Step 4: Analyze**

Run: `flutter analyze`
Expected: same pre-existing errors as before (fixed in Task 6), nothing new.

- [ ] **Step 5: Manual check**

Run: `flutter run -d windows` (or the current platform), start a timer, click Pause — confirm the displayed time freezes and the button now reads "Fortsetzen"; click it again — confirm the clock resumes counting from the frozen value, not from zero; click Stop while paused — confirm the entry disappears from the running card (moves to the entries list below) without hanging or erroring.

- [ ] **Step 6: Commit**

```bash
git add lib/features/timer/timer_screen.dart
git commit -m "Add Pause/Resume to the running timer card; suspend tracking while paused"
```

---

### Task 6: Reports, CSV export, and entries list use workedDuration

**Files:**
- Modify: `lib/features/entries/entries_list.dart`
- Modify: `lib/features/reports/report_calculations.dart`
- Modify: `lib/features/reports/csv_export.dart`
- Modify: `test/features/reports/report_calculations_test.dart`
- Modify: `test/features/reports/csv_export_test.dart`

**Interfaces:**
- Consumes: `TimeEntry.workedDuration` (Task 2).

- [ ] **Step 1: Update `entries_list.dart`**

Add the import and change the duration line:

```dart
import '../../data/drift/time_entry_extensions.dart';
```

Change:
```dart
            final duration = entry.endAt!.difference(entry.startAt);
```
to:
```dart
            final duration = entry.workedDuration;
```

- [ ] **Step 2: Update `report_calculations.dart`**

Add the import:
```dart
import '../../data/drift/time_entry_extensions.dart';
```

In `totalsByProject`, change:
```dart
  for (final entry in entries) {
    final endAt = entry.endAt;
    if (endAt == null) continue;
    final duration = endAt.difference(entry.startAt);
```
to:
```dart
  for (final entry in entries) {
    if (entry.endAt == null) continue;
    final duration = entry.workedDuration;
```

In `totalsByDay`, change:
```dart
  for (final entry in entries) {
    final endAt = entry.endAt;
    if (endAt == null) continue;
    final local = entry.startAt.toLocal();
    final day = DateTime(local.year, local.month, local.day);
    final duration = endAt.difference(entry.startAt);
```
to:
```dart
  for (final entry in entries) {
    if (entry.endAt == null) continue;
    final local = entry.startAt.toLocal();
    final day = DateTime(local.year, local.month, local.day);
    final duration = entry.workedDuration;
```

- [ ] **Step 3: Update `csv_export.dart`**

Add the import:
```dart
import '../../data/drift/time_entry_extensions.dart';
```

Change:
```dart
    final duration = endAt.difference(entry.startAt);
```
to:
```dart
    final duration = entry.workedDuration;
```

(`endAt` stays as a local variable — it's still used a few lines later for `formatTime(endAt)`.)

- [ ] **Step 4: Fix the two test fixtures and add pause-exclusion assertions**

In `test/features/reports/report_calculations_test.dart`, add `totalPausedSeconds: 0` to the `_entry` helper's `TimeEntry(...)` construction and to the "still-running entry" test's direct construction:

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

```dart
    test('a still-running entry (no endAt) is excluded', () {
      final now = DateTime.utc(2026, 7, 1);
      final running = TimeEntry(
        id: 'e1',
        startAt: DateTime.utc(2026, 7, 7, 9),
        source: 'manual',
        deviceId: 'dev_a',
        createdAt: now,
        updatedAt: now,
        totalPausedSeconds: 0,
      );

      expect(totalsByProject([running], const []), isEmpty);
    });
```

Then add one new test to the `totalsByProject` group confirming pause time is actually excluded end-to-end through this call site:

```dart
    test('paused time is excluded from the summed duration', () {
      final entries = [
        TimeEntry(
          id: 'e1',
          projectId: 'p1',
          startAt: DateTime.utc(2026, 7, 7, 9),
          endAt: DateTime.utc(2026, 7, 7, 11), // 2h wall-clock
          totalPausedSeconds: 20 * 60, // 20 minutes paused
          source: 'manual',
          deviceId: 'dev_a',
          createdAt: DateTime.utc(2026, 7, 1),
          updatedAt: DateTime.utc(2026, 7, 1),
        ),
      ];

      final totals = totalsByProject(entries, [
        _project(id: 'p1', name: 'Client X'),
      ]);

      expect(totals.single.duration, const Duration(hours: 1, minutes: 40));
    });
```

In `test/features/reports/csv_export_test.dart`, add `totalPausedSeconds: 0` to the existing `TimeEntry(...)` construction, and add a new test confirming the exported hours exclude pause time:

```dart
  test('entriesToCsv excludes paused time from the exported hours', () {
    final now = DateTime.utc(2026, 7, 1);
    final project = Project(
      id: 'p1',
      name: 'Client X',
      colorHex: '#5B8DEF',
      archived: false,
      billable: true,
      hourlyRateCents: 10000,
      currency: 'EUR',
      createdAt: now,
      updatedAt: now,
    );
    final entry = TimeEntry(
      id: 'e1',
      projectId: 'p1',
      description: 'Design review',
      startAt: DateTime.utc(2026, 7, 7, 9),
      endAt: DateTime.utc(2026, 7, 7, 11), // 2h wall-clock
      totalPausedSeconds: 30 * 60, // 30 minutes paused
      source: 'manual',
      deviceId: 'dev_a',
      createdAt: now,
      updatedAt: now,
    );

    final csv = entriesToCsv([entry], [project]);
    final lines = csv.trim().split('\r\n');

    expect(lines[1], contains('1.50')); // 2h - 30min = 1.5h
  });
```

Remember to also add `totalPausedSeconds: 0` to the file's existing `entry` construction (the one built at the top of the first test), so it still compiles.

- [ ] **Step 5: Run the affected tests to verify they pass**

Run: `flutter test test/features/reports/report_calculations_test.dart test/features/reports/csv_export_test.dart`
Expected: PASS, including the two new pause-exclusion tests.

- [ ] **Step 6: Analyze and run the full suite**

Run: `flutter analyze`
Expected: `No issues found!` — this is the task that clears the pre-existing errors noted since Task 1.

Run: `flutter test`
Expected: all tests pass, no failures.

- [ ] **Step 7: Commit**

```bash
git add lib/features/entries/entries_list.dart lib/features/reports/report_calculations.dart lib/features/reports/csv_export.dart test/features/reports/report_calculations_test.dart test/features/reports/csv_export_test.dart
git commit -m "Switch reports, CSV export, and entries list to workedDuration"
```

---

## Self-Review Notes

- **Spec coverage:** data model + migration (Task 1), duration formula (Task 2), pause/resume/stop-while-paused write API (Task 3), sync wiring (Task 4), UI + tracking suspension (Task 5), reports/CSV/entries-list (Task 6) — every section of the spec maps to a task. Manual verification steps from the spec's Verification section are covered by Task 5 Step 5 (freeze/resume/stop-while-paused) and Task 3's automated tests (multi-cycle accumulation); the CSV/report pause-exclusion checks are covered by Task 6's new tests instead of only manually, which is stronger than the spec asked for.
- **Placeholder scan:** none found — every step has complete code.
- **Type consistency:** `TimeEntriesDao.pauseEntry`/`resumeEntry` (Task 3) match their usage in `SyncedWrites` (Task 4) and, transitively, `timer_screen.dart` (Task 5) — same names, same `Future<void> Function(String id)` shape throughout. `workedDuration` (Task 2) is used identically in Tasks 5 and 6.
- **Sequencing:** Tasks 1→2→3→4→5, and 6 depends only on Task 2 — a valid linear order satisfying every dependency. Task 1's `flutter analyze` step deliberately documents the two now-broken test files rather than hiding them, so each intermediate task's analyze step has a clear "expected, not new" baseline until Task 6 fixes them for good.
