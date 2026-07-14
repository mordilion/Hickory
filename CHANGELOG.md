# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Add a GitHub Actions workflow that analyzes, tests, and builds macOS, Windows, Android, and iOS artifacts on every push to `main` and on demand.

## [1.0.0] - 2026-07-14

### Added

- Add live timer with start/stop/pause/resume, plus manual time entries with client, project, and tag assignment.
- Add reports screen with per-project totals, billable amounts, and CSV export in the user's configured date/time format.
- Add Jira integration: ticket autocomplete on time entries, worklog sync with per-entry status, and Jira credentials management via secure storage.
- Add file-based multi-device sync: point Hickory at any folder synced by iCloud Drive, Dropbox, Google Drive, or OneDrive; changes merge via a per-device, last-write-wins event log.
- Add automatic activity tracking with active-window and idle-time detection on macOS/Windows, including an idle-time keep/discard prompt.
- Add system tray integration (minimize/close to tray) and autostart-at-login support.
- Add localized UI in German, English, Spanish, French, Italian, and Dutch, with a user-configurable date/time display format.
- Add the Electric Violet visual theme.

[Unreleased]: https://github.com/mordilion/Hickory/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/mordilion/Hickory/releases/tag/v1.0.0
