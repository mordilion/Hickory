# Collapsible Jira/Personio Sync Sections — Design

Date: 2026-08-09
Status: Approved for planning

## Goal & Scope

The Jira and Personio integration cards on `SyncScreen` (`lib/features/sync/sync_screen.dart`)
are always fully expanded, taking up significant vertical space even when the user isn't
touching them. This makes both sections collapsible via a toggle arrow, using Flutter's
built-in `ExpansionTile`.

Out of scope: the Sync Folder card at the top (not requested); persisting the expanded/
collapsed state across app restarts or screen rebuilds (confirmed with the user — pure UI
state, resets every time); changing any of the existing save/test/sync logic or credential
handling.

## Behavior

- Both the Jira and Personio cards render as `Card(child: ExpansionTile(...))` instead of
  `Card(child: Padding(child: Column([Text(title), ...])))`.
- `ExpansionTile.title` takes over the section heading (`l10n.syncJiraSectionTitle` /
  `l10n.syncPersonioSectionTitle`), styled `titleMedium` to match the previous heading's
  visual weight — `ExpansionTile` doesn't apply that style itself.
- `ExpansionTile.children` holds everything that used to follow the heading (text fields,
  status message, buttons, Personio's date-range row) wrapped in a `Padding` for the same
  horizontal/bottom inset the old `Column` had, since `ExpansionTile` doesn't pad its
  children the way the removed wrapping `Padding` did.
- `initiallyExpanded: false` on both — both sections start collapsed every time the Sync
  tab is (re)built, regardless of whether credentials are already configured.
- No new state field needed: `ExpansionTile` manages its own expanded/collapsed state
  internally (it's a stateful widget), so `_SyncScreenState` doesn't need a new
  `bool`/`ValueNotifier` for this.

## Testing

No pre-existing automated test covers `SyncScreen` (`test/features/sync/` doesn't exist in
this repo), so no test changes are required or added — this matches the codebase's existing
coverage boundary for this screen. Verified via `flutter analyze` and a manual desktop
smoke check (open Sync tab, confirm both sections start collapsed, tap to expand/collapse,
confirm all existing buttons/fields still work once expanded).

## Out of Scope

Persisting expand/collapse state; changing the Sync Folder card; any change to credential
storage, connection testing, or sync logic.
