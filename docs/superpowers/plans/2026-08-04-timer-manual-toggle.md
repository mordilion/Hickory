# Timer / Manual Toggle Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Timer tab's permanent stack of the timer card + quick-add bar with a segmented toggle that shows one at a time, locked to Timer mode while a timer is running.

**Architecture:** One new enum + one new `bool _rangeTouched`-style piece of local state in `_TimerScreenState`, a `SegmentedButton<_TimerTabMode>` rendered above the existing conditional card, and a conditional swap of `_RunningCard`/`_StartCard` vs `QuickAddBar`. No new files, no data-layer changes.

**Tech Stack:** Flutter Material 3 (`SegmentedButton`), existing Riverpod providers (`runningEntryProvider`).

## Global Constraints

- Single file touched (`lib/features/timer/timer_screen.dart`) plus l10n additions — no data model, DAO, or provider changes.
- Every new user-facing string added to all six ARB files (`lib/l10n/app_{de,en,es,fr,it,nl}.arb`).
- Mode is never persisted — always defaults to Timer mode on launch.
- While `runningEntryProvider` has a non-null value, "Manual" must be disabled and the mode forced to Timer — never allow a running timer to go unshown.
- Commit messages follow Conventional Commits: `type(scope): imperative, lowercase, no period, <72 chars`.
- TDD: write the failing test, watch it fail, implement, watch it pass, then commit.

---

## Task 1: Segmented Timer/Manual toggle

**Files:**
- Modify: `lib/features/timer/timer_screen.dart`
- Modify: `lib/l10n/app_de.arb`, `app_en.arb`, `app_es.arb`, `app_fr.arb`, `app_it.arb`, `app_nl.arb`
- Test: `test/features/timer/timer_screen_test.dart` (new)

**Interfaces:**
- Produces: private enum `_TimerTabMode { timer, manual }` and `_TimerScreenState._mode` — internal, no other file depends on them.

- [ ] **Step 1: Add the new l10n key to all six ARB files**

Insert immediately after the `"timerStart"` line in each file (keep that line's trailing comma):

`app_de.arb`: `"timerModeManual": "Manuell",`
`app_en.arb`: `"timerModeManual": "Manual",`
`app_es.arb`: `"timerModeManual": "Manual",`
`app_fr.arb`: `"timerModeManual": "Manuel",`
`app_it.arb`: `"timerModeManual": "Manuale",`
`app_nl.arb`: `"timerModeManual": "Handmatig",`

Run: `flutter gen-l10n`
Expected: succeeds; `AppLocalizations.timerModeManual` exists for all six locales.

- [ ] **Step 2: Write the failing widget test**

Create `test/features/timer/timer_screen_test.dart`:

```dart
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/core/di/app_settings_provider.dart';
import 'package:hickory/core/di/database_provider.dart';
import 'package:hickory/core/di/device_id_provider.dart';
import 'package:hickory/core/di/jira_providers.dart';
import 'package:hickory/core/di/sync_providers.dart';
import 'package:hickory/data/drift/database.dart';
import 'package:hickory/data/sync/sync_log_writer.dart';
import 'package:hickory/data/sync/synced_writes.dart';
import 'package:hickory/features/projects/projects_providers.dart';
import 'package:hickory/features/timer/timer_providers.dart';
import 'package:hickory/features/timer/timer_screen.dart';
import 'package:hickory/l10n/app_localizations.dart';

void main() {
  late AppDatabase db;
  late Directory syncRoot;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    syncRoot = Directory.systemTemp.createTempSync('hickory_timer_screen_test_');
  });

  tearDown(() async {
    await db.close();
    if (syncRoot.existsSync()) syncRoot.deleteSync(recursive: true);
  });

  // Same static-override pattern used throughout this codebase's other
  // widget tests (see quick_add_bar_test.dart) to avoid subscribing to a
  // live drift-backed StreamProvider, which hits a known flutter_test
  // false positive at teardown (flutter/flutter#144472).
  Widget makeApp() => ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          runningEntryProvider.overrideWith((ref) => Stream.value(null)),
          allEntriesProvider.overrideWith((ref) => Stream.value(const [])),
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
          home: const Scaffold(body: TimerScreen()),
        ),
      );

  testWidgets('defaults to Timer mode: start card shown, quick-add bar absent', (tester) async {
    await tester.pumpWidget(makeApp());
    await tester.pumpAndSettle();

    expect(find.text('Start'), findsOneWidget);
    expect(find.text('Add entry'), findsNothing);
  });

  testWidgets('tapping Manual (no running entry) swaps to the quick-add bar', (tester) async {
    await tester.pumpWidget(makeApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Manual'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Add entry'), findsOneWidget);
    expect(find.text('What are you working on?'), findsNothing);
  });

  testWidgets('with a running entry, Manual is disabled and Timer mode stays forced', (tester) async {
    final now = DateTime.now().toUtc();
    final running = TimeEntry(
      id: 'running-1',
      projectId: null,
      description: null,
      startAt: now,
      endAt: null,
      pausedAt: null,
      totalPausedSeconds: 0,
      billableOverride: null,
      source: 'manual',
      deviceId: 'device-1',
      jiraTicketKey: null,
      createdAt: now,
      updatedAt: now,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          runningEntryProvider.overrideWith((ref) => Stream.value(running)),
          allEntriesProvider.overrideWith((ref) => Stream.value(const [])),
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
          home: const Scaffold(body: TimerScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // _TimerTabMode is private to timer_screen.dart, so this test can't
    // reference SegmentedButton<_TimerTabMode> by generic type -- it only
    // asserts on the resulting behavior (disabled segments don't respond to
    // taps), not on the widget's internal `enabled` flag directly.
    await tester.tap(find.text('Manual'), warnIfMissed: false);
    await tester.pumpAndSettle();

    // _RunningCard is still showing (its Stop button, a stable marker
    // independent of the live elapsed-time text) and the quick-add bar
    // never appeared.
    expect(find.text('Stop'), findsOneWidget);
    expect(find.byTooltip('Add entry'), findsNothing);
  });
}
```

- [ ] **Step 3: Run the test, verify it fails**

Run: `flutter test test/features/timer/timer_screen_test.dart`
Expected: FAIL — `Start` renders today, but tapping "Manual" does nothing (no such control exists yet) and the third test's `SegmentedButton` lookup finds nothing.

- [ ] **Step 4: Implement the toggle**

Edit `lib/features/timer/timer_screen.dart`. Add a private enum near the top of the file, after the existing `_idleThresholdSeconds` constant:

```dart
enum _TimerTabMode { timer, manual }
```

Add one field to `_TimerScreenState`, alongside the existing fields:

```dart
  _TimerTabMode _mode = _TimerTabMode.timer;
```

Replace the `build` method's `Column` children — insert the segmented control before the existing `runningAsync.when(...)` block, and swap the timer-card/quick-add-bar based on `_mode`:

```dart
    final isRunning = runningAsync.value != null;
    if (isRunning) _mode = _TimerTabMode.timer;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          SegmentedButton<_TimerTabMode>(
            segments: [
              ButtonSegment(
                value: _TimerTabMode.timer,
                label: Text(l10n.navTimer),
              ),
              ButtonSegment(
                value: _TimerTabMode.manual,
                label: Text(l10n.timerModeManual),
                enabled: !isRunning,
              ),
            ],
            selected: {_mode},
            onSelectionChanged: (selection) => setState(() => _mode = selection.first),
          ),
          const SizedBox(height: 16),
          if (_mode == _TimerTabMode.timer)
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
                      selectedJiraTicketKey: _selectedJiraTicketKey,
                      onJiraTicketKeyChanged: (key) => setState(() => _selectedJiraTicketKey = key),
                      onStart: _start,
                    ),
              loading: () => const CircularProgressIndicator(),
              error: (e, _) => Text(l10n.timerError('$e')),
            )
          else
            const QuickAddBar(),
          const SizedBox(height: 16),
          const Expanded(child: EntriesList()),
        ],
      ),
    );
```

(This replaces the whole `return Padding(...)` statement at the end of `build`; everything above it — the `l10n`/`runningAsync`/`ref.listen` setup — stays unchanged. The `import '../entries/quick_add_bar.dart';` import already exists from the quick-entry-redesign work, so no import changes are needed.)

- [ ] **Step 5: Run the test, verify it passes**

Run: `flutter test test/features/timer/timer_screen_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 6: Run static analysis**

Run: `flutter analyze lib/features/timer/timer_screen.dart`
Expected: no issues.

- [ ] **Step 7: Commit**

```bash
git add lib/features/timer/timer_screen.dart lib/l10n/app_de.arb lib/l10n/app_en.arb lib/l10n/app_es.arb lib/l10n/app_fr.arb lib/l10n/app_it.arb lib/l10n/app_nl.arb test/features/timer/timer_screen_test.dart
git commit -m "feat(timer): toggle between Timer and Manual instead of stacking both"
```

---

## Final Verification

- [ ] `flutter test test/features/timer/` passes.
- [ ] `flutter analyze` is clean.
- [ ] Manually confirm in a running build: default is Timer mode; tapping Manual (no running entry) swaps to the quick-add bar; starting a timer forces the toggle back to Timer and greys out Manual; stopping the timer re-enables Manual.
