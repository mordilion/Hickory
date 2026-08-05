# Deployment & Release Process

## Versioning

- Single source of truth: `version:` in `pubspec.yaml` (format `X.Y.Z+build`).
- Release notes source: `CHANGELOG.md`, Keep-a-Changelog format. Entries live under `[Unreleased]` during development and get moved into a new `## [X.Y.Z] - YYYY-MM-DD` section when releasing.

## Release steps

1. Set the new version in `pubspec.yaml`.
2. Move the relevant `[Unreleased]` entries in `CHANGELOG.md` into a new `## [X.Y.Z] - YYYY-MM-DD` section.
3. Push a Git tag `vX.Y.Z` — this triggers `.github/workflows/release.yml`.

## CI: `.github/workflows/release.yml` (trigger: tag push `v*`)

- **verify-version**: fails the run if the pushed tag version doesn't match `pubspec.yaml`'s version.
- **build-macos**: `flutter build macos --release`, zips `hickory.app` → `hickory-macos.zip`, computes `hickory-macos.zip.sha256`.
- **build-windows**: `flutter build windows --release`, zips the release folder → `hickory-windows.zip`, computes `hickory-windows.zip.sha256`.
- **publish** (needs both builds): downloads both artifacts, extracts the matching version section from `CHANGELOG.md` via `awk` as release notes, publishes a GitHub Release (name = tag) with the ZIPs + checksum files attached.
- Android/iOS are **not** built or published by this workflow.

## CI: `.github/workflows/build.yml` (trigger: push to `main`, manual)

- Analyze, test, and build macOS, Windows, Android, and iOS artifacts. No GitHub Release is published — this is verification-only CI, separate from the release pipeline.

## In-app auto-update

- Implemented in `lib/core/update/` (`UpdateChecker`, `UpdateInstaller`) with providers in `lib/core/di/update_providers.dart`.
- Checks GitHub Releases on app startup and via the "Check for updates" button in Settings (`lib/features/settings/settings_screen.dart`).
- On update: downloads the platform ZIP, verifies its SHA256 checksum against the `.sha256` file from the release, extracts, and swaps the installation.
- Only wired up for macOS/Windows (`Platform.isMacOS || Platform.isWindows` gate in the settings screen) — matches the platforms actually built by the release workflow.

## Gotchas

- Tag version and `pubspec.yaml` version must match exactly (`vX.Y.Z` vs `X.Y.Z`) or `verify-version` blocks the whole pipeline.
- The `awk` changelog extraction in `publish` depends on the `## [X.Y.Z]` heading existing in `CHANGELOG.md` *before* the tag is pushed — release notes will be empty otherwise.
- `UpdateInstaller.quitAndSwap` swaps the install directory from a *detached* shell/PowerShell script that only runs after the app process has fully exited — it has no way to report failure back to the Flutter UI. Because of this, `prepareUpdate()` verifies write access to the install directory's parent *before* the app quits (probes by creating+deleting a throwaway directory there); a failure throws `UpdateInstallPermissionException`, which the Settings screen shows as a specific, actionable message instead of the generic install-failed one. Without this check, a permission failure (e.g. `/Applications` on a non-admin macOS account) made the relaunch script's swap fail silently and its unconditional `open`/`Start-Process` at the end just relaunched the unchanged old app — from the user's perspective, "the app closes and immediately reopens" with no error and no update applied.
