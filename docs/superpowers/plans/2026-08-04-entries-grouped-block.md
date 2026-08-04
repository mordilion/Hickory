# Entries Grouped Day Block Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Render each day's time entries as one rounded `Card` block with divider-separated rows, instead of each entry being its own independently pill-shaped `Card`.

**Architecture:** `EntriesList.build` currently flattens day groups into a single list of header/entry "rows" fed to `ListView.builder` one row at a time. It changes to one `ListView.builder` item per day group, each item building the existing `_DayHeader` followed by a new `_DayEntriesBlock` widget that renders that day's entries as a single `Card` containing a `Column` of `_EntryTile` rows separated by `Divider(height: 1)`. The per-entry `Dismissible`/`ListTile` markup is extracted into `_EntryTile`, unchanged in behavior, just re-parented.

**Tech Stack:** Flutter, Riverpod (`ConsumerWidget`), `flutter_test` widget tests.

## Global Constraints

- Corner radius: use the theme's default `CardThemeData` shape (`_cardRadius` = 24px in `lib/core/theme/app_theme.dart`) — no per-widget shape override.
- `clipBehavior: Clip.antiAlias` on the day-block `Card` so the swipe-to-delete background is clipped to the rounded corners.
- Entries inside a block are separated by `Divider(height: 1)`; no divider after the last entry in a group.
- Each entry stays individually wrapped in `Dismissible`, keyed by `ValueKey(entry.id)` — swipe-to-delete behavior is unchanged.
- The day header (`_DayHeader`) stays a freestanding element above the block — not absorbed into the `Card`.
- Scope is limited to `lib/features/entries/entries_list.dart` and its test file; no other screens, dialogs, or theme tokens change.
- Spec: `docs/superpowers/specs/2026-08-04-entries-grouped-block-design.md`.

---

### Task 1: Write failing tests for the grouped block layout

**Files:**
- Modify: `test/features/entries/entries_list_test.dart`

**Interfaces:**
- Consumes: existing `makeApp(List<TimeEntry> entries, {...})` helper and `_entry({required String id, required DateTime startAt, required DateTime endAt, int totalPausedSeconds})` helper already defined in this file (lines 13-35, 50-79) — reuse them as-is, no changes to their signatures.
- Produces: nothing consumed by later tasks; these are the acceptance tests Task 2 must satisfy.

- [ ] **Step 1: Add the two new test cases**

Insert these two `testWidgets` blocks into `test/features/entries/entries_list_test.dart`, right after the existing `'groups entries under Today/Yesterday headers with totals'` test (after line 101, before the empty-state test):

```dart
  testWidgets(
    "groups a single day's entries into one card with a divider between rows",
    (tester) async {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day, 9);
      await tester.pumpWidget(
        makeApp([
          _entry(id: '1', startAt: today, endAt: today.add(const Duration(hours: 1))),
          _entry(
            id: '2',
            startAt: today.add(const Duration(hours: 2)),
            endAt: today.add(const Duration(hours: 3)),
          ),
        ]),
      );
      await tester.pumpAndSettle();

      expect(find.byType(Card), findsOneWidget);
      expect(find.byType(Divider), findsOneWidget);
      final dismissibles = tester.widgetList<Dismissible>(find.byType(Dismissible));
      expect(
        dismissibles.map((d) => d.key),
        containsAll(const [ValueKey('1'), ValueKey('2')]),
      );
    },
  );

  testWidgets(
    'renders one card per day and omits the divider after the last entry in each block',
    (tester) async {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day, 9);
      final yesterday = today.subtract(const Duration(days: 1));
      await tester.pumpWidget(
        makeApp([
          _entry(id: '1', startAt: today, endAt: today.add(const Duration(hours: 1))),
          _entry(
            id: '2',
            startAt: today.add(const Duration(hours: 2)),
            endAt: today.add(const Duration(hours: 3)),
          ),
          _entry(id: '3', startAt: yesterday, endAt: yesterday.add(const Duration(minutes: 30))),
        ]),
      );
      await tester.pumpAndSettle();

      expect(find.byType(Card), findsNWidgets(2));
      expect(find.byType(Divider), findsOneWidget);
      expect(find.byType(Dismissible), findsNWidgets(3));
    },
  );
```

- [ ] **Step 2: Run the new tests and confirm they fail**

Run: `flutter test test/features/entries/entries_list_test.dart --plain-name "groups a single day's entries into one card"`
Expected: FAIL — `find.byType(Card)` finds 2 widgets (one per entry), not the expected 1, because each entry is still its own `Card` at this point.

Run: `flutter test test/features/entries/entries_list_test.dart --plain-name "renders one card per day"`
Expected: FAIL — `find.byType(Card)` finds 3 widgets, not the expected 2, and `find.byType(Divider)` finds 0, not the expected 1.

- [ ] **Step 3: Commit the failing tests**

```bash
git add test/features/entries/entries_list_test.dart
git commit -m "test(entries): add grouped day block expectations"
```

---

### Task 2: Implement the grouped day block and make the tests pass

**Files:**
- Modify: `lib/features/entries/entries_list.dart` (full rewrite of the widget body — see below)
- Test: `test/features/entries/entries_list_test.dart` (from Task 1, unchanged in this task)

**Interfaces:**
- Consumes: `EntryDayGroup` (`day`, `entries`, `totalDuration`, `breakDuration`) from `lib/features/entries/day_grouping.dart`; `requiredBreakForWorked(Duration, List<BreakRuleTier>)` from `lib/features/entries/break_rule_calculations.dart`; `showManualEntryDialog(BuildContext, WidgetRef, {TimeEntry? existing, ...})` from `lib/features/entries/manual_entry_dialog.dart`; `syncedWritesProvider` from `lib/core/di/sync_providers.dart`.
- Produces: `_DayEntriesBlock` (private `ConsumerWidget`, takes `entries`, `projectsById`, `jiraWorklogsById`, `timeStyle`, `l10n`) and `_EntryTile` (private `StatelessWidget`, takes `entry`, `project`, `jiraWorklog`, `timeStyle`, `l10n`, `onTap: VoidCallback`, `onDismissed: VoidCallback`) — both private to this file, nothing outside `entries_list.dart` depends on them.

- [ ] **Step 1: Replace the contents of `lib/features/entries/entries_list.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/app_settings_provider.dart';
import '../../core/di/break_rule_tiers_provider.dart';
import '../../core/di/jira_providers.dart';
import '../../core/di/sync_providers.dart';
import '../../core/format/date_format.dart';
import '../../core/format/duration_format.dart';
import '../../data/drift/database.dart';
import '../../data/drift/tables/jira_worklogs_table.dart';
import '../../data/drift/time_entry_extensions.dart';
import '../../l10n/app_localizations.dart';
import '../projects/projects_providers.dart';
import '../timer/timer_providers.dart';
import 'break_rule_calculations.dart';
import 'day_grouping.dart';
import 'manual_entry_dialog.dart';

class EntriesList extends ConsumerWidget {
  const EntriesList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final entriesAsync = ref.watch(allEntriesProvider);
    final projectsAsync = ref.watch(activeProjectsProvider);
    final jiraWorklogsAsync = ref.watch(jiraWorklogsByEntryIdProvider);
    final tiersAsync = ref.watch(breakRuleTiersProvider);
    final settings = ref.watch(appSettingsProvider).value;
    final dateStyle = settings.dateStyle;
    final timeStyle = settings.timeStyle;
    final countPausedTimeAsBreak = settings?.countPausedTimeAsBreak ?? false;

    return entriesAsync.when(
      data: (entries) {
        final finished = entries.where((e) => e.endAt != null).toList();
        if (finished.isEmpty) {
          return Center(child: Text(l10n.entriesEmpty));
        }
        final projectsById = {
          for (final p in projectsAsync.value ?? const <Project>[]) p.id: p,
        };
        final jiraWorklogsById = jiraWorklogsAsync.value ?? const <String, JiraWorklogRow>{};
        final tiers = tiersAsync.value ?? const <BreakRuleTier>[];
        final groups = groupEntriesByDay(
          finished,
          includePausedTimeInBreak: countPausedTimeAsBreak,
        );
        final localeName = Localizations.localeOf(context).languageCode;
        return ListView.builder(
          itemCount: groups.length,
          itemBuilder: (context, index) {
            final group = groups[index];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _DayHeader(
                  day: group.day,
                  total: group.totalDuration,
                  breakDuration: group.breakDuration,
                  requiredBreak: requiredBreakForWorked(group.totalDuration, tiers),
                  l10n: l10n,
                  dateStyle: dateStyle,
                  timeStyle: timeStyle,
                  localeName: localeName,
                ),
                _DayEntriesBlock(
                  entries: group.entries,
                  projectsById: projectsById,
                  jiraWorklogsById: jiraWorklogsById,
                  timeStyle: timeStyle,
                  l10n: l10n,
                ),
              ],
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => Center(child: Text(l10n.entriesError(error.toString()))),
    );
  }
}

Widget? _jiraStatusIcon(AppLocalizations l10n, String? jiraTicketKey, JiraWorklogRow? worklog) {
  if (jiraTicketKey == null) return null;
  final status = worklog?.status;
  return switch (status) {
    JiraWorklogStatus.synced => Tooltip(
        message: l10n.entriesJiraStatusSynced,
        child: const Icon(Icons.cloud_done_outlined, size: 18, color: Colors.green),
      ),
    JiraWorklogStatus.error => Tooltip(
        message: l10n.entriesJiraStatusError,
        child: const Icon(Icons.cloud_off_outlined, size: 18, color: Colors.red),
      ),
    _ => Tooltip(
        message: l10n.entriesJiraStatusPending,
        child: Icon(Icons.cloud_upload_outlined, size: 18, color: Colors.grey.shade600),
      ),
  };
}

/// One day's entries rendered as a single rounded card: rows separated by
/// 1px dividers (no divider after the last row), with
/// `clipBehavior: Clip.antiAlias` so each row -- including the
/// swipe-to-delete background -- is clipped to the card's rounded corners.
/// See docs/superpowers/specs/2026-08-04-entries-grouped-block-design.md.
class _DayEntriesBlock extends ConsumerWidget {
  const _DayEntriesBlock({
    required this.entries,
    required this.projectsById,
    required this.jiraWorklogsById,
    required this.timeStyle,
    required this.l10n,
  });

  final List<TimeEntry> entries;
  final Map<String, Project> projectsById;
  final Map<String, JiraWorklogRow> jiraWorklogsById;
  final TimeFormatStyle timeStyle;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.only(bottom: 8),
      child: Column(
        children: [
          for (var index = 0; index < entries.length; index++) ...[
            _EntryTile(
              entry: entries[index],
              project: entries[index].projectId == null
                  ? null
                  : projectsById[entries[index].projectId],
              jiraWorklog: jiraWorklogsById[entries[index].id],
              timeStyle: timeStyle,
              l10n: l10n,
              onTap: () => showManualEntryDialog(context, ref, existing: entries[index]),
              onDismissed: () {
                final entryId = entries[index].id;
                ref.read(syncedWritesProvider.future).then((w) => w.deleteEntry(entryId));
              },
            ),
            if (index != entries.length - 1) const Divider(height: 1),
          ],
        ],
      ),
    );
  }
}

/// A single time entry row inside a [_DayEntriesBlock]. Presentational only
/// -- [onTap] and [onDismissed] carry the Riverpod-dependent behavior so
/// this widget stays a plain [StatelessWidget].
class _EntryTile extends StatelessWidget {
  const _EntryTile({
    required this.entry,
    required this.project,
    required this.jiraWorklog,
    required this.timeStyle,
    required this.l10n,
    required this.onTap,
    required this.onDismissed,
  });

  final TimeEntry entry;
  final Project? project;
  final JiraWorklogRow? jiraWorklog;
  final TimeFormatStyle timeStyle;
  final AppLocalizations l10n;
  final VoidCallback onTap;
  final VoidCallback onDismissed;

  @override
  Widget build(BuildContext context) {
    final jiraStatusIcon = _jiraStatusIcon(l10n, entry.jiraTicketKey, jiraWorklog);
    final duration = entry.workedDuration;
    return Dismissible(
      key: ValueKey(entry.id),
      direction: DismissDirection.endToStart,
      background: Container(
        color: Theme.of(context).colorScheme.errorContainer,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: const Icon(Icons.delete_outline),
      ),
      onDismissed: (_) => onDismissed(),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: project != null
              ? Color(int.parse(project!.colorHex.replaceFirst('#', '0xFF')))
              : Colors.grey,
          radius: 8,
          child: const SizedBox.shrink(),
        ),
        title: Text(
          entry.description?.isNotEmpty == true
              ? entry.description!
              : (project?.name ?? l10n.entriesNoDescription),
        ),
        subtitle: Text(
          '${project?.name ?? l10n.commonNoProject} · '
          '${formatTime(entry.startAt, timeStyle)} – '
          '${formatTime(entry.endAt!, timeStyle)}',
        ),
        trailing: jiraStatusIcon == null
            ? Text(formatDuration(duration, timeStyle))
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  jiraStatusIcon,
                  const SizedBox(width: 6),
                  Text(formatDuration(duration, timeStyle)),
                ],
              ),
        onTap: onTap,
      ),
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({
    required this.day,
    required this.total,
    required this.breakDuration,
    required this.requiredBreak,
    required this.l10n,
    required this.dateStyle,
    required this.timeStyle,
    required this.localeName,
  });

  final DateTime day;
  final Duration total;
  final Duration breakDuration;
  final Duration? requiredBreak;
  final AppLocalizations l10n;
  final DateFormatStyle dateStyle;
  final TimeFormatStyle timeStyle;
  final String localeName;

  String _label() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (day == today) return l10n.entriesToday;
    final yesterday = today.subtract(const Duration(days: 1));
    if (day == yesterday) return l10n.entriesYesterday;
    return formatDate(day, dateStyle, localeName);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final requiredBreak = this.requiredBreak;
    final isInsufficient = requiredBreak != null && breakDuration < requiredBreak;
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 8),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 4,
        children: [
          Text(
            l10n.entriesDayHeader(_label(), formatDuration(total, timeStyle)),
            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          if (isInsufficient)
            Tooltip(
              message: l10n.entriesBreakInsufficientTooltip,
              child: Icon(Icons.warning_amber_rounded, size: 16, color: theme.colorScheme.error),
            ),
          Text(
            l10n.entriesBreakLabel(formatDuration(breakDuration, timeStyle)),
            style: theme.textTheme.bodySmall?.copyWith(
              color: isInsufficient ? theme.colorScheme.error : null,
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Run the full entries list test file and confirm everything passes**

Run: `flutter test test/features/entries/entries_list_test.dart`
Expected: PASS — all tests in the file, including the two added in Task 1.

- [ ] **Step 3: Static analysis**

Run: `flutter analyze lib/features/entries/entries_list.dart test/features/entries/entries_list_test.dart`
Expected: `No issues found!`

- [ ] **Step 4: Commit**

```bash
git add lib/features/entries/entries_list.dart
git commit -m "feat(entries): group a day's entries into one rounded block"
```

---

## Self-Review Notes

- **Spec coverage:** 24px radius via default `CardThemeData` (Task 2, `Card` with no shape override) ✓. `Clip.antiAlias` on the block `Card` ✓. `Divider(height: 1)` between rows, none after the last ✓ (tested in Task 1, implemented in Task 2). Per-entry `Dismissible` preserved, keyed by entry id ✓ (tested in Task 1). `_DayHeader` stays freestanding, outside the `Card` ✓ (see the `Column` in `EntriesList.build`). Scope limited to `entries_list.dart` + its test file ✓ — no other file is touched.
- **Placeholder scan:** none found — every step has literal code and literal commands with expected output.
- **Type consistency:** `_DayEntriesBlock` fields (`entries: List<TimeEntry>`, `projectsById: Map<String, Project>`, `jiraWorklogsById: Map<String, JiraWorklogRow>`, `timeStyle: TimeFormatStyle`, `l10n: AppLocalizations`) match what `EntriesList.build` passes. `_EntryTile`'s `onTap`/`onDismissed` are both `VoidCallback`, matching how `_DayEntriesBlock` constructs them (closures with no parameters).
