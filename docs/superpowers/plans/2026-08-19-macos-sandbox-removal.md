# macOS Sandbox Removal Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Drop the macOS App Sandbox so the in-app updater can replace the installed bundle, moving existing user data out of the sandbox container in the same release.

**Architecture:** One pure, temp-directory-testable migration function copies the two container directories into their unsandboxed homes on first launch of the new build; it runs from `main()` before any provider touches storage. The database's macOS path moves from Documents to Application Support in the same step, because unsandboxed Documents means the user's own `~/Documents`.

**Tech Stack:** Flutter (version from `pubspec.yaml`), `path_provider`, Drift, `flutter_secure_storage`, `flutter_test`.

**Spec:** `docs/superpowers/specs/2026-08-19-macos-sandbox-removal-design.md`

## Global Constraints

- **Never touch the live container.** Every manual verification runs against a *copy*. The reporter's real data lives in `~/Library/Containers/com.hickory.hickory` and is the only copy that exists.
- The migration **copies, never moves or deletes**. An interrupted run must leave the sandboxed build fully working.
- `flutter`/`dart` live in `/opt/homebrew/bin/`; call them by absolute path when `which` comes up empty.
- Commits only on the user's explicit request (`CLAUDE.md`); each task ends with its commit step prepared, not necessarily run.
- Every task ends with `flutter test` fully green and `flutter analyze` clean.
- Do not reformat untouched lines; `dart format` is not clean on some existing test files.
- New user-facing strings go into all six `.arb` files, `app_de.arb` is the template.
- Windows behavior must not change. Its database path stays `getApplicationDocumentsDirectory()`.

---

### Task 1: Migration logic

**Files:**
- Create: `lib/core/storage/support_directory_migration.dart`
- Test: `test/core/storage/support_directory_migration_test.dart`

**Interfaces:**
- Produces: `enum SupportMigrationOutcome { skippedAlreadyMigrated, skippedNoLegacyData, copied }` and
  `Future<SupportMigrationOutcome> migrateOutOfSandboxContainer({required Directory legacySupport, required Directory legacyDocuments, required Directory target, required String databaseFileName})`.

The target for **both** legacy directories is the one unsandboxed Application Support
directory: the database file lands next to the other state instead of in `~/Documents`.

- [ ] **Step 1: Write the failing test**

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/core/storage/support_directory_migration.dart';

void main() {
  late Directory root;
  late Directory legacySupport;
  late Directory legacyDocuments;
  late Directory target;

  setUp(() {
    root = Directory.systemTemp.createTempSync('hickory_migration_test_');
    legacySupport = Directory('${root.path}/container/Library/Application Support')
      ..createSync(recursive: true);
    legacyDocuments = Directory('${root.path}/container/Documents')
      ..createSync(recursive: true);
    target = Directory('${root.path}/unsandboxed')..createSync(recursive: true);
  });

  tearDown(() => root.deleteSync(recursive: true));

  Future<SupportMigrationOutcome> migrate() => migrateOutOfSandboxContainer(
    legacySupport: legacySupport,
    legacyDocuments: legacyDocuments,
    target: target,
    databaseFileName: 'hickory.sqlite',
  );

  test('copies the database and the support files into one directory', () async {
    File('${legacyDocuments.path}/hickory.sqlite').writeAsStringSync('db');
    File('${legacySupport.path}/device_id').writeAsStringSync('device-1');
    Directory('${legacySupport.path}/sync').createSync();
    File('${legacySupport.path}/sync/state.json').writeAsStringSync('{}');

    expect(await migrate(), SupportMigrationOutcome.copied);
    expect(File('${target.path}/hickory.sqlite').readAsStringSync(), 'db');
    expect(File('${target.path}/device_id').readAsStringSync(), 'device-1');
    expect(File('${target.path}/sync/state.json').existsSync(), isTrue);
  });

  test('leaves the legacy data in place', () async {
    File('${legacyDocuments.path}/hickory.sqlite').writeAsStringSync('db');

    await migrate();

    expect(File('${legacyDocuments.path}/hickory.sqlite').existsSync(), isTrue);
  });

  test('does nothing when the target already has a database', () async {
    File('${legacyDocuments.path}/hickory.sqlite').writeAsStringSync('old');
    File('${target.path}/hickory.sqlite').writeAsStringSync('current');

    expect(await migrate(), SupportMigrationOutcome.skippedAlreadyMigrated);
    // The second run must never overwrite live data with the stale container copy.
    expect(File('${target.path}/hickory.sqlite').readAsStringSync(), 'current');
  });

  test('does nothing for a fresh install with no container', () async {
    legacySupport.deleteSync();
    legacyDocuments.deleteSync();

    expect(await migrate(), SupportMigrationOutcome.skippedNoLegacyData);
    expect(target.listSync(), isEmpty);
  });

  test('reports copied when only the support directory exists', () async {
    legacyDocuments.deleteSync();
    File('${legacySupport.path}/device_id').writeAsStringSync('device-1');

    expect(await migrate(), SupportMigrationOutcome.copied);
    expect(File('${target.path}/device_id').existsSync(), isTrue);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `/opt/homebrew/bin/flutter test test/core/storage/support_directory_migration_test.dart`
Expected: FAIL — the import cannot be resolved.

- [ ] **Step 3: Write the implementation**

Create `lib/core/storage/support_directory_migration.dart`. Requirements the tests pin:

- Skip when `target/databaseFileName` exists — the presence of the live database *is* the
  "already migrated" marker, so no extra state file is needed.
- Skip when neither legacy directory exists.
- Copy `legacyDocuments/databaseFileName` to `target/databaseFileName`, and every entry of
  `legacySupport` into `target`, recursing into subdirectories.
- Never delete or move anything under either legacy directory.
- Let an `IOException` escape: the caller in Task 2 turns it into a visible error rather than
  starting with half the data.
- Document *why* the database changes directory (unsandboxed Documents is the user's own
  `~/Documents`) and that the copy is deliberate.

- [ ] **Step 4: Run tests to verify they pass**

Run: `/opt/homebrew/bin/flutter test test/core/storage/support_directory_migration_test.dart`
Expected: PASS, 5 tests. Then `/opt/homebrew/bin/flutter analyze` — no issues.

- [ ] **Step 5: Commit** (only with the user's go-ahead)

```bash
git add lib/core/storage/support_directory_migration.dart test/core/storage/support_directory_migration_test.dart
git commit -m "feat(storage): add the sandbox-container data migration"
```

---

### Task 2: Resolve the paths and run the migration at startup

**Files:**
- Create: `lib/core/storage/app_directories.dart`
- Modify: `lib/main.dart` (before `ProviderContainer()` is created)
- Modify: `lib/data/drift/database.dart:99` (the macOS database path)
- Test: `test/core/storage/app_directories_test.dart`

**Interfaces:**
- Consumes: `migrateOutOfSandboxContainer` (Task 1).
- Produces: `Directory legacyContainerSupportDirectory(String home, String bundleId)`,
  `Directory legacyContainerDocumentsDirectory(String home, String bundleId)`, and
  `Future<Directory> appDataDirectory()` — the one directory the database and all other state
  live in.

- [ ] **Step 1: Write the failing test for the path builders**

The container paths must be derived from the home directory, because `path_provider` no longer
returns them once the sandbox is gone. Keep them pure so they are testable without a container:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/core/storage/app_directories.dart';

void main() {
  test('builds the legacy container paths from home and bundle id', () {
    expect(
      legacyContainerSupportDirectory('/Users/x', 'com.hickory.hickory').path,
      '/Users/x/Library/Containers/com.hickory.hickory/Data/Library/'
          'Application Support/com.hickory.hickory',
    );
    expect(
      legacyContainerDocumentsDirectory('/Users/x', 'com.hickory.hickory').path,
      '/Users/x/Library/Containers/com.hickory.hickory/Data/Documents',
    );
  });
}
```

These exact strings were verified against the live container on 2026-08-19; do not "tidy" them.

- [ ] **Step 2: Run it and watch it fail, then implement**

Run: `/opt/homebrew/bin/flutter test test/core/storage/app_directories_test.dart` → FAIL, then
implement both builders plus `appDataDirectory()`, which returns
`getApplicationSupportDirectory()` on macOS and, on Windows,
`getApplicationDocumentsDirectory()` for the database's sake — see the Global Constraints on
not moving Windows data.

- [ ] **Step 3: Point the database at it**

In `lib/data/drift/database.dart`, replace `getApplicationDocumentsDirectory()` with
`appDataDirectory()` and note in the comment why macOS and Windows differ.

- [ ] **Step 4: Run the migration in `main()`**

Before `final container = ProviderContainer();` — nothing may read storage first — and only on
macOS: resolve the three directories, call `migrateOutOfSandboxContainer`, `debugPrint` the
outcome (never file contents — the sync config and device id are not log material), and on
throw, keep the exception so the next step can surface it rather than starting empty.

- [ ] **Step 5: Surface a failed migration**

A migration that throws must not leave the user staring at an apparently empty app. Show a
blocking, dismissible message naming the container path and the manual download, using a new
l10n key `migrationFailedMessage` in all six locales. This is the one case where being loud
beats being tidy: silently starting fresh looks exactly like data loss.

- [ ] **Step 6: Verify**

Run: `/opt/homebrew/bin/flutter test && /opt/homebrew/bin/flutter analyze`
Expected: full suite green, no analyzer issues. Note that no automated test covers the
`main()` wiring — Task 5's manual checklist is what actually proves it.

- [ ] **Step 7: Commit** (only with the user's go-ahead)

```bash
git add lib/core/storage/app_directories.dart lib/main.dart lib/data/drift/database.dart lib/l10n test/core/storage/app_directories_test.dart
git commit -m "feat(storage): migrate out of the sandbox container on startup"
```

---

### Task 3: Remove the sandbox entitlement

**Files:**
- Modify: `macos/Runner/Release.entitlements`, `macos/Runner/DebugProfile.entitlements`

- [ ] **Step 1: Delete the entitlement**

Remove the `com.apple.security.app-sandbox` key and its `<true/>` from both files. Keep
`com.apple.security.network.client` (harmless unsandboxed) and leave every other key alone.

- [ ] **Step 2: Confirm the built app is no longer sandboxed**

```bash
/opt/homebrew/bin/flutter build macos --debug
codesign -d --entitlements - build/macos/Build/Products/Debug/hickory.app 2>&1 | grep -A2 app-sandbox
```

Expected: no `app-sandbox` key in the output. If it is still there, the build reused a cached
signature — `flutter clean` and rebuild before concluding anything.

- [ ] **Step 3: Verify the write probe now passes**

The whole point. With the debug build in place:

```bash
ls -ld /Applications
```

and confirm from the running app (Settings → check for updates) that the permission message no
longer appears. If it still does, stop and re-investigate rather than patching the probe —
that message is now telling the truth about something else.

- [ ] **Step 4: Commit** (only with the user's go-ahead)

```bash
git add macos/Runner/Release.entitlements macos/Runner/DebugProfile.entitlements
git commit -m "build(macos): drop the app sandbox so updates can install"
```

---

### Task 4: Keychain behavior for Jira and Personio credentials

**Files:**
- Modify (only if the check below shows it is needed): `lib/features/settings/`, `lib/l10n/*.arb`

This task is a **verification first**. The spec records it as an open risk, not a known
outcome: a sandboxed app's Keychain items are scoped by its application-identifier
entitlement, so the unsandboxed build may or may not still read them.

- [ ] **Step 1: Check against a copied container**

With the Task 3 build running against copied data (see Task 5 for how to set that up), open
Settings and look at the Jira and Personio sections.

- [ ] **Step 2: If the credentials are still there**

Nothing to build. Record the finding in `docs/memory/deployment.md` — including the macOS
version tested, since this is OS behavior — and move on.

- [ ] **Step 3: If they are gone**

Do not let it look like a sync bug. Detect the empty-credential case, show a one-time message
saying the credentials need re-entering after this update, and name it in the changelog as a
required manual step. Add the string to all six locales.

- [ ] **Step 4: Commit** (only with the user's go-ahead)

```bash
git commit -m "fix(sync): handle credentials the unsandboxed build cannot read"
```

---

### Task 5: Manual verification against copied data

No automated test can cover entitlements, `path_provider` resolution, or the Keychain. This
checklist is the actual proof and must be run before release.

- [ ] **Step 1: Copy the container — never work on the original**

```bash
cp -R ~/Library/Containers/com.hickory.hickory ~/Desktop/hickory-container-backup
```

Keep that copy until the whole checklist has passed. It is the only backup of the live data.

- [ ] **Step 2: Migration on real data**

Move `~/Library/Application Support/com.hickory.hickory` aside if it exists, run the
unsandboxed build, and confirm: entries, projects, clients and settings all appear; the new
directory exists and holds `hickory.sqlite`; the container is unchanged (compare against the
backup with `diff -r`).

- [ ] **Step 3: Second start does not re-copy**

Create an entry, restart, confirm it is still there — proving the stale container copy did not
overwrite the live database.

- [ ] **Step 4: Fresh install**

Move both the container and the new directory aside, start the app, confirm it comes up empty
without an error dialog, then restore.

- [ ] **Step 5: The actual bug — auto-update end to end**

Install the unsandboxed build into `/Applications`, publish a test release with a higher
version, and update from Settings. Confirm the app swaps, relaunches into the new version, and
still has its data. **This is the only step that proves the reported bug is fixed**; every
other step proves nothing was broken along the way.

- [ ] **Step 6: Record the results**

Write the outcomes into `docs/memory/deployment.md` — especially anything that behaved
differently from this plan's expectations.

---

### Task 6: Documentation and release notes

**Files:**
- Modify: `CHANGELOG.md`, `docs/memory/deployment.md`, `README.md`

- [ ] **Step 1: Changelog**

Under `## [Unreleased]`, in the user's own terms: automatic updates work on macOS again; data
moves out of the sandbox container automatically; **this one update has to be installed by
hand**, because the build that would deliver it is the broken one. Add the credential note if
Task 4 found one.

- [ ] **Step 2: Memory**

Update the `## macOS auto-update is blocked by the App Sandbox` section to say it is fixed,
with the migration's paths and the verified Keychain outcome.

- [ ] **Step 3: Readme**

Note under the macOS instructions that updating from a pre-fix version is a manual download.

- [ ] **Step 4: Commit** (only with the user's go-ahead)

```bash
git add CHANGELOG.md docs README.md
git commit -m "docs(update): document the sandbox removal and its manual step"
```
