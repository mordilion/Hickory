# Settings Reorganization — Design

Date: 2026-08-08
Status: Approved for planning

## 1. Goal & Scope

`SettingsScreen` is currently a single scrolling stack of seven unrelated `Card`s
(Autostart, Date/Time format + Language, Quick-add durations, Break rule tiers, Projects,
App update, App reset), all visually equal weight with no grouping. This restructures it
into a **category list with drill-down sub-pages** (iOS-Settings-style): the Settings tab
opens on a list of 5 category rows; tapping one pushes a dedicated sub-page for that
category, with a back arrow to return.

The app's bottom `NavigationBar` (Timer/Reports/Sync/Settings) must stay visible while
browsing a settings sub-page — this requires a small `Navigator` local to the Settings
tab, since today the whole app has exactly one `Navigator` (the `MaterialApp` root) and no
tab has its own back stack.

Out of scope: changing any of the five embedded widgets' own internal behavior
(`AppResetSection`, `ProjectsEditor`, `BreakRuleTiersEditor`, `QuickAddDurationsEditor`,
`LanguageDropdown` are relocated, not modified); adaptive master-detail layout for wide
windows (plain push/pop only, confirmed with the user); reorganizing the Sync tab (it's
already a separate top-level tab, not part of Settings).

## 2. Categories

| # | Category | Content (existing widgets, unmodified) | Sub-page header |
|---|---|---|---|
| 1 | Allgemein | Autostart `SwitchListTile`, Date/Time format dropdowns, `LanguageDropdown` | Title "Allgemein" (new key `settingsCategoryGeneral`) |
| 2 | Zeiterfassung | `QuickAddDurationsEditor`, `BreakRuleTiersEditor` (each still in its own `Card`, as today) | Title "Zeiterfassung" (new key `settingsCategoryTimeTracking`) |
| 3 | Projekte | `ProjectsEditor` | Back arrow only — `ProjectsEditor` already renders `l10n.settingsProjectsTitle` as its own heading |
| 4 | Update | The update-check/install section (moved out of `SettingsScreen` verbatim) | Back arrow only — already renders `l10n.settingsUpdateTitle` |
| 5 | Zurücksetzen | `AppResetSection` | Back arrow only — already renders `l10n.settingsResetTitle` |

Categories 3–5 render a page header with **only** a back button: each embedded widget
already starts with its own `Text(l10n.xxxTitle, style: titleMedium)`, so a page-level
title would duplicate it. Categories 1–2 have no such internal title (their contents are
several self-labeled controls / multiple sub-widgets with no combined heading), so the
page header carries the category name instead.

The "Zurücksetzen" row in the category list uses a distinct icon (`Icons.warning_amber_outlined`)
and the theme's error color for both icon and text — consistent with the existing
error-colored reset button, and icon-plus-color (not color alone) per this project's
accessibility rule against color-only signaling.

## 3. Navigation Architecture

**`lib/features/settings/settings_screen.dart`** (rewritten): becomes the Settings tab's
own `Navigator` host, nested inside `NavShell`'s `IndexedStack` slot exactly where the old
`SettingsScreen` widget sat — so `AppShell`/`NavShell` need no changes at all.

```dart
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Navigator(
      onGenerateRoute: (settings) =>
          MaterialPageRoute(builder: (_) => const SettingsHomeScreen()),
    );
  }
}
```

Because this `Navigator` is *inside* `NavShell`'s `IndexedStack` (which is itself inside
`NavShell`'s single `Scaffold`, below the shared `bottomNavigationBar`), pushing a route
here only replaces the Settings tab's own content — the `NavigationBar` and the other three
tabs' state are untouched. This is the standard "each tab owns its own back stack" pattern;
no other file changes.

**`lib/features/settings/settings_home_screen.dart`** (new): the category list. Each row
is a `ListTile` (icon, title, trailing `Icons.chevron_right`); `onTap` calls
`Navigator.of(context).push(MaterialPageRoute(builder: (_) => const XxxSettingsScreen()))`.

**`lib/features/settings/settings_sub_page.dart`** (new): shared header/scaffold for all 5
sub-pages, so the back-button-plus-optional-title layout isn't duplicated five times
(Rule of Three).

```dart
/// Shared chrome for a Settings sub-page: a back button (optionally next to
/// a page title) above scrollable [child] content. [title] is omitted when
/// [child]'s own first widget already renders an equivalent heading (see
/// docs/superpowers/specs/2026-08-08-settings-reorganization-design.md
/// section 2) -- passing both would show the same text twice.
class SettingsSubPage extends StatelessWidget {
  const SettingsSubPage({super.key, this.title, required this.child});

  final String? title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const BackButton(),
              if (title != null) ...[
                const SizedBox(width: 8),
                Text(title!, style: Theme.of(context).textTheme.headlineSmall),
              ],
            ],
          ),
          const SizedBox(height: 16),
          Expanded(child: SingleChildScrollView(child: child)),
        ],
      ),
    );
  }
}
```

`BackButton` (not a hand-rolled `IconButton`) is used deliberately: it already resolves
the platform-correct back icon/tooltip via `MaterialLocalizations` and calls
`Navigator.maybePop` — matching Flutter's built-in behavior rather than reimplementing it.

## 4. The Five Category Screens

Each is a thin wrapper: `SettingsSubPage` plus the relocated content, in the same
`Card(child: Padding(padding: all(16), child: XxxEditor()))` shape each widget already
sits in today (visual style unchanged, only which screen hosts it).

- **`general_settings_screen.dart`** (new, `ConsumerStatefulWidget`): owns the Autostart
  state and handlers currently on `_SettingsScreenState`
  (`_loading`/`_autostartEnabled`/`_loadAutostartState`/`_setAutostart`), plus the
  date/time-format `Card` (unchanged dropdowns + handlers) and `LanguageDropdown`.
- **`time_tracking_settings_screen.dart`** (new, `StatelessWidget`): two `Card`s,
  `QuickAddDurationsEditor` and `BreakRuleTiersEditor` — no local state, both widgets
  already manage their own.
- **`projects_settings_screen.dart`** (new, `StatelessWidget`): one `Card` wrapping
  `ProjectsEditor`.
- **`update_settings_screen.dart`** (new, `ConsumerStatefulWidget`): owns the update state
  and handlers currently on `_SettingsScreenState`
  (`_updateBusy`/`_updateStatusMessage`/`_checkForUpdates`/`_installUpdate`), plus the
  `currentVersionAsync`/`availableUpdate` reads — content and logic moved verbatim. The
  existing `Platform.isMacOS || Platform.isWindows` guard moves to `settings_home_screen.dart`
  (the category row itself is omitted on other platforms, not just its content).
- **`reset_settings_screen.dart`** (new, `StatelessWidget`): one `Card` wrapping
  `AppResetSection`.

## 5. i18n

New ARB keys (all 6 locale files): `settingsCategoryGeneral` ("Allgemein" / "General" /
"General" / "Général" / "Generale" / "Algemeen"), `settingsCategoryTimeTracking`
("Zeiterfassung" / "Time tracking" / "Seguimiento de tiempo" / "Suivi du temps" /
"Rilevamento del tempo" / "Tijdregistratie").

Reused as-is: `settingsProjectsTitle`, `settingsUpdateTitle`, `settingsResetTitle` (category
list row labels), everything else already used by the relocated widgets unchanged.

## 6. Testing

- **`test/features/settings/settings_home_screen_test.dart`** (new): all 5 category rows
  render (the existing `Platform.isMacOS || Platform.isWindows` guard around the Update row
  is already untested at the widget level today — matches that precedent, not newly
  introduced); tapping a row navigates to that category's sub-page; tapping the back button
  returns to the list; the bottom `NavigationBar` stays present throughout.
- **Navigation state naturally survives tab switches**: `NavShell` keeps all four tabs
  mounted via `IndexedStack` (switching tabs only changes which is visible, none are
  rebuilt), so the Settings tab's nested `Navigator` — and therefore whichever sub-page the
  user drilled into — is preserved when switching to another tab and back. This falls out
  of the existing `IndexedStack` architecture for free; no code or test is needed to
  provide it, and no code path resets it.
- **`test/features/settings/settings_screen_test.dart`** (new, small): confirms
  `SettingsScreen` renders `SettingsHomeScreen` as its initial route (i.e. the `Navigator`
  wiring itself works).
- **`general_settings_screen_test.dart`** / **`update_settings_screen_test.dart`** (new):
  cover the state/handlers moved out of `SettingsScreen` (autostart toggle persistence,
  update check/install flow) — equivalent coverage to what implicitly existed before via
  manual testing only (no prior automated test covered these; this is a net-new safety net,
  not a preserved one).
- Existing tests (`quick_add_durations_editor_test.dart`, `break_rule_tiers_editor_test.dart`,
  `language_dropdown_test.dart`, `app_reset_section_test.dart`, `project_form_dialog_test.dart`,
  `projects_editor_test.dart`) mount their widget directly inside a plain `Scaffold`, not via
  `SettingsScreen` — confirmed unaffected by this restructuring, no changes needed.

## 7. Out of Scope

Modifying any embedded widget's internal behavior; adaptive/master-detail layout for wide
windows; deep-linking directly to a category (e.g. from a notification); persisting which
category was last open across tab switches or app restarts; reorganizing the Sync tab.
