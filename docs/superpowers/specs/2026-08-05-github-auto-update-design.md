# GitHub Auto-Update — Design

Date: 2026-08-05
Status: Approved for planning

## 1. Goal & Scope

Let Hickory check GitHub for a newer release, and — on macOS/Windows, where the app
ships as a portable zip rather than through an app store — download, verify, and
install it automatically, then relaunch. This is two connected pieces of work:

1. **A release pipeline that doesn't exist yet.** The current `.github/workflows/build.yml`
   builds all four platforms on every push to `main`, but only uploads ephemeral,
   non-public GitHub Actions *artifacts* — there are no git tags and no GitHub
   *Releases* with permanent download URLs. This design adds a second workflow that
   publishes real releases.
2. **An in-app updater** that polls the GitHub Releases API, and on macOS/Windows
   can fetch, verify, and self-install the update.

Explicit scope decisions from brainstorming:
- The in-app update check/install only runs on **macOS and Windows** — the only
  platforms with a portable, non-store distribution. iOS/Android updates stay on
  their respective app stores; self-updating outside a store is blocked on iOS and
  not attempted on Android.
- The new `release.yml` workflow **only builds and publishes macOS and Windows** —
  Android/iOS keep using the existing `build.yml` CI artifacts, not full releases,
  since nothing consumes an Android/iOS release asset.
- No code-signing/notarization work here — the macOS/Windows builds are unsigned,
  same as today's CI builds. (Gatekeeper/SmartScreen warnings on a fresh download
  are a pre-existing condition of this project, not something this feature changes
  or is required to fix.)
- Built by hand against GitHub's public Releases REST API, **not** a third-party
  package like `auto_updater` (Sparkle/WinSparkle) — that would require a signed
  update feed (EdDSA key pair, `appcast.xml`, DMG packaging) this project has no
  other reason to stand up. Matches the existing house pattern of small,
  purpose-built HTTP clients (`HttpJiraClient`, `HttpPersonioClient`) over adopting
  a heavier framework.
- Update checks run automatically on startup (silent unless an update is actually
  found) plus a manual "Check for updates" action in Settings.
- Installing is opt-in per update: the user must click "Install" after seeing the
  version/release notes. Once clicked, download → verify → extract → relaunch
  proceeds without further prompts ("fully automatic" refers to this — not to
  installing without the user ever seeing it).
- Assumes the install directory is user-writable (true for a manually-extracted
  portable zip in a normal location). An install placed somewhere requiring
  elevation (e.g. `Program Files`) is out of scope — the update will fail with a
  clear error rather than silently prompting for admin rights.

## 2. Release Pipeline

### New workflow: `.github/workflows/release.yml`

Triggered by `on: push: tags: ['v*']` (matches the tag format the existing
CHANGELOG.md already references, e.g. `v1.0.0`). Needs `permissions: contents:
write` (unlike `build.yml`'s read-only permissions) to create a release.

Jobs:
1. **`verify-version`**: reads `pubspec.yaml`'s `version:` field (the part before
   `+buildNumber`) and compares it against the pushed tag (stripped of its leading
   `v`). Fails the workflow on mismatch — a cheap guard against tagging a release
   under the wrong declared version, which would otherwise silently break the
   in-app version-compare logic (Section 3).
2. **`build-macos`** / **`build-windows`** (each `needs: verify-version`): identical
   build+package steps to `build.yml`'s existing `build-macos`/`build-windows` jobs,
   plus a checksum step:
   - macOS: `shasum -a 256 hickory-macos.zip` → write **only the lowercase hex
     digest** (no filename column) to `hickory-macos.zip.sha256`.
   - Windows: `(Get-FileHash -Algorithm SHA256 hickory-windows.zip).Hash.ToLower()`
     → same bare-hex-digest format, written to `hickory-windows.zip.sha256`.
   - Both the zip and its `.sha256` file are uploaded as build artifacts for the
     next job to pick up.
3. **`publish`** (`needs: [build-macos, build-windows]`, `runs-on: ubuntu-latest`):
   downloads both artifacts, extracts the relevant section from `CHANGELOG.md`
   (the block under the heading matching the tag's version, e.g. `## [1.0.1]`) as
   the release body, and creates the GitHub Release via `softprops/action-gh-release`
   (pinned by commit SHA, matching this repo's existing action-pinning convention)
   with all 4 files attached: `hickory-macos.zip`, `hickory-macos.zip.sha256`,
   `hickory-windows.zip`, `hickory-windows.zip.sha256`. Uses the default
   `GITHUB_TOKEN` — no new secrets needed.

### Release checklist (manual, unchanged by this feature)

Bump `pubspec.yaml`'s version, move the `CHANGELOG.md` `[Unreleased]` section under
a new `## [X.Y.Z] - YYYY-MM-DD` heading, commit, tag `vX.Y.Z`, push the tag. Out of
scope: automating the version bump/changelog move itself.

## 3. In-App Update Check

### `lib/core/update/github_release_client.dart`

```dart
class GithubRelease {
  const GithubRelease({required this.version, required this.notes, required this.assets});
  final String version; // tag_name with leading "v" stripped
  final String notes;   // release body (markdown)
  final List<GithubReleaseAsset> assets;
}

class GithubReleaseAsset {
  const GithubReleaseAsset({required this.name, required this.downloadUrl, required this.size});
  final String name;
  final String downloadUrl;
  final int size;
}

class GithubReleaseClient {
  /// GET https://api.github.com/repos/mordilion/Hickory/releases/latest --
  /// public, unauthenticated (60 req/hour/IP, far more than a startup-once
  /// check needs). Returns null on a 404 (no releases published yet).
  Future<GithubRelease?> fetchLatestRelease();
}
```

### `lib/core/update/update_checker.dart`

Compares `GithubRelease.version` (semver `major.minor.patch`, no pre-release
handling needed — this project doesn't use pre-release tags) against
`PackageInfo.fromPlatform().version` (the current running version). Picks the
release asset whose name matches the current platform (`hickory-macos.zip` /
`hickory-windows.zip`) and its `.sha256` sidecar asset. Returns an `UpdateInfo`
(version, notes, asset download URL, checksum asset URL, size) when a newer
version with a matching asset exists, else `null`. On any network/parse failure,
returns `null` rather than throwing — a failed background check must never
surface as an error the user didn't ask for (the manual "Check for updates" button
gets its own explicit error message instead, see Section 5).

## 4. Download, Verify, Install

### `lib/core/update/update_installer.dart`

Only reachable when `Platform.isMacOS || Platform.isWindows`. Sequence, run from
the "Install" button tap:

1. **Download** the zip asset and its `.sha256` sidecar to a temp directory
   (`path_provider`'s temp dir).
2. **Verify**: compute the downloaded zip's SHA256 (`crypto` package — new
   dependency) and compare against the sidecar's content. Abort with an error on
   mismatch; nothing about the running install is touched yet.
3. **Extract** the verified zip into a fresh directory,
   `<system temp>/hickory_update_<timestamp>/`, using the `archive` package (new
   dependency — no zip/archive handling exists in this codebase yet). Sanity-check
   the extracted directory actually contains an executable
   (`hickory.exe`/`hickory` at the expected relative path) before proceeding —
   a corrupt-but-checksummed-correctly archive should still fail loudly here
   rather than mid-swap.
4. **Locate the current install directory**: `File(Platform.resolvedExecutable).parent`
   on Windows (the folder containing `hickory.exe` and its `data/` folder, matching
   exactly what `build.yml`/`release.yml` zip up). On macOS, walk up from
   `Platform.resolvedExecutable` (`.../Hickory.app/Contents/MacOS/hickory`) three
   segments to the `.app` bundle root — a stable, well-known bundle-layout
   convention, safe to rely on directly.
5. **Write a relaunch/swap script** to a temp file (PowerShell `.ps1` on Windows,
   shell `.sh` on macOS — see below), passing it: the current process id, the
   extracted-update directory, the current install directory, and the path to
   relaunch. Launch it detached (`Process.start(..., mode: ProcessStartMode.detached)`).
6. **Quit through the existing quit path**: call the same `onBeforeQuit` hook
   `WindowTrayController`'s tray-menu quit uses (finalizes a paused entry the same
   way a normal quit already does — see `quit_behavior.dart`; a *running*,
   non-paused entry is deliberately left alone and survives the restart exactly
   like it survives any other app restart today), then exit.
7. **The detached script**, once the app process has fully exited:
   - Waits for the given PID to exit (`Wait-Process -Id <pid> -Timeout 30` on
     Windows; a `kill -0`-polling loop on macOS).
   - Renames the current install directory to `<install dir>_old_<timestamp>`
     (not delete-then-copy — a rename is atomic-ish and leaves the previous
     version intact if anything goes wrong before this point).
   - Renames the extracted update directory to the original install directory
     path.
   - Deletes the `_old_` backup.
   - Relaunches the app from the new install directory.
   - Deletes itself (a `.bat`/`.ps1` self-delete trick on Windows; a plain `rm`
     of its own path at the end on macOS).

This is the highest-risk part of the whole feature (it's the only piece that
deletes/replaces real files outside a temp directory) — steps 1–4 are entirely
reversible/non-destructive and can fail safely with the app still running
normally; only step 7, which only ever runs after the old app has fully exited,
touches the real install.

## 5. UI

### Settings screen — new "Updates" section

New `Card` in `settings_screen.dart`:
- Current version (`PackageInfo.version`), read-only text.
- "Check for updates" button (`OutlinedButton`) — manual trigger, shows a
  transient status message (checking / up to date / error) the same way the Sync
  screen's Jira/Personio sections do.
- When an update is available (either from the manual check or the silent
  startup check): a banner showing the new version + release notes (scrollable if
  long) + an "Install" button. Tapping "Install" runs the sequence in Section 4,
  with a progress indicator (downloading → verifying → extracting → installing)
  replacing the button while in flight.

### Startup check

`main()` kicks off `UpdateChecker.check()` fire-and-forget after `runApp()` (never
blocks startup) using the same `personioLatestSyncedAtProvider`-style plain
`FutureProvider` pattern. If it finds an update, the same banner described above
appears (wherever the user currently is in the app) rather than only inside
Settings — a `StateProvider`-held "available update" value, read from both the
Settings screen and a small persistent banner/snackbar at the app-shell level.

### Riverpod

`lib/core/di/update_providers.dart`: `githubReleaseClientProvider`,
`updateCheckerProvider`, and an `availableUpdateProvider` (plain state, set once
by the startup check or the manual button, consumed by both the Settings card and
the app-shell banner).

## 6. Testing

- `github_release_client_test.dart`: mocked `http.Client` (same `MockClient`
  pattern as `http_personio_client_test.dart`), covering a successful parse, a 404
  (no releases yet → null), and a malformed-JSON response (→ null, doesn't throw).
- `update_checker_test.dart`: version-compare cases (older/equal/newer tag vs.
  current version), asset-matching per platform, missing-matching-asset case,
  network-failure-returns-null case.
- `update_installer_test.dart`: checksum verification (matching / mismatching
  sidecar content), extraction into a temp dir with a real small test zip fixture,
  and the "extracted directory must contain the expected executable" sanity check
  — using real file I/O against temp directories, not mocks, matching this
  codebase's established testing convention. The relaunch script's own behavior
  (steps that only run after the real app process has exited) is **not**
  automatable and is called out as a manual verification step in the
  implementation plan, the same way `resizable-window`'s plan flagged
  `WindowTrayController`'s real-window behavior as manual-only.
- No widget test for the new Settings card or app-shell banner, matching this
  codebase's existing precedent (`sync_screen.dart`'s Jira/Personio sections have
  no widget tests either — see the Personio design's identical reasoning).

## 7. Out of Scope

Code signing/notarization; delta/incremental updates (always downloads the full
zip); rollback UI (the `_old_` backup is deleted immediately after a successful
swap, not offered as a "revert" option); update channels (stable-only, no
beta/pre-release track); installs in a location requiring elevated permissions;
automating the version-bump/changelog/tag release checklist itself; Linux (no
existing build target); any change to `build.yml`'s existing CI-artifact behavior.
