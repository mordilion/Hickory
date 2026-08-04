# Timer / Manual Toggle — Design

Date: 2026-08-04
Status: Approved for planning

## 1. Goal & Scope

The Timer tab currently stacks the timer card (start/running) directly above the
quick-add bar (manual entry), permanently — both take up vertical space even though
a user is only ever doing one of the two at a time. Replace the permanent stack with
a toggle: a segmented control switches the top section between "Timer" and "Manual"
mode, showing only one at a time. This reduces the space the top section needs and
keeps the user focused on one flow.

In scope: `lib/features/timer/timer_screen.dart` only. The entries list below stays
untouched and always visible in both modes — it's useful context regardless of which
input mode is active, and toggling it away was explicitly ruled out.

## 2. Behavior

- New local UI state in `_TimerScreenState`: `_TimerTabMode { timer, manual }`,
  defaulting to `.timer` on every launch (not persisted — matches the app's existing
  "opens ready to track" expectation).
- A segmented control ("Timer" | "Manual") renders above the top card, always visible.
- **Timer mode**: renders today's `_RunningCard`/`_StartCard` exactly as now (no
  behavior change to either).
- **Manual mode**: renders `QuickAddBar` instead.
- **Running-timer lock**: while `runningEntryProvider` has a non-null value (a timer
  is running or paused), the "Manual" segment is disabled (visibly greyed, not
  tappable) and the mode is forced to `.timer` — a user can never lose sight of an
  active timer by switching away from it. The moment the timer stops, "Manual"
  becomes selectable again; the mode stays wherever the user last left it (defaults
  to `.timer` if they never touched the control).

## 3. UI

`SegmentedButton<_TimerTabMode>` (Material 3), two segments:
- Timer: reuses the existing `l10n.navTimer` string ("Timer") — same word, no new key.
- Manual: new l10n key `timerModeManual` ("Manual" / "Manuell" / …), added to all six
  locale files, since no existing short key fits (`entriesManualEntryTitle` is
  "Manual entry", too long for a segment label).

Placed above the conditional card, inside the same `Padding`/`Column` that already
wraps the Timer tab's content; `QuickAddBar`'s own internal layout is unchanged.

## 4. Testing

- Widget test: default render shows the segmented control with Timer selected and
  `_StartCard` visible, `QuickAddBar` absent.
- Widget test: tapping "Manual" (with no running entry) swaps to `QuickAddBar`,
  `_StartCard` gone.
- Widget test: with a running entry, the "Manual" segment is disabled and tapping it
  has no effect — `_RunningCard` stays visible.
