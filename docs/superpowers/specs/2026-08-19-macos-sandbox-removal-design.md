# macOS Sandbox Removal & Data Migration — Design

Date: 2026-08-19
Status: Approved for planning

## 1. Problem

Auto-update is broken on macOS and cannot be fixed as long as the app is sandboxed.

Evidence gathered 2026-08-19 on the reporter's machine, running the released 1.2.0 from
`/Applications`:

| Check | Result |
|---|---|
| `com.apple.security.app-sandbox` in `macos/Runner/Release.entitlements` | `true` |
| Same on the installed bundle (`codesign -d --entitlements -`) | `true` |
| Sandbox container | `~/Library/Containers/com.hickory.hickory` exists |
| `/Applications` mode/owner | `drwxrwxr-x root:admin` |
| `hickory.app` owner | the reporter's own account |
| Account in `admin` group | yes |
| `mkdir /Applications/...` from a shell | succeeds |
| Same operation from inside the app | denied |

So POSIX permissions are fine and the sandbox is what denies the write. A sandboxed app
may only write inside its container, which never contains the installed bundle, so
`UpdateInstaller._ensureInstallDirWritable` fails for **every** install location — there is
no "writable place" to move the app to.

Removing the probe would not help: `quitAndSwap` launches the swap script with
`Process.start('/bin/sh', ..., mode: ProcessStartMode.detached)`
(`lib/core/update/update_installer.dart`), and a child process inherits its parent's
sandbox. The failure would just move past the point where the app can still report it.

Decision (with the reporter, 2026-08-19): **drop the App Sandbox.** The alternatives were
keeping the sandbox and degrading auto-update to a guided manual download, or a privileged
helper — the latter is not viable while sandboxed and unnecessary once it is gone, since the
bundle is owned by the installing user.

## 2. Scope

- Remove `com.apple.security.app-sandbox` from `macos/Runner/Release.entitlements` and
  `macos/Runner/DebugProfile.entitlements`.
- Migrate existing user data out of the container on first launch of the unsandboxed build.
- Handle credentials stored in the Keychain, whose access changes with the sandbox.
- Revisit the `settingsUpdateInstallErrorPermission` wording, which now names the sandbox.

Out of scope: signing and notarization (separate roadmap item), Windows (unaffected, its
updater already works), any change to the update mechanism itself.

## 3. The migration is the actual work

`path_provider` resolves differently depending on the sandbox, and the app uses **two**
directories — corrected 2026-08-19 while writing the plan, having first assumed the database
sat in Application Support:

| What | Call | Sandboxed (today) | Unsandboxed |
|---|---|---|---|
| Database `hickory.sqlite` | `getApplicationDocumentsDirectory()` (`data/drift/database.dart:99`) | `…/Containers/com.hickory.hickory/Data/Documents/` | **`~/Documents/`** |
| device id, sync config, window bounds, font cache | `getApplicationSupportDirectory()` | `…/Containers/…/Data/Library/Application Support/com.hickory.hickory/` | `~/Library/Application Support/com.hickory.hickory/` |

Verified 2026-08-19: both container paths hold live data (the database was 151 KB, modified
that morning) and **nothing exists outside the container**.

The Documents row is a problem beyond migration. Unsandboxed, `hickory.sqlite` would land
directly in the user's own `~/Documents` folder — visible, in every backup selection dialog,
and easy to delete by accident. So dropping the sandbox forces a second decision: on macOS the
database moves to Application Support, where application data belongs, and the migration
copies it there from the container's Documents directory. Windows keeps
`getApplicationDocumentsDirectory()`, because nothing forces its path to change and moving a
working install's database earns nothing but risk.
Shipping the entitlement change alone would therefore present every existing user with what
looks like a factory-reset app — database, device id, locale and sync configuration all
appear gone while actually sitting in the container.

### Migration behavior

On startup, before any provider reads the support directory:

1. Resolve the unsandboxed support directory (`target`).
2. If `target` already contains the database, do nothing — migration has run, or this is a
   fresh install.
3. Otherwise, look for the legacy container path (`source`), derived from the home directory
   and the bundle id rather than from `path_provider` (which no longer returns it).
4. If `source` exists, **copy** its contents to `target` — copy, not move, so an interrupted
   or failed migration leaves the old data intact and the previous build still runnable.
5. Record that the migration ran, and log its outcome at DEBUG without any file contents.
6. Never delete the container. Leave that to a later release, once the migration has proven
   itself in the wild.

A copy of a few megabytes on one startup is not worth a progress UI; a failure must surface
as a visible, actionable error rather than a silent empty app.

### Keychain

Jira and Personio credentials go through `flutter_secure_storage`. A sandboxed app's Keychain
items are scoped to its application-identifier entitlement, so an unsandboxed build may not
be able to read what the sandboxed one wrote. This is a **risk to verify before release**,
not a known outcome:

1. Build unsandboxed against a copy of a real container.
2. Check whether the stored credentials are still readable.
3. If they are not: detect the empty-credentials case, tell the user their Jira/Personio
   credentials need re-entering once, and name it in the changelog. Do not fail silently and
   do not treat it as a sync error.

## 4. What removing the sandbox costs

Stated plainly so the trade-off is on the record: the app loses OS-level containment. It
gains nothing else it did not already have — it already declares only `network.client`, and
the sync folder is user-chosen either way. For an app distributed outside the App Store this
matches what comparable self-updating Mac apps do, but it is a real reduction in blast radius
if the app is ever compromised. App Store distribution would require the sandbox back.

## 5. Verification

Automated tests cannot cover this: the behavior lives in entitlements, `path_provider`, and
the Keychain. The plan must therefore include a manual checklist run against a **copy** of a
real container, never the live one:

1. Unsandboxed debug build starts with the copied data visible (entries, projects, settings).
2. `~/Library/Application Support/com.hickory.hickory` exists afterwards and the container is
   untouched.
3. Second start does not copy again.
4. Fresh-install case: no container present, app starts empty without error.
5. Auto-update end to end: install 1.3.0 in `/Applications`, release a test build, update
   from Settings, confirm it swaps and relaunches into the new version with data intact.
6. Jira/Personio credentials: still present, or the re-entry path behaves as designed.

Item 5 is the whole point of this work and must be done on a real `/Applications` install, not
a debug run from the build directory.

## 6. Release considerations

The migration only runs when a user launches an unsandboxed build, which they can only get by
updating manually — the built-in updater cannot deliver it, since the currently installed
sandboxed build is what is broken. The release notes must say so: this one update has to be
installed by hand, and the ones after it will work from inside the app.
