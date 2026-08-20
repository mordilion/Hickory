# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Show a progress bar while an update installs: a real percentage with megabytes during the download, then a labelled bar for verifying the checksum and unpacking, which cannot report progress.

### Changed

- Book to Jira on its own. The reconciliation now runs at app start and, coalesced into one run per few seconds, after every entry that is created, stopped, edited or deleted — until now it only ever ran when the user pressed the button on the Sync tab, so an edit to an already-booked entry never reached Jira. It stays silent: the outcome shows up in each entry's status icon, and nothing happens at all while Jira is unconfigured.
- Name the reason a Jira booking failed. The entry's red cloud icon carries the stored error message instead of the generic "Jira booking failed", which stays the tooltip for a failure recorded before this version.

## [1.3.2] - 2026-08-19

### Fixed

- Correct the update error message on macOS. Since 1.3.1 removed the sandbox, the message still blamed it — it now names the folder it could not write to and the likely reason, the app belonging to a different user account.

## [1.3.1] - 2026-08-19

### Fixed

- Fix automatic updates on macOS. The app no longer runs in the App Sandbox, which was what prevented it from replacing itself, and it carries existing data over to its new location on first start. This one update has to be installed by hand — the version that would have delivered it is the one that cannot. Check the Sync tab afterwards: if the Jira or Personio fields are empty, enter the credentials once more.
- Explain the real reason automatic updates fail on macOS. The message used to suggest moving the app to a writable folder, which cannot work: the sandboxed build may only write inside its own container, so it now points at the manual download instead.

## [1.3.0] - 2026-08-19

### Added

- Add a drill-down hierarchy to the entries overview: years contain months, months contain calendar weeks with their date range, and a week lists its days with their entries. Every row shows the worked and break time below it, and a breadcrumb navigates back up. The app opens on the current week.

### Changed

- Raise the minimum macOS version to 12.0. The current Flutter toolchain requires it, so macOS 10.15 and 11 are no longer supported.
- Give the manual entry's add button the same full-width gradient pill styling as the timer's Start button, replacing the small round icon button.
- Make the end of a manual entry follow its start: picking a start date pulls the end date onto the same day, and picking a start time shifts the end time by the same amount, so the entry keeps its duration and the end fields rarely need touching. Picking an end date or time still only changes the end.

## [1.2.0] - 2026-08-09

### Added

- Add "Today" and "Yesterday" report presets, plus a combinable project and billable/non-billable filter that's remembered across restarts and respected by CSV export.

### Changed

- Reorganize Settings into a category list (General, Time tracking, Projects, Updates, Reset) with drill-down sub-pages, replacing the previous single flat stack of cards.
- Make the Jira and Personio sections on the Sync screen collapsible, and remove the default divider lines for a cleaner look.

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

[Unreleased]: https://github.com/mordilion/Hickory/compare/v1.2.0...HEAD
[1.2.0]: https://github.com/mordilion/Hickory/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/mordilion/Hickory/compare/v1.0.2...v1.1.0
[1.0.2]: https://github.com/mordilion/Hickory/releases/tag/v1.0.2
