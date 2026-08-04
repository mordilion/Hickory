# Break Rule Tiers — Design

Date: 2026-08-04
Status: Approved for planning

## 1. Goal & Scope

Show each day's break time in `EntriesList`'s day header (e.g. "Today · 7:30 worked ·
0:45 break"), and flag it red plus a warning icon when it falls short of a
configurable, tiered minimum-break rule — e.g. "worked more than 6h → at least 30min
break required." The rule is user-defined; Settings offers one-click presets
(Germany/Austria/Switzerland) that fill an otherwise freely editable list of tiers.

This reuses the `BreakRuleTiers` table design from
`docs/superpowers/specs/2026-07-17-worktime-calendar-rules-design.md` (Section 2), but
trims that plan's much larger scope down to just this: no Calendar tab, no
`DayExceptions`, no `BalanceAdjustments`, no window resizing, no weekly/monthly
targets. Those remain a separate, later effort if ever picked up.

## 2. Data Model

### New `BreakRuleTiers` table (synced entity, same shape/conventions as `Projects`)

| Column | Type | Notes |
|---|---|---|
| `id` | text, PK | UUID, generated client-side. |
| `afterMinutes` | int | Worked-minutes threshold at which this tier applies. |
| `requiredBreakMinutes` | int | Break minutes required once `afterMinutes` is reached. |
| `deviceId` | text | Sync origin, same convention as `TimeEntries`/`Projects`. |
| `createdAt` / `updatedAt` | datetime | |

No separate "preset" concept in the data model — a preset is a hardcoded list of
`(afterMinutes, requiredBreakMinutes)` pairs in the UI layer (see Section 4). Picking
one deletes all current tiers and creates the preset's tiers in their place; the
result is then freely editable like any manually-entered tier. No confirmation dialog
before replacing — this only affects rule configuration, not tracked time entries.

Migration: `schemaVersion` 5 → 6, `onUpgrade` adds `m.createTable(breakRuleTiers)` for
`from < 6`, following the exact pattern of every prior migration step in
`lib/data/drift/database.dart`.

Sync wiring follows the established pattern exactly:
- `lib/data/drift/tables/break_rule_tiers_table.dart` (table)
- `lib/data/drift/daos/break_rule_tiers_dao.dart` — `watchAllTiers()`, `createTier(...)`,
  `deleteTier(String id)`
- `EntityTypes.breakRuleTier = 'break_rule_tier'`
- `SyncedWrites.createBreakRuleTier(...)`, `SyncedWrites.deleteBreakRuleTier(String id)`,
  and `SyncedWrites.replaceBreakRuleTiers(List<BreakRuleTierValues> tiers)` for the
  preset-apply action (deletes existing tiers, creates the new set, each step logged
  individually — matches how every other multi-step write in this codebase logs one
  event per DAO call rather than inventing a batch-event concept), where
  `BreakRuleTierValues` is a small immutable `(afterMinutes, requiredBreakMinutes)`
  value class (not a Dart record — the codebase has no existing record-type usage;
  a plain class matches house style, see `dart/architecture.md`'s immutable-class rule)
- `SyncIngestor._applyMaterializedEntity` gains an `EntityTypes.breakRuleTier` case,
  insert-or-update on non-delete / row delete on delete — identical shape to the
  existing `EntityTypes.project` case
- `test/data/drift/break_rule_tiers_dao_test.dart` and a new case in
  `test/data/sync_round_trip_test.dart`

## 3. Calculation

New pure-Dart module `lib/features/entries/break_rule_calculations.dart`, no DB/Flutter
dependency beyond the drift row types — mirrors `report_calculations.dart`.

- **Break time for a day**: sort that day's entries by `startAt` ascending, sum the
  gaps between each consecutive pair (`nextEntry.startAt - previousEntry.endAt`, only
  when positive — overlapping/back-to-back entries contribute zero). A day with 0 or 1
  entries has 0 break time. This mirrors the 2026-07-17 spec's "gaps between entries
  within the same calendar day" definition exactly — the overnight gap into the next
  day is never counted, and explicit Timer-pause time (`totalPausedSeconds`) is
  unrelated and not part of this calculation.
- **Required break for a day**: given the day's worked minutes (already computed as
  `EntryDayGroup.totalDuration`, see `day_grouping.dart`) and the active tier list,
  pick the tier with the highest `afterMinutes` that is `<=` worked minutes. Returns
  `null` (no requirement) if no tiers are configured, or worked minutes are below every
  tier's threshold.
- **Violation**: `actualBreak < requiredBreak` (only meaningful when a requirement
  exists). Applies to every day shown, including today while it's still in progress —
  a day that hasn't taken its break yet shows red until it does, by design.

## 4. UI

### Day header (`entries_list.dart`, `_DayHeader`)

Break time is **always shown** once there's at least one entry that day, regardless of
whether any rule is configured — it's useful information on its own. The existing
`entriesDayHeader(day, total)` line (e.g. "Today · 1:00") is left exactly as-is, and a
second, separate `Text` is appended after it via a new ARB key `entriesBreakLabel`,
`"Pause: {duration}"` (de) / `"Break: {duration}"` (en) — e.g. "Today · 1:00  Break:
0:45". Keeping it a separate `Text` (own `TextStyle`) rather than folding it into
`entriesDayHeader`'s placeholders is what lets it carry its own error color/icon
independently of the day-and-total text. When a rule is configured and violated, this
second `Text` renders in `Theme.of(context).colorScheme.error` with a small
`Icons.warning_amber_rounded` beside it (never color alone, per the repo's
accessibility rule — same reasoning as `_jiraStatusIcon`'s icon+color pairing).

### Settings — new "Pausenregeln" section

New widget `lib/features/settings/break_rule_tiers_editor.dart`, added to
`settings_screen.dart` as a new `Card`, styled like the existing
`QuickAddDurationsEditor` section:
- A row of preset buttons: Germany, Austria, Switzerland, and a "None" option that
  clears all tiers. Values (confirmed with the user):
  - Germany: 360min → 30min, 540min → 45min
  - Austria: 360min → 30min
  - Switzerland: 330min → 15min, 420min → 30min, 540min → 60min
- Below that, the current tier list (one row per tier: "after Xh Ym → at least Ah Bm
  break", delete icon), plus an "add tier" action opening a small dialog with two
  number fields (after-minutes, required-minutes) — mirrors
  `QuickAddDurationsEditor._add`'s single-field dialog, just with two fields.
- Presets are a hardcoded `const` list of `BreakRulePreset` (a small immutable class:
  `labelKey` + `List<BreakRuleTierValues> tiers`) in the new editor file — not a
  database concept (Section 2) — so adding a country later is a one-line addition, no
  schema/sync change needed.

### Riverpod

`breakRuleTiersProvider` — a plain `StreamProvider<List<BreakRuleTier>>` (not
`@riverpod` codegen, per the repo's existing rule about drift row types + riverpod_generator,
see `lib/features/reports/reports_providers.dart` for the precedent) wrapping
`BreakRuleTiersDao.watchAllTiers()`.

## 5. Testing

- `break_rule_calculations.dart`: unit tests for gap-summing (no entries, one entry,
  multiple entries with/without gaps, entries not already sorted), and tier selection
  (no tiers, worked time below smallest tier, exact threshold boundary, worked time
  above the highest tier).
- `break_rule_tiers_dao_test.dart` + sync round-trip case: same shape as the existing
  DAO/round-trip tests for other synced entities.
- `entries_list_test.dart`: new cases asserting the break segment renders neutral when
  no tiers are configured or the requirement is met, and red (findable via the warning
  icon, not color alone) when violated — including a case for today's in-progress day.
- `break_rule_tiers_editor_test.dart`: preset button fills the list with the expected
  values; add/remove tier updates the list; matches
  `quick_add_durations_editor_test.dart`'s existing structure.

## 6. Out of Scope (explicitly, from the trimmed 2026-07-17 plan)

Calendar tab, `DayExceptions`, `BalanceAdjustments`, window resizing, weekday work-time
targets, daily maximum, weekly/monthly targets, overtime/undertime balance. Any of
these would be a separate future spec.
