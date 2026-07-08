# User-configurable date/time display format

## Context

Hickory currently renders every date and time in the UI through one hand-rolled helper, `lib/core/format/date_format.dart` (`formatDate` → hardcoded `YYYY-MM-DD`, `formatTime` → hardcoded 24h `HH:MM`). There is no way for a user to change this. The user asked to make the display format configurable, and — since Hickory already syncs time entries, projects, and activity samples across devices via its own JSONL event-log sync engine — explicitly wants this preference to sync across devices too, not be a per-device-only setting.

This is the first Hickory setting to be synced. Today's only setting (autostart-on-login) is deliberately per-device (OS-level registration can't sync) and lives outside the sync layer entirely. A synced date/time-format preference needs a new kind of synced entity: a *singleton* (one current value per synced identity) rather than a collection like time entries.

An i18n phase (English support, ARB files, language picker) is already planned as the next major initiative after this one. To avoid building a one-off synced-settings mechanism now and a second, different one for the language preference shortly after, this design introduces a small, deliberately extensible `AppSettings` singleton entity rather than a narrow one-field entity — new settings (like a future language preference) become new columns + a migration, not a new entity type.

## Design decisions

1. **Scope of options**: fixed lists, not free-form pattern input — four date styles (`de`, `iso`, `us`, `long`) × four time styles (`24h`, `24h_sec`, `12h`, `12h_sec`).
2. **Synced, not per-device**: the format preference travels with the user across devices via the existing sync-folder mechanism, using the same last-write-wins semantics already accepted for all other synced data.
3. **Extensible settings entity**: `AppSettings` is built as a small singleton row designed to grow (e.g. a future `language` column for the i18n phase), not re-modeled as a one-off two-column table.
4. **CSV export follows the display setting**: exported dates/times use the same format the user sees in the app, not a fixed machine-readable format. (The date-range *picker* calendar UI in Reports is unaffected — see Out of scope.)
5. **Default preserves current behavior**: no settings row yet (fresh install, or a sync partner that hasn't written one) → `iso` + `24h`, matching today's hardcoded output exactly. No user sees an unannounced format change.

## Data model

New Drift table, `AppSettings`, a singleton keyed by a fixed id rather than a UUID:

```
AppSettings
  id            TEXT PRIMARY KEY   -- fixed literal "default"
  dateFormat    TEXT NOT NULL      -- "de" | "iso" | "us" | "long"
  timeFormat    TEXT NOT NULL      -- "24h" | "24h_sec" | "12h" | "12h_sec"
  updatedAt     DATETIME NOT NULL
```

Date style → pattern mapping (via `intl`'s `DateFormat`, German locale for month names):

| Style | Pattern | Example |
|---|---|---|
| `de` | `dd.MM.yyyy` | 24.12.2026 |
| `iso` | `yyyy-MM-dd` | 2026-12-24 |
| `us` | `MM/dd/yyyy` | 12/24/2026 |
| `long` | `d. MMM y` | 24. Dez. 2026 |

Time style → pattern mapping:

| Style | Pattern | Example |
|---|---|---|
| `24h` | `HH:mm` | 14:30 |
| `24h_sec` | `HH:mm:ss` | 14:30:05 |
| `12h` | `h:mm a` | 2:30 PM |
| `12h_sec` | `h:mm:ss a` | 2:30:05 PM |

Reading with no row present (fresh install / not-yet-synced device) yields the default `AppSettings(id: "default", dateFormat: "iso", timeFormat: "24h")` without writing a row — a row is only written the first time a user actually changes a setting, keeping devices that never touch the setting free of sync noise.

## Sync integration

- `lib/data/sync/entity_types.dart` gets a new constant, `appSettings` (`entityType: "app_settings"`).
- `entityId` is the fixed literal `"default"`, not a generated UUID — `materialize()` in `packages/sync_engine` groups purely by `entityId` and is agnostic to cardinality, so the existing LWW-by-`(ts, deviceId, seq)` merge works unmodified for a singleton.
- `SyncedWrites` (`lib/data/sync/synced_writes.dart`) gets an `updateAppSettings({String? dateFormat, String? timeFormat})` method: writes through the DAO (upsert on the fixed id), re-reads the row, and calls `logWriter.appendEvent(entityType: appSettings, entityId: "default", op: update, payload: current.toJson())` — same shape as every other synced write in the app.
- `sync_ingestor.dart`'s `_applyMaterializedEntity` switch gets one new `case appSettings:` that upserts the single row from the materialized payload into the `AppSettings` table.
- **Backward compatibility**: an older Hickory build that doesn't know the `app_settings` entity type simply falls through the switch without a matching case — the same behavior already relied on for the existing `client`/`tag` stub entity types. No crash, no data loss; the setting is just invisible on that older build until it's updated.

## Formatting layer

- `intl` is added to `pubspec.yaml` (not currently a dependency).
- `lib/core/format/date_format.dart` is rebuilt: `formatDate(DateTime, DateFormatStyle)` and `formatTime(DateTime, TimeFormatStyle)` (small enums wrapping the style-key strings above) map to the `intl.DateFormat` patterns in the tables above and call `.format(dt)`. The mapping is pure and independently unit-testable.
- A new Riverpod provider, `appSettingsProvider`, wraps `db.appSettingsDao.watchSettings()` (a Drift `.watch()` stream, defaulting to `iso`/`24h` when no row exists) so every consumer reacts live — including to a setting change that arrives from another device via sync, with no app restart needed.
- Call sites switch from the old parameterless `formatDate(dt)`/`formatTime(dt)` to reading the current style from `appSettingsProvider` and passing it through: `entries_list.dart`, `manual_entry_dialog.dart`, `csv_export.dart`.

## Settings UI

- `lib/features/settings/settings_screen.dart` converts from a plain `ConsumerStatefulWidget` with local `setState` to reading `appSettingsProvider` reactively (the autostart toggle's local state is untouched — it stays a device-local, non-synced setting).
- Two new dropdowns are added: date format and time format, each showing a live preview of the current date/time rendered in that option (e.g. the dropdown item for `de` shows "24.12.2026" next to the label) so the user sees the effect before committing.
- Selecting an option calls `synced_writes.updateAppSettings(...)`; the UI updates immediately from the same reactive provider that drives the rest of the app, so there's no separate "save" step or optimistic-local-state juggling like the autostart toggle needs.

## CSV export

- `lib/features/reports/csv_export.dart` reads the current `dateFormat`/`timeFormat` (via `appSettingsProvider`, or receives the resolved styles as parameters if the export path isn't run inside the widget tree) and uses `formatDate`/`formatTime` for the date/start-time/end-time columns instead of the previous hardcoded formatting.
- The `showDateRangePicker` calendar dialog in `reports_screen.dart` is unaffected — it's a Flutter-builtin widget bound to `MaterialLocalizations`/app locale, not to this setting. Only the *textual* rendering of the picked range afterward goes through `formatDate`. See Out of scope.

## Out of scope

- No changes to the built-in `showDateRangePicker` calendar UI itself.
- No free-form/custom format pattern input — only the four fixed date styles and four fixed time styles.
- No language/locale picker — that's the separate, already-planned i18n phase; this design only makes `AppSettings` shaped so that phase can add a `language` column without a new entity type.
- No migration of historical CSV exports or past behavior — only future renders and future exports are affected.

## Verification

- `flutter analyze` clean; `flutter test` green.
- Unit tests for the `date_format.dart` style→pattern mapping: all 4 date styles × 4 time styles produce the expected string for a fixed reference `DateTime`.
- Unit tests for `AppSettingsDao`: default value when no row exists, upsert behavior on repeated writes.
- Manual: change the format in Settings, confirm the entries list, manual-entry dialog, and CSV export all reflect it immediately without an app restart.
- Manual sync test (two local sync-folder test instances, as used for earlier sync verification in this project): change the format on device A, sync, confirm device B picks up the new format.
