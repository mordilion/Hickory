# Roadmap

This roadmap tracks the themes planned for upcoming Hickory versions. It is driven by one
current goal — **broader distribution** — and is revisited whenever priorities shift.

Each version below gets its own design/plan cycle when work actually starts on it; this
document only captures the agreed sequencing and scope at a high level.

## v1.3 — Migration

**Goal:** make switching to Hickory from another time tracker low-friction.

- Generic CSV import for time entries, including duplicate detection and project/client
  mapping during import
- Documentation: "Switching from Toggl/Clockify to Hickory"

## v1.4 — Visibility

**Goal:** get Hickory discoverable where people already look for apps.

- Microsoft Store listing (MSIX packaging) — Microsoft signs the package during store
  certification, so this does **not** depend on v1.5's own code signing
- Mac App Store listing — blocked on v1.5 (needs our own signing plus a
  sandboxing/entitlements review), so out of scope until then
- Landing page skeleton — not version-bound, can start anytime in parallel
- Store listing copy, screenshots, feature list — not version-bound, can start anytime in
  parallel; publishing still waits on the store-specific packaging work above

## v1.5 — Trust

**Goal:** remove the friction of unsigned builds. Pushed behind Migration/Visibility
because every real option here has an external dependency outside our control (Apple's
paid enrollment + identity verification, SignPath's application/approval, or a paid
Windows cert) — revisit once there's bandwidth to sit through those processes.

- macOS: self-hosted Homebrew tap with automatic de-quarantine as a free interim
  mitigation; real notarization (Apple Developer Program, `notarytool`) stays blocked on
  the $99/year fee until/unless that gets funded
- Windows: apply to SignPath.io Foundation for free code signing; Azure Trusted Signing
  as a paid fallback if that doesn't work out
- Update README installation instructions once the Homebrew tap and/or real signing are
  in place
- Prep already done, execution on hold: Homebrew cask built locally
  (`../homebrew-hickory`, not yet pushed to GitHub), SignPath eligibility + GitHub Actions
  integration researched and documented in `docs/memory/deployment.md`

## Backlog / later

Ideas that came up but aren't scheduled into a version yet:

- Mobile (Android/iOS) or Linux desktop support
- Global hotkey to start/stop/pause the timer from anywhere, tray quick-start for the last
  project
- Reminder notifications (timer running very long, forgot to start)
- PDF export / simple invoicing on top of the existing CSV export
- Calendar/week view and richer report grouping (by client, by tag)
- Sync conflict visibility/history, encryption of the sync folder's event log
