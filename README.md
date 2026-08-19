# Hickory

A local-first, privacy-friendly time tracking desktop app with Jira worklog sync, automatic activity tracking, and multi-device sync over your own cloud storage folder (iCloud Drive, Dropbox, Google Drive, OneDrive, ...) — no server or account required.

[![Build Artifacts](https://github.com/mordilion/Hickory/actions/workflows/build.yml/badge.svg)](https://github.com/mordilion/Hickory/actions/workflows/build.yml)
![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)
![Platform: macOS | Windows](https://img.shields.io/badge/platform-macOS%20%7C%20Windows-lightgrey.svg)
![Flutter](https://img.shields.io/badge/flutter-3.38%2B-02569B.svg?logo=flutter)

## Features

- **Timer & manual entries** — start/stop/pause/resume a live timer, or add manual entries with client, project, and tags.
- **Automatic activity tracking** — desktop idle detection (macOS/Windows) prompts you to discard or keep idle time.
- **Drill-down entries overview** — years, then months, then one calendar week with its date range; a week lists its days with their entries, and every row carries the worked and break time below it, flagging days whose break falls short of the configured rule.
- **Reports & CSV export** — per-project totals and billable amounts, exportable as CSV in your preferred date/time format.
- **Jira integration** — link time entries to Jira tickets (with autocomplete) and sync them as worklogs; per-entry sync status is shown inline.
- **File-based multi-device sync** — point Hickory at a folder already synced by iCloud Drive, Dropbox, Google Drive, or OneDrive; a per-device, last-write-wins event log merges changes without a backend.
- **System tray & autostart** — runs quietly in the tray, minimizes instead of quitting, and can launch at login.
- **Self-updating** — Settings → Updates checks GitHub Releases, verifies the download's SHA256, and swaps the installation in place (macOS/Windows).
- **Localized UI** — available in German, English, Spanish, French, Italian, and Dutch, with a user-configurable date/time format.

## Tech Stack

| Layer | Technology |
|---|---|
| App framework | [Flutter](https://flutter.dev) (desktop targets: macOS, Windows) |
| State management | [Riverpod](https://riverpod.dev) (code generation) |
| Local storage | [Drift](https://drift.simonbinder.eu) (SQLite) |
| Sync | Custom file-based event log (`packages/sync_engine`), watched via `packages/storage_access` |
| Activity tracking | Native macOS/Windows plugin (`packages/activity_tracker`) |
| Jira integration | REST API via `http`, credentials in `flutter_secure_storage` |

## Getting Started

### Prerequisites

- [Flutter](https://docs.flutter.dev/get-started/install) stable channel with Dart `^3.12.2` — the constraint `pubspec.yaml` enforces; anything newer on stable works
- macOS 12+ or Windows for the desktop-only features (activity tracking, folder sync); other platforms are not currently supported
- A Jira Cloud account with an [API token](https://id.atlassian.com/manage-profile/security/api-tokens) if you want to use the Jira sync feature (optional)

### Pre-built artifacts

Every push to `main` builds macOS, Windows, Android, and iOS artifacts via [GitHub Actions](.github/workflows/build.yml); download them from a workflow run's [Artifacts](https://github.com/mordilion/Hickory/actions/workflows/build.yml) list. There is no signed release yet:
- macOS and Windows builds are unsigned but runnable.
- The Android APK is signed with the Flutter debug keystore (not suitable for distribution).
- The iOS build is unsigned (`--no-codesign`) and needs re-signing before it can be installed on a device.

Updating is normally handled in-app (Settings → Updates). One exception: **coming from 1.3.0 or
earlier on macOS, that first update has to be installed by hand.** Those builds were sandboxed
and could not replace themselves — which is exactly what 1.3.1 fixed, so the broken version is
the one that would have had to deliver the fix. Every update from 1.3.1 onwards installs itself.

Because the macOS build is unsigned and not notarized, Gatekeeper quarantines the downloaded `.app` and refuses to open it, reporting it as "damaged" or "can't be opened" (the app itself is fine — this is macOS's quarantine flag on unsigned downloads). Clear the flag before launching:

```bash
xattr -cr /path/to/hickory.app
```

### Installation

```bash
git clone https://github.com/mordilion/Hickory.git
cd Hickory
flutter pub get
```

### Running

```bash
# macOS
flutter run -d macos

# Windows
flutter run -d windows
```

### Building a release

```bash
flutter build macos   # produces build/macos/Build/Products/Release/hickory.app
flutter build windows # produces build/windows/x64/runner/Release/hickory.exe
```

### Tests & static analysis

```bash
flutter analyze
flutter test
```

## Configuration

- **Sync folder**: Settings → Sync lets you choose a folder that's already synced by your cloud provider of choice. Hickory writes a per-device JSONL event log there and merges changes on start and on file-system change events.
- **Jira**: Settings → Sync → Jira Integration. Provide your Jira base URL, account email, and an API token; credentials are stored using the OS-native secure keychain (`flutter_secure_storage`), never in plain text or logs.

- **Where your data lives**: the database and local state sit in the application-support directory — `~/Library/Application Support/com.hickory.hickory` on macOS, `%USERPROFILE%\Documents` on Windows. Versions up to 1.3.0 ran sandboxed on macOS and kept everything in `~/Library/Containers/com.hickory.hickory`; 1.3.1 copies it out on first start and leaves the container untouched, so the old version stays usable if you need to go back.

## Project Structure

```
lib/
├── core/       # DI, theming, formatting, window/tray, locale helpers
├── data/       # Drift database, DAOs, sync engine integration
├── features/   # Feature-first UI: timer, entries, projects, reports, jira, sync, settings, shell
└── l10n/       # ARB-based localization (app_de.arb is the source locale)
packages/
├── sync_engine/     # Pure-Dart event log codec and last-write-wins merge
├── storage_access/  # Cross-platform sync-folder picker/watcher
└── activity_tracker/ # macOS/Windows active-window and idle-time plugin
```

## Contributing

Contributions are welcome — please read [CONTRIBUTING.md](CONTRIBUTING.md) for the development workflow, coding conventions, and how to submit a pull request. By participating, you agree to uphold the [Code of Conduct](CODE_OF_CONDUCT.md).

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for a history of notable changes.

## License

Hickory is licensed under the [MIT License](LICENSE).
