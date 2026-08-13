# Roadmap

This roadmap tracks the themes planned for upcoming Hickory versions. It is driven by one
current goal — **broader distribution** — and is revisited whenever priorities shift.

Each version below gets its own design/plan cycle when work actually starts on it; this
document only captures the agreed sequencing and scope at a high level.

## v1.3 — Trust

**Goal:** remove the biggest friction point for new users: unsigned builds. Pursuing a
free-first path before spending money — see `docs/memory/deployment.md` for the full
runbook.

- macOS: self-hosted Homebrew tap with automatic de-quarantine as a free interim
  mitigation; real notarization (Apple Developer Program, `notarytool`) stays blocked on
  the $99/year fee until/unless that gets funded
- Windows: apply to SignPath.io Foundation for free code signing; Azure Trusted Signing
  as a paid fallback if that doesn't work out
- Update README installation instructions once the Homebrew tap and/or real signing are
  in place

## v1.4 — Migration

**Goal:** make switching to Hickory from another time tracker low-friction.

- Generic CSV import for time entries, including duplicate detection and project/client
  mapping during import
- Documentation: "Switching from Toggl/Clockify to Hickory"

## v1.5 — Visibility

**Goal:** get Hickory discoverable where people already look for apps.

- Mac App Store listing (depends on v1.3 signing; needs sandboxing/entitlements review)
- Microsoft Store listing (MSIX packaging)
- Landing page skeleton — not version-bound, can start anytime in parallel
- Store listing copy, screenshots, feature list — not version-bound, can start anytime in
  parallel; publishing still waits on the store-specific packaging work above

## Backlog / later

Ideas that came up but aren't scheduled into a version yet:

- Mobile (Android/iOS) or Linux desktop support
- Global hotkey to start/stop/pause the timer from anywhere, tray quick-start for the last
  project
- Reminder notifications (timer running very long, forgot to start)
- PDF export / simple invoicing on top of the existing CSV export
- Calendar/week view and richer report grouping (by client, by tag)
- Sync conflict visibility/history, encryption of the sync folder's event log
