# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

- Fix Windows crashing every time the app is quit from the tray menu, and at the end of an in-app update. The window was torn down in an order that let Flutter's shutdown reach back into itself, so Windows killed the process instead of letting it exit. Quitting and updating now end cleanly.

## [1.5.0] - 2026-09-11

### Fixed

- Count absence days in days rather than in records: a half day counted as a whole one, so eleven entries with one half day among them read as 11 instead of 10.5. A recorded time range now counts its share of that day.

### Added

- Name the days behind the tracking-quality counts: tapping "work days with no booking" or "days with too short a break" in the Reports tab unfolds the dates, so the figure says where to go and not only that something is wrong.
- Add a floating timer pill: while a timer runs, the window collapses to a small always-on-top pill with the elapsed time, client and project, and pause/stop/expand controls

## [1.4.1] - 2026-09-09

### Fixed

- Fix updating from 1.3.x to 1.4.0 leaving the app on an endless spinner. The database upgrade added a column to a table the same run had just created, which failed and left the database unopened. Upgrades now run as one transaction and repair a database that 1.4.0 already left half-migrated, so no data is lost and no reinstall is needed.

## [1.4.0] - 2026-09-08

### Added

- Show a progress bar while an update installs: a real percentage with megabytes during the download, then a labelled bar for verifying the checksum and unpacking, which cannot report progress.
- Name what failed on the Sync tab. Under each service's result, the entries whose last push failed are listed with their date and the stored reason, and tapping one opens it for editing — the counts said that something went wrong but never what or where. The list is driven by the stored state, so a failure from an automatic background run shows up too.
- Show each entry's Personio state in the list, next to the Jira one: a calendar icon that is green once the entry has been recorded and red when the push failed, carrying the reason. Entries that were never pushed stay unmarked — Personio has no per-entry opt-in, so an icon on every row would say nothing.
- Set a target work time under Settings → Work time & balance, either as seven daily figures or as one weekly figure spread over the days you pick. Until now the app had nothing to measure tracked time against, so it could not say whether a week was over or under. The same screen holds the yearly cutoff rule: the balance can carry on untouched, be reset to zero on a date you choose, or be carried over capped at an upper and a lower bound.
- Show the flex-time balance at the top of the Reports tab, counted from the last cutoff and always signed, so a surplus and a deficit cannot be confused. It covers every entry regardless of the tab's filters — "overtime, but only for project X" is not a meaningful number — and says so while a filter is active. With no target set yet it points at the settings screen instead of reading every tracked minute as overtime.
- Absences can be recorded from the main screen against freely defined types, each marked paid or unpaid, and count toward the work-time balance accordingly. Recording is off by default; with it on, a work day with neither a booking nor an absence shows up as a deficit.
- Correct a recorded absence from its row in the entries list: type, extent, time range and note. Until now a mistyped absence could only be deleted and entered again, once per day of a vacation.

### Fixed

- Refuse deleting an absence type that days still use from anywhere in the app, not just from the settings screen it was checked in.
- Refuse an absence whose time range ends when it starts. It was written as a row worth no time at all while the form reported it as recorded.
- Keep the caret in place in the work-time settings fields. Refreshing a field — most visibly when a work-day toggle redistributes the weekly figure — sent the cursor to the end of it.

### Changed

- Book to Jira on its own. The reconciliation now runs at app start and, coalesced into one run per few seconds, after every entry that is created, stopped, edited or deleted — until now it only ever ran when the user pressed the button on the Sync tab, so an edit to an already-booked entry never reached Jira. It stays silent: the outcome shows up in each entry's status icon, and nothing happens at all while Jira is unconfigured.
- Name the reason a Jira booking failed. The entry's red cloud icon carries the stored error message instead of the generic "Jira booking failed", which stays the tooltip for a failure recorded before this version.
- Chart worked time against the target in the Reports tab, each bar coloured by how the period stands: the target met or beaten, short of it, or a day that was never owed. Time covered by a paid absence is stacked on top in a lighter shade, so a day off reaches the target line without looking like it was worked. One bar per day, per week once the range grows past about two months, per month past two years, with the target as a line across it. Each bar carries its period and both figures for screen readers and on hover.
- Show money and billability in the Reports tab: the billable share of tracked time, revenue per currency, and the clients it came from. This block follows the tab's filters, unlike the balance.
- Show what the tracking is missing: work days with no booking, days whose break falls short of the configured rule, entries a push could not deliver, and absence days per type.
- Show three more figures beside the flex-time balance in the Reports tab: the balance within the selected range, target against actual with a progress bar, and the average per work day. They follow the range chips but none of the filters — "overtime, but only for project X" is not a meaningful number.
- Correct the balance by hand under Reports → Correction: a signed number of hours against a date, with a reason. Every correction stays listed and can be taken back, instead of history being rewritten.
- Say which half a half-day absence covers, morning or afternoon. Half days recorded before this stay as they are and are still credited half the day's target.
- Record an absence over a time range that crosses days: the range now carries a from and a to date beside its two times, read as one continuous absence — the first day from its start time, the days between whole, the last day up to its end time.
- Give the absence form the same shape as the timer and manual modes: one card, the note first, the same date and time buttons, and the same full-width submit button. Its dates and times now follow the formats set under Settings — it used the system locale and a 24-hour clock of its own, so the same moment read differently depending on which mode wrote it.
- Keep the standard absence types reachable. The button that creates them stayed hidden once any type existed; it now stays put and skips every name already in the list.

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

[Unreleased]: https://github.com/mordilion/Hickory/compare/v1.4.1...HEAD
[1.4.1]: https://github.com/mordilion/Hickory/compare/v1.4.0...v1.4.1
[1.4.0]: https://github.com/mordilion/Hickory/compare/v1.3.2...v1.4.0
[1.2.0]: https://github.com/mordilion/Hickory/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/mordilion/Hickory/compare/v1.0.2...v1.1.0
[1.0.2]: https://github.com/mordilion/Hickory/releases/tag/v1.0.2
