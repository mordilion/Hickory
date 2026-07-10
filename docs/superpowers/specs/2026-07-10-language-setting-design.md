# Language Setting & i18n Infrastructure — Design

**Date:** 2026-07-10
**Status:** Approved by user

## Goal

Hickory's UI is hardcoded German. Add full internationalization and a
user-facing language setting supporting six languages: German, English,
French, Spanish, Italian, Dutch.

## Decisions (from brainstorming)

- **Languages:** de, en, fr, es, it, nl
- **Default:** follow the system locale; fall back to English when the
  system language is unsupported. An explicit user choice always wins.
- **Scope of the preference:** per device, stored locally, **not** synced
  (unlike the date/time format, which lives in the synced `app_settings`
  entity — devices may legitimately run different OS languages).
- **Translations:** authored as part of this feature (German is the
  authoritative wording; EN/FR/ES/IT/NL translated from it).
- **Approach:** official Flutter `gen_l10n` with ARB files (option A;
  easy_localization and hand-rolled string classes were rejected —
  stringly-typed keys / boilerplate without plural support).

## Architecture

### i18n infrastructure

- Add `flutter_localizations` (SDK) to `pubspec.yaml`, enable
  `generate: true`.
- `l10n.yaml` points at `lib/l10n/`; **template is `app_de.arb`**
  (German is the authoring language). Sibling files: `app_en.arb`,
  `app_fr.arb`, `app_es.arb`, `app_it.arb`, `app_nl.arb`.
- `gen_l10n` generates the type-safe `AppLocalizations` class; every UI
  string becomes a getter (or method, when it has placeholders).

### Locale preference

- `lib/core/locale/locale_store.dart` — `LocaleStore`, modeled on
  `background_notice_store.dart`: a plain file named `locale` in the app
  support directory containing the language code (`de`, `en`, …).
  Missing file = follow system.
- `localeProvider` (Riverpod `Notifier<Locale?>`, `null` = system):
  reads the store at startup; setting a value writes the file and
  updates state reactively.

### Applying the locale

- `MaterialApp` gets `locale: ref.watch(localeProvider)`,
  `AppLocalizations.localizationsDelegates`, `supportedLocales`, and a
  `localeResolutionCallback` that returns English when the system locale
  is unsupported.
- Language switches apply immediately, no restart.

### Special cases

1. **Tray menu** ("Öffnen"/"Beenden") lives outside the widget tree.
   Use `lookupAppLocalizations(locale)` (no BuildContext needed); the
   `WindowTrayController` gets a hook that rebuilds the context menu
   with new labels whenever the locale changes.
2. **Date names** (month/weekday names from `intl`, e.g. in reports)
   follow the active locale: `DateFormat` receives the resolved locale;
   `main()` initializes locale data for all supported languages.

## Settings UI

A **"Sprache" / "Language" dropdown** in the Settings screen, directly
below the date/time format dropdowns and visually identical to them.
Options:

- **"Systemstandard (…)"** — shows the currently resolved language in
  parentheses, e.g. "Systemstandard (Deutsch)"
- The six languages, each in its own name: Deutsch, English, Français,
  Español, Italiano, Nederlands

Selection applies to the whole app immediately.

## String extraction

All hardcoded UI strings move to ARB files. Affected surfaces: every
screen (timer, entries, projects, reports, settings, sync, shell), the
dialogs (manual entry, new project, idle prompt), the tray menu, and the
CSV export column headers. Dynamic fragments become ARB placeholders
(e.g. `"deleteProject": "Projekt {name} löschen?"`); count-dependent
texts become proper plurals. Estimated volume: 100–150 strings.

German keeps today's exact wording. EN/FR/ES/IT/NL are authored as part
of the implementation.

## Error handling

- Unreadable/corrupt `locale` file → silently fall back to system
  default.
- File contains an unsupported code (e.g. after a downgrade) → system
  default.
- Write failure when saving the preference → the choice still applies
  for the running session; the error is logged.

## Testing

1. `LocaleStore` round-trip: write/read/delete, corrupt-file fallback.
2. Locale resolution: supported system locale is used; unsupported
   falls back to English; an explicit choice always wins.
3. Widget test: selecting a language in the dropdown re-renders visible
   texts immediately.
4. ARB completeness: CI-suitable check that no language is missing keys
   (gen_l10n `untranslated-messages-file` must stay empty).

## Out of scope

- Syncing the language preference across devices.
- RTL languages, per-language number formats beyond what `intl`
  provides automatically.
- Translating documentation or commit history.
