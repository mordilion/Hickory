# Window Behavior, Tray, Autostart, and Internationalization

## Context

Three related requests came in during the Electric Violet redesign work: (1) the desktop window should look and feel like a phone — a fixed, slim window instead of a resizable desktop-shaped one — and minimizing or closing it should tuck it into the system tray rather than quitting, so background time-tracking keeps running; (2) an autostart-on-login option; (3) the app should support more than German, starting with English, auto-detected from the OS with a manual override.

The first two naturally need a place to live in the UI — a new dedicated Settings tab — which is also the natural home for a manual language switcher, so this spec covers both together. They're still separable in implementation: window/tray/autostart/Settings-tab-shell first, then i18n (which depends on the Settings tab existing for its language picker).

## Decisions

1. **Window**: fixed size (~400×800 logical px, a slim "phone" aspect ratio), not user-resizable, on both Windows and macOS — set via `window_manager` (already a dependency, unused until now) at startup.
2. **Tray**: both minimizing and closing (the window's X button) hide the window into the system tray instead of exiting the app — via `tray_manager` (already a dependency, unused until now). Left-click the tray icon restores the window; right-click opens a context menu with "Öffnen"/"Open" and "Beenden"/"Quit". Actually quitting only happens via that menu's Quit item (or OS-level force-quit). A one-time snackbar/notification on the first minimize-to-tray tells the user where the window went, so it doesn't feel like the app silently vanished.
3. **Autostart**: a toggle (default OFF) on the new Settings tab, implemented via the `launch_at_startup` package (Windows/macOS support) rather than hand-rolling registry/LaunchAgent code.
4. **New "Einstellungen" (Settings) tab**: a 4th bottom-nav destination (Timer/Reports/Sync/Settings), for now containing the autostart toggle and (once i18n lands) the language picker.
5. **i18n**: German (existing) + English, using Flutter's standard `flutter_localizations` + `intl` + ARB-file + `flutter gen-l10n` pipeline — not a hand-rolled solution — so adding a third language later is just another ARB file. Language follows the OS locale by default; the Settings tab gets a manual override (persisted locally) that takes precedence once set.

## Window & Tray

- `main.dart` initializes `window_manager` before `runApp`: set a fixed `Size(400, 800)`, disable resizing (`setResizable(false)`), and hand off close-button interception (`setPreventClose(true)`) so the app can intercept the close event instead of the OS closing the window.
- A small `WindowTrayController` (or similar) service wires:
  - `WindowListener.onWindowClose` → if `setPreventClose(true)` fired the close intent, hide the window (`windowManager.hide()`) instead of exiting; show the one-time explanatory snackbar/notification the first time this happens (persist a "seen" flag locally, same pattern as the sync-folder-path persistence already in the codebase).
  - `WindowListener.onWindowMinimize` → same hide-to-tray behavior.
  - `tray_manager`: set a tray icon at startup, a context menu with Open/Quit, left-click restores (`windowManager.show()` + `windowManager.focus()`), Quit calls `windowManager.destroy()` (or exits the process). The menu's label strings come from `AppLocalizations` at the point the tray is (re)initialized; since `tray_manager` doesn't auto-rebuild on locale change, the tray setup re-runs whenever the Settings tab's language override changes, so the menu text stays in sync without a restart.
- Desktop-only (Windows/macOS) — consistent with the rest of the app's current platform scope (mobile is M6, not started).

## Autostart

- `launch_at_startup` package, initialized once with the app's name/executable path.
- Settings tab exposes a `SwitchListTile` reading/writing the package's enabled state; default OFF; state persists via the package itself (which manages the OS-level mechanism directly, no extra local flag needed beyond querying the package's own `isEnabled()`).

## Settings Tab

- New `lib/features/settings/settings_screen.dart`, body-only content (matches the shell's existing pattern from the other three tabs).
- `AppShell`/`NavShell` gain a 4th destination (`Icons.settings_outlined`/`Icons.settings`, label "Einstellungen"/"Settings" — itself localized once i18n lands).
- Content: a simple list — autostart `SwitchListTile` now, language picker added once i18n lands (see below). No FAB on this tab (matches Reports/Sync today).

## Internationalization

- Add `flutter_localizations` (SDK) + `intl` dependencies; enable `generate: true` in `pubspec.yaml`'s `flutter:` section; add `l10n.yaml` pointing at `lib/l10n/app_en.arb` (template) and `lib/l10n/app_de.arb`.
- Every user-facing hardcoded German string across the app (timer screen, entries list, manual-entry dialog, new-project dialog, idle-prompt dialog, reports screen, sync screen, and the new settings screen) moves into the ARB files and is referenced via the generated `AppLocalizations.of(context)` accessor.
- `MaterialApp` gets `localizationsDelegates: AppLocalizations.localizationsDelegates`, `supportedLocales: AppLocalizations.supportedLocales`. Default `locale` is left unset (Flutter follows the OS locale automatically) unless the user has picked a manual override.
- Manual override: a `StateProvider<Locale?>`-backed (or small dedicated persistence, consistent with how `configuredSyncFolderPathProvider` persists a plain value to a local file) setting; `null` means "follow system." The Settings tab's language picker offers "System" / "Deutsch" / "English".
- English (`app_en.arb`) is the template/source-of-truth file (required by `flutter gen-l10n`); German (`app_de.arb`) provides the translations, since German is the app's existing, already-written baseline copy.

## Out of Scope

- No new languages beyond German/English for now (architecture supports adding more later — just another ARB file).
- No mobile-specific window/tray/autostart work (none of these three concepts apply to iOS/Android anyway).
- No change to the Electric Violet redesign's visual system — the new Settings screen and any new dialogs use the existing `AppTheme`/`HickoryColors`/pill-button conventions already established.
- Tray icon does not reflect live timer state (e.g., no dynamic elapsed-time in the tooltip) — static icon/tooltip only, not requested.

## Verification

- `flutter analyze` clean, existing test suite green throughout.
- Manual: build and launch on Windows, confirm the window opens at the fixed slim size and can't be resized by dragging edges; minimize and close both hide to tray with the one-time explanatory message on first occurrence; tray icon left-click restores, right-click shows Open/Quit, Quit actually exits; toggle autostart on/off and confirm (via OS: Windows Task Manager's Startup tab, or `shell:startup` folder / registry Run key) the entry appears/disappears; switch the Settings tab's language picker between System/Deutsch/English and confirm UI text changes live; change the OS locale and confirm the app follows it when the override is set to "System."
