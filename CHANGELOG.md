# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Add "Today" and "Yesterday" report presets, plus a combinable project and billable/non-billable filter that's remembered across restarts and respected by CSV export.

### Changed

- Reorganize Settings into a category list (General, Time tracking, Projects, Updates, Reset) with drill-down sub-pages, replacing the previous single flat stack of cards.

## [1.1.0] - 2026-08-07

### Added

- Add the ability to permanently delete a project, once archived or active, that no time entries reference — alongside the existing archive option.
- Add a "Reset everything" option in Settings that returns the device to a fresh-install state (clears all local data, forgets the sync folder, and clears Jira/Personio credentials) without affecting other devices in a shared sync folder.

## [1.0.2] - 2026-08-05

First public release. Consolidates the internal 1.0.0 and 1.0.1 milestones,
which were never distributed to users.

### Added

- Add live timer with start/stop/pause/resume, plus manual time entries with client, project, and tag assignment.
- Add reports screen with per-project totals, billable amounts, and CSV export in the user's configured date/time format.
- Add Jira integration: ticket autocomplete on time entries, worklog sync with per-entry status, and Jira credentials management via secure storage.
- Add file-based multi-device sync: point Hickory at any folder synced by iCloud Drive, Dropbox, Google Drive, or OneDrive; changes merge via a per-device, last-write-wins event log.
- Add automatic activity tracking with active-window and idle-time detection on macOS/Windows, including an idle-time keep/discard prompt.
- Add system tray integration (minimize/close to tray) and autostart-at-login support.
- Add localized UI in German, English, Spanish, French, Italian, and Dutch, with a user-configurable date/time display format.
- Add the Electric Violet visual theme.
- Add a GitHub Actions workflow that analyzes, tests, and builds macOS, Windows, Android, and iOS artifacts on every push to `main` and on demand.
- Add a tag-triggered release pipeline that publishes SHA256-checksummed macOS and Windows builds as GitHub Releases, plus an in-app updater that checks for new releases on startup and via a manual "Check for updates" button in Settings, and can download, verify, and install them automatically.

### Fixed

- Fix the Settings screen not being scrollable when its content overflows the window.
- Fix the in-app updater silently relaunching the unchanged app on macOS/Windows when it can't write to the install directory; it now fails with a clear, actionable message before quitting instead.

[Unreleased]: https://github.com/mordilion/Hickory/compare/v1.1.0...HEAD
[1.1.0]: https://github.com/mordilion/Hickory/compare/v1.0.2...v1.1.0
[1.0.2]: https://github.com/mordilion/Hickory/releases/tag/v1.0.2
