# Settings Reorganization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Settings' single flat stack of 7 cards with a category list (5 rows) that drills down into dedicated sub-pages, keeping the bottom `NavigationBar` visible throughout.

**Architecture:** `SettingsScreen` becomes a thin host for its own nested `Navigator` (so the Settings tab gets its own back stack without touching `NavShell`/`AppShell`). `SettingsHomeScreen` is the category list; five new sub-page widgets each wrap an existing, unmodified editor widget in a shared `SettingsSubPage` chrome (back button + optional title).

**Tech Stack:** Flutter (Riverpod 3.x, existing patterns only — no new codegen needed), Dart, `flutter_test`.

## Global Constraints

- User-facing strings must be localized via ARB files in `lib/l10n/`; all 6 locale files (`de`, `en`, `es`, `fr`, `it`, `nl`) must define the same keys (`test/l10n/arb_completeness_test.dart` enforces this).
- `flutter analyze` and `flutter test` must pass; format with `dart format` before each commit.
- Feature-first structure: all new files live under `lib/features/settings/` (except `SettingsScreen`'s consumer, `AppShell`, which needs no changes).
- None of the five embedded widgets' (`AppResetSection`, `ProjectsEditor`, `BreakRuleTiersEditor`, `QuickAddDurationsEditor`, `LanguageDropdown`) internals may change — only where they're mounted.
- Commit after every task using Conventional Commits format (`feat(settings): ...`, `test(settings): ...`), imperative mood, lowercase, no trailing period, under 72 chars.

---

## Task 1: Localization keys

**Files:**
- Modify: `lib/l10n/app_de.arb`, `lib/l10n/app_en.arb`, `lib/l10n/app_es.arb`, `lib/l10n/app_fr.arb`, `lib/l10n/app_it.arb`, `lib/l10n/app_nl.arb`

**Interfaces:**
- Produces: `l10n.settingsCategoryGeneral`, `l10n.settingsCategoryTimeTracking`. Consumed by Task 6 (`GeneralSettingsScreen`), Task 4 (`TimeTrackingSettingsScreen`), and Task 8 (`SettingsHomeScreen`).

- [ ] **Step 1: Add keys to `app_de.arb`**

Find `"settingsTitle": "Einstellungen",` and insert directly after it:

```json
  "settingsCategoryGeneral": "Allgemein",
  "settingsCategoryTimeTracking": "Zeiterfassung",
```

- [ ] **Step 2: Add keys to `app_en.arb`**

After `"settingsTitle": "Settings",`:

```json
  "settingsCategoryGeneral": "General",
  "settingsCategoryTimeTracking": "Time tracking",
```

- [ ] **Step 3: Add keys to `app_es.arb`**

After `"settingsTitle": "Ajustes",`:

```json
  "settingsCategoryGeneral": "General",
  "settingsCategoryTimeTracking": "Seguimiento de tiempo",
```

- [ ] **Step 4: Add keys to `app_fr.arb`**

After `"settingsTitle": "Paramètres",`:

```json
  "settingsCategoryGeneral": "Général",
  "settingsCategoryTimeTracking": "Suivi du temps",
```

- [ ] **Step 5: Add keys to `app_it.arb`**

After `"settingsTitle": "Impostazioni",`:

```json
  "settingsCategoryGeneral": "Generale",
  "settingsCategoryTimeTracking": "Rilevamento del tempo",
```

- [ ] **Step 6: Add keys to `app_nl.arb`**

After `"settingsTitle": "Instellingen",`:

```json
  "settingsCategoryGeneral": "Algemeen",
  "settingsCategoryTimeTracking": "Tijdregistratie",
```

- [ ] **Step 7: Regenerate localization delegates**

Run: `flutter gen-l10n`
Expected: completes without error.

- [ ] **Step 8: Verify ARB parity**

Run: `flutter test test/l10n/arb_completeness_test.dart`
Expected: PASS

- [ ] **Step 9: Commit**

```bash
git add lib/l10n/
git commit -m "feat(settings): add i18n keys for settings categories"
```

---

## Task 2: `SettingsSubPage` shared widget

**Files:**
- Create: `lib/features/settings/settings_sub_page.dart`

**Interfaces:**
- Produces: `class SettingsSubPage extends StatelessWidget { const SettingsSubPage({super.key, String? title, required Widget child}); }`. Consumed by Tasks 3–7.

No dedicated test (it's exercised by every sub-page's own test in Tasks 6–8; a standalone test would just re-assert its two branches in isolation, which those tests already cover through real usage).

- [ ] **Step 1: Create the widget**

Create `lib/features/settings/settings_sub_page.dart`:

```dart
import 'package:flutter/material.dart';

/// Shared chrome for a Settings sub-page: a back button (optionally next to
/// a page title) above scrollable [child] content. [title] is omitted when
/// [child]'s own first widget already renders an equivalent heading -- see
/// docs/superpowers/specs/2026-08-08-settings-reorganization-design.md
/// section 2 for which categories that applies to (passing both would show
/// the same text twice).
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

- [ ] **Step 2: Verify it compiles**

Run: `flutter analyze lib/features/settings/settings_sub_page.dart`
Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add lib/features/settings/settings_sub_page.dart
git commit -m "feat(settings): add SettingsSubPage shared chrome"
```

---

## Task 3: `ProjectsSettingsScreen`

**Files:**
- Create: `lib/features/settings/projects_settings_screen.dart`

**Interfaces:**
- Consumes: `SettingsSubPage` (Task 2), `ProjectsEditor` (existing, `lib/features/projects/projects_editor.dart`, unmodified).
- Produces: `class ProjectsSettingsScreen extends StatelessWidget`. Consumed by Task 8.

- [ ] **Step 1: Create the screen**

Create `lib/features/settings/projects_settings_screen.dart`:

```dart
import 'package:flutter/material.dart';

import '../projects/projects_editor.dart';
import 'settings_sub_page.dart';

/// No page title -- ProjectsEditor already renders l10n.settingsProjectsTitle
/// as its own heading (see settings_sub_page.dart's doc comment).
class ProjectsSettingsScreen extends StatelessWidget {
  const ProjectsSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const SettingsSubPage(
      child: Card(
        child: Padding(padding: EdgeInsets.all(16), child: ProjectsEditor()),
      ),
    );
  }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `flutter analyze lib/features/settings/projects_settings_screen.dart`
Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add lib/features/settings/projects_settings_screen.dart
git commit -m "feat(settings): add ProjectsSettingsScreen"
```

---

## Task 4: `TimeTrackingSettingsScreen`

**Files:**
- Create: `lib/features/settings/time_tracking_settings_screen.dart`

**Interfaces:**
- Consumes: `SettingsSubPage` (Task 2), `QuickAddDurationsEditor`, `BreakRuleTiersEditor` (existing, unmodified), `l10n.settingsCategoryTimeTracking` (Task 1).
- Produces: `class TimeTrackingSettingsScreen extends StatelessWidget`. Consumed by Task 8.

- [ ] **Step 1: Create the screen**

Create `lib/features/settings/time_tracking_settings_screen.dart`:

```dart
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import 'break_rule_tiers_editor.dart';
import 'quick_add_durations_editor.dart';
import 'settings_sub_page.dart';

class TimeTrackingSettingsScreen extends StatelessWidget {
  const TimeTrackingSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SettingsSubPage(
      title: l10n.settingsCategoryTimeTracking,
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: QuickAddDurationsEditor(),
            ),
          ),
          SizedBox(height: 16),
          Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: BreakRuleTiersEditor(),
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `flutter analyze lib/features/settings/time_tracking_settings_screen.dart`
Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add lib/features/settings/time_tracking_settings_screen.dart
git commit -m "feat(settings): add TimeTrackingSettingsScreen"
```

---

## Task 5: `ResetSettingsScreen`

**Files:**
- Create: `lib/features/settings/reset_settings_screen.dart`

**Interfaces:**
- Consumes: `SettingsSubPage` (Task 2), `AppResetSection` (existing, unmodified).
- Produces: `class ResetSettingsScreen extends StatelessWidget`. Consumed by Task 8.

- [ ] **Step 1: Create the screen**

Create `lib/features/settings/reset_settings_screen.dart`:

```dart
import 'package:flutter/material.dart';

import 'app_reset_section.dart';
import 'settings_sub_page.dart';

/// No page title -- AppResetSection already renders l10n.settingsResetTitle
/// as its own heading (see settings_sub_page.dart's doc comment).
class ResetSettingsScreen extends StatelessWidget {
  const ResetSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const SettingsSubPage(
      child: Card(
        child: Padding(padding: EdgeInsets.all(16), child: AppResetSection()),
      ),
    );
  }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `flutter analyze lib/features/settings/reset_settings_screen.dart`
Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add lib/features/settings/reset_settings_screen.dart
git commit -m "feat(settings): add ResetSettingsScreen"
```

---

## Task 6: `GeneralSettingsScreen`

**Files:**
- Create: `lib/features/settings/general_settings_screen.dart`
- Test: `test/features/settings/general_settings_screen_test.dart` (new)

**Interfaces:**
- Consumes: `SettingsSubPage` (Task 2), `l10n.settingsCategoryGeneral` (Task 1), `autostartServiceProvider` (`lib/core/di/autostart_service.dart`), `appSettingsProvider` (`lib/core/di/app_settings_provider.dart`), `syncedWritesProvider` (`lib/core/di/sync_providers.dart`), `LanguageDropdown` (existing, unmodified).
- Produces: `class GeneralSettingsScreen extends ConsumerStatefulWidget`. Consumed by Task 8. Owns the autostart state and date/time-format handlers moved verbatim from the old `SettingsScreen`.

- [ ] **Step 1: Write the failing test**

Create `test/features/settings/general_settings_screen_test.dart`:

```dart
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/core/di/app_settings_provider.dart';
import 'package:hickory/core/di/autostart_service.dart';
import 'package:hickory/core/di/locale_provider.dart';
import 'package:hickory/core/di/sync_providers.dart';
import 'package:hickory/core/format/date_format.dart';
import 'package:hickory/core/locale/locale_store.dart';
import 'package:hickory/data/drift/database.dart';
import 'package:hickory/data/sync/sync_log_writer.dart';
import 'package:hickory/data/sync/synced_writes.dart';
import 'package:hickory/features/settings/general_settings_screen.dart';
import 'package:hickory/l10n/app_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';

class _FakeAutostartService extends AutostartService {
  _FakeAutostartService({this.enabled = false});
  bool enabled;

  @override
  Future<bool> isEnabled() async => enabled;

  @override
  Future<void> setEnabled(bool value) async => enabled = value;
}

Future<void> pumpUntilTrue(
  WidgetTester tester,
  Future<bool> Function() condition, {
  int maxTries = 50,
}) async {
  for (var i = 0; i < maxTries; i++) {
    if (await condition()) return;
    await tester.pump(const Duration(milliseconds: 10));
  }
}

void main() {
  late AppDatabase db;
  late Directory syncRoot;
  late Directory localeDir;
  late _FakeAutostartService autostartService;

  setUpAll(() async {
    // GeneralSettingsScreen formats each date-format dropdown option via
    // formatDate(..., Localizations.localeOf(context).languageCode), which
    // is 'en' for this test's MaterialApp(locale: Locale('en')) -- intl
    // requires its locale data initialized before DateFormat('en', ...) works,
    // same requirement documented on formatDate itself and followed by
    // date_format_test.dart/csv_export_test.dart.
    await initializeDateFormatting('en');
  });

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    syncRoot = Directory.systemTemp.createTempSync('hickory_general_settings_test_sync_');
    localeDir = Directory.systemTemp.createTempSync('hickory_general_settings_test_locale_');
    autostartService = _FakeAutostartService();
  });

  tearDown(() async {
    await db.close();
    if (syncRoot.existsSync()) syncRoot.deleteSync(recursive: true);
    if (localeDir.existsSync()) localeDir.deleteSync(recursive: true);
  });

  Widget makeApp() => ProviderScope(
        overrides: [
          appSettingsProvider.overrideWith(
            (ref) => Stream.value(
              AppSettingsRow(
                id: 'default',
                dateFormat: 'iso',
                timeFormat: '24h',
                quickAddDurationsMinutes: '15,30,45,60',
                countPausedTimeAsBreak: false,
                updatedAt: DateTime.utc(2026, 1, 1),
              ),
            ),
          ),
          syncedWritesProvider.overrideWith(
            (ref) async => SyncedWrites(
              db: db,
              logWriter: SyncLogWriter(syncRoot: syncRoot, deviceId: 'device-1'),
            ),
          ),
          autostartServiceProvider.overrideWithValue(autostartService),
          localeStoreProvider.overrideWith(
            (ref) async => LocaleStore(supportDirectory: localeDir),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: const Scaffold(body: GeneralSettingsScreen()),
        ),
      );

  Future<String?> currentDateFormat() async {
    final row = await db.select(db.appSettings).getSingleOrNull();
    return row?.dateFormat;
  }

  testWidgets('shows the autostart switch reflecting the current state', (tester) async {
    autostartService.enabled = true;
    await tester.pumpWidget(makeApp());
    await tester.pumpAndSettle();

    final switchTile = tester.widget<SwitchListTile>(find.byType(SwitchListTile));
    expect(switchTile.value, isTrue);
  });

  testWidgets('toggling autostart persists via AutostartService', (tester) async {
    await tester.pumpWidget(makeApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();

    expect(autostartService.enabled, isTrue);
    final switchTile = tester.widget<SwitchListTile>(find.byType(SwitchListTile));
    expect(switchTile.value, isTrue);
  });

  testWidgets('selecting a date format persists it', (tester) async {
    await tester.pumpWidget(makeApp());
    await tester.pumpAndSettle();

    // The dropdown's option labels are formatted dates (e.g. "08/08/2026"),
    // not the enum name -- compute the exact string GeneralSettingsScreen
    // will render for DateFormatStyle.us so the tap target matches without
    // guessing at a hardcoded date. 'en' matches this test's locale, same
    // as what the widget passes via Localizations.localeOf(context).
    final usDateText = formatDate(DateTime.now(), DateFormatStyle.us, 'en');

    await tester.tap(find.byType(DropdownButtonFormField<DateFormatStyle>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(usDateText).last);
    await tester.pumpAndSettle();

    await pumpUntilTrue(tester, () async => await currentDateFormat() == 'us');
    expect(await currentDateFormat(), 'us');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/settings/general_settings_screen_test.dart`
Expected: FAIL — `general_settings_screen.dart` doesn't exist yet.

- [ ] **Step 3: Create the screen**

Create `lib/features/settings/general_settings_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/app_settings_provider.dart';
import '../../core/di/autostart_service.dart';
import '../../core/di/sync_providers.dart';
import '../../core/format/date_format.dart';
import '../../l10n/app_localizations.dart';
import 'language_dropdown.dart';
import 'settings_sub_page.dart';

class GeneralSettingsScreen extends ConsumerStatefulWidget {
  const GeneralSettingsScreen({super.key});

  @override
  ConsumerState<GeneralSettingsScreen> createState() => _GeneralSettingsScreenState();
}

class _GeneralSettingsScreenState extends ConsumerState<GeneralSettingsScreen> {
  bool _loading = true;
  bool _autostartEnabled = false;

  @override
  void initState() {
    super.initState();
    _loadAutostartState();
  }

  Future<void> _loadAutostartState() async {
    final enabled = await ref.read(autostartServiceProvider).isEnabled();
    if (!mounted) return;
    setState(() {
      _autostartEnabled = enabled;
      _loading = false;
    });
  }

  Future<void> _setAutostart(bool value) async {
    setState(() => _autostartEnabled = value);
    await ref.read(autostartServiceProvider).setEnabled(value);
  }

  Future<void> _setDateFormat(DateFormatStyle style) async {
    final writes = await ref.read(syncedWritesProvider.future);
    await writes.updateAppSettings(dateFormat: style.wireName);
  }

  Future<void> _setTimeFormat(TimeFormatStyle style) async {
    final writes = await ref.read(syncedWritesProvider.future);
    await writes.updateAppSettings(timeFormat: style.wireName);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final settings = ref.watch(appSettingsProvider).value;
    final dateStyle = settings.dateStyle;
    final timeStyle = settings.timeStyle;
    final now = DateTime.now();

    return SettingsSubPage(
      title: l10n.settingsCategoryGeneral,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            child: _loading
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: LinearProgressIndicator(),
                  )
                : SwitchListTile(
                    title: Text(l10n.settingsAutostart),
                    value: _autostartEnabled,
                    onChanged: _setAutostart,
                  ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<DateFormatStyle>(
                          initialValue: dateStyle,
                          isDense: true,
                          decoration: InputDecoration(labelText: l10n.settingsDateFormat),
                          items: DateFormatStyle.values
                              .map(
                                (style) => DropdownMenuItem(
                                  value: style,
                                  child: Text(
                                    formatDate(
                                      now,
                                      style,
                                      Localizations.localeOf(context).languageCode,
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (style) => style == null ? null : _setDateFormat(style),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<TimeFormatStyle>(
                          initialValue: timeStyle,
                          isDense: true,
                          decoration: InputDecoration(labelText: l10n.settingsTimeFormat),
                          items: TimeFormatStyle.values
                              .map(
                                (style) => DropdownMenuItem(
                                  value: style,
                                  child: Text(formatTime(now, style)),
                                ),
                              )
                              .toList(),
                          onChanged: (style) => style == null ? null : _setTimeFormat(style),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const LanguageDropdown(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/settings/general_settings_screen_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/features/settings/general_settings_screen.dart test/features/settings/general_settings_screen_test.dart
git commit -m "feat(settings): add GeneralSettingsScreen"
```

---

## Task 7: `UpdateSettingsScreen`

**Files:**
- Create: `lib/features/settings/update_settings_screen.dart`
- Test: `test/features/settings/update_settings_screen_test.dart` (new)

**Interfaces:**
- Consumes: `SettingsSubPage` (Task 2), `updateCheckerProvider`, `updateInstallerProvider`, `currentAppVersionProvider`, `availableUpdateProvider` (`lib/core/di/update_providers.dart`), `appDatabaseProvider` (`lib/core/di/database_provider.dart`), `syncedWritesProvider` (`lib/core/di/sync_providers.dart`), `UpdateInfo`/`UpdateChecker` (`lib/core/update/update_checker.dart`), `UpdateInstaller`/`UpdateInstallPermissionException` (`lib/core/update/update_installer.dart`).
- Produces: `class UpdateSettingsScreen extends ConsumerStatefulWidget`. Consumed by Task 8. Owns the update-check/install state and handlers moved verbatim from the old `SettingsScreen`. No `Platform.isMacOS || Platform.isWindows` guard inside this file — that guard now lives in `SettingsHomeScreen` (Task 8), controlling whether the category row (and therefore this screen) is reachable at all.

- [ ] **Step 1: Write the failing test**

Create `test/features/settings/update_settings_screen_test.dart`:

```dart
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/core/di/database_provider.dart';
import 'package:hickory/core/di/sync_providers.dart';
import 'package:hickory/core/di/update_providers.dart';
import 'package:hickory/core/update/github_release_client.dart';
import 'package:hickory/core/update/update_checker.dart';
import 'package:hickory/core/update/update_installer.dart';
import 'package:hickory/data/drift/database.dart';
import 'package:hickory/data/sync/sync_log_writer.dart';
import 'package:hickory/data/sync/synced_writes.dart';
import 'package:hickory/features/settings/update_settings_screen.dart';
import 'package:hickory/l10n/app_localizations.dart';

class _FakeUpdateChecker extends UpdateChecker {
  _FakeUpdateChecker(this._result)
      : super(
          releaseClient: GithubReleaseClient(owner: 'test', repo: 'test'),
          platformAssetName: 'test.zip',
        );

  final UpdateInfo? _result;

  @override
  Future<UpdateInfo?> checkForUpdate() async => _result;
}

class _FakeUpdateInstaller extends UpdateInstaller {
  _FakeUpdateInstaller(this.extractedDir);

  final Directory extractedDir;
  bool quitAndSwapCalled = false;

  @override
  Future<Directory> prepareUpdate(UpdateInfo update) async => extractedDir;

  @override
  Future<void> quitAndSwap(
    Directory extractedTopLevel, {
    required AppDatabase db,
    required SyncedWrites writes,
  }) async {
    quitAndSwapCalled = true;
  }
}

void main() {
  late AppDatabase db;
  late Directory syncRoot;
  late Directory extractedDir;
  late _FakeUpdateInstaller installer;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    syncRoot = Directory.systemTemp.createTempSync('hickory_update_settings_test_sync_');
    extractedDir = Directory.systemTemp.createTempSync('hickory_update_settings_test_extracted_');
    installer = _FakeUpdateInstaller(extractedDir);
  });

  tearDown(() async {
    await db.close();
    if (syncRoot.existsSync()) syncRoot.deleteSync(recursive: true);
    if (extractedDir.existsSync()) extractedDir.deleteSync(recursive: true);
  });

  Widget makeApp({UpdateInfo? checkResult}) => ProviderScope(
        overrides: [
          currentAppVersionProvider.overrideWith((ref) async => '1.1.0'),
          updateCheckerProvider.overrideWithValue(_FakeUpdateChecker(checkResult)),
          updateInstallerProvider.overrideWithValue(installer),
          appDatabaseProvider.overrideWithValue(db),
          syncedWritesProvider.overrideWith(
            (ref) async => SyncedWrites(
              db: db,
              logWriter: SyncLogWriter(syncRoot: syncRoot, deviceId: 'device-1'),
            ),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: const Scaffold(body: UpdateSettingsScreen()),
        ),
      );

  testWidgets('shows the current version', (tester) async {
    await tester.pumpWidget(makeApp());
    await tester.pumpAndSettle();

    expect(find.textContaining('1.1.0'), findsOneWidget);
  });

  testWidgets('checking for updates with none available shows the up-to-date message', (
    tester,
  ) async {
    await tester.pumpWidget(makeApp(checkResult: null));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Check for updates'));
    await tester.pumpAndSettle();

    expect(find.text('You have the latest version.'), findsOneWidget);
  });

  testWidgets('checking for updates with one available shows the install button', (
    tester,
  ) async {
    const update = UpdateInfo(
      version: '1.2.0',
      notes: 'Bug fixes',
      downloadUrl: 'https://example.com/a.zip',
      checksumUrl: 'https://example.com/a.sha256',
      size: 1024,
    );
    await tester.pumpWidget(makeApp(checkResult: update));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Check for updates'));
    await tester.pumpAndSettle();

    expect(find.textContaining('1.2.0'), findsWidgets);
    expect(find.text('Install now'), findsOneWidget);
  });

  testWidgets('installing calls prepareUpdate and quitAndSwap on the installer', (
    tester,
  ) async {
    const update = UpdateInfo(
      version: '1.2.0',
      notes: '',
      downloadUrl: 'https://example.com/a.zip',
      checksumUrl: 'https://example.com/a.sha256',
      size: 1024,
    );
    await tester.pumpWidget(makeApp(checkResult: update));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Check for updates'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Install now'));
    await tester.pumpAndSettle();

    expect(installer.quitAndSwapCalled, isTrue);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/settings/update_settings_screen_test.dart`
Expected: FAIL — `update_settings_screen.dart` doesn't exist yet.

- [ ] **Step 3: Create the screen**

Create `lib/features/settings/update_settings_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/database_provider.dart';
import '../../core/di/sync_providers.dart';
import '../../core/di/update_providers.dart';
import '../../core/update/update_checker.dart';
import '../../core/update/update_installer.dart';
import '../../l10n/app_localizations.dart';
import 'settings_sub_page.dart';

class UpdateSettingsScreen extends ConsumerStatefulWidget {
  const UpdateSettingsScreen({super.key});

  @override
  ConsumerState<UpdateSettingsScreen> createState() => _UpdateSettingsScreenState();
}

class _UpdateSettingsScreenState extends ConsumerState<UpdateSettingsScreen> {
  bool _updateBusy = false;
  String? _updateStatusMessage;

  Future<void> _checkForUpdates() async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _updateBusy = true;
      _updateStatusMessage = l10n.settingsUpdateChecking;
    });
    try {
      final checker = ref.read(updateCheckerProvider);
      final update = await checker.checkForUpdate();
      ref.read(availableUpdateProvider.notifier).state = update;
      if (!mounted) return;
      setState(() => _updateStatusMessage = update == null ? l10n.settingsUpdateUpToDate : null);
    } catch (_) {
      if (mounted) setState(() => _updateStatusMessage = l10n.settingsUpdateCheckError);
    } finally {
      if (mounted) setState(() => _updateBusy = false);
    }
  }

  Future<void> _installUpdate(UpdateInfo update) async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _updateBusy = true;
      _updateStatusMessage = l10n.settingsUpdateInstalling;
    });
    try {
      final installer = ref.read(updateInstallerProvider);
      final extracted = await installer.prepareUpdate(update);
      final db = ref.read(appDatabaseProvider);
      final writes = await ref.read(syncedWritesProvider.future);
      await installer.quitAndSwap(extracted, db: db, writes: writes);
    } on UpdateInstallPermissionException {
      if (mounted) {
        setState(() => _updateStatusMessage = l10n.settingsUpdateInstallErrorPermission);
      }
    } catch (_) {
      if (mounted) setState(() => _updateStatusMessage = l10n.settingsUpdateInstallError);
    } finally {
      if (mounted) setState(() => _updateBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final currentVersionAsync = ref.watch(currentAppVersionProvider);
    final availableUpdate = ref.watch(availableUpdateProvider);

    return SettingsSubPage(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.settingsUpdateTitle, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              currentVersionAsync.when(
                data: (version) => Text(
                  l10n.settingsUpdateCurrentVersion(version),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                loading: () => const SizedBox.shrink(),
                error: (_, _) => const SizedBox.shrink(),
              ),
              if (_updateStatusMessage != null) ...[
                const SizedBox(height: 8),
                Text(_updateStatusMessage!, style: Theme.of(context).textTheme.bodySmall),
              ],
              const SizedBox(height: 16),
              if (availableUpdate != null) ...[
                Text(l10n.settingsUpdateAvailable(availableUpdate.version)),
                if (availableUpdate.notes.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(availableUpdate.notes, style: Theme.of(context).textTheme.bodySmall),
                ],
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _updateBusy ? null : () => _installUpdate(availableUpdate),
                  child: Text(l10n.settingsUpdateInstallButton),
                ),
              ] else
                OutlinedButton(
                  onPressed: _updateBusy ? null : _checkForUpdates,
                  child: Text(l10n.settingsUpdateCheckButton),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/settings/update_settings_screen_test.dart`
Expected: PASS (4 tests)

- [ ] **Step 5: Commit**

```bash
git add lib/features/settings/update_settings_screen.dart test/features/settings/update_settings_screen_test.dart
git commit -m "feat(settings): add UpdateSettingsScreen"
```

---

## Task 8: `SettingsHomeScreen`

**Files:**
- Create: `lib/features/settings/settings_home_screen.dart`
- Test: `test/features/settings/settings_home_screen_test.dart` (new)

**Interfaces:**
- Consumes: `GeneralSettingsScreen` (Task 6), `TimeTrackingSettingsScreen` (Task 4), `ProjectsSettingsScreen` (Task 3), `UpdateSettingsScreen` (Task 7), `ResetSettingsScreen` (Task 5), `l10n.settingsCategoryGeneral`/`settingsCategoryTimeTracking`/`settingsProjectsTitle`/`settingsUpdateTitle`/`settingsResetTitle`.
- Produces: `class SettingsHomeScreen extends StatelessWidget`. Consumed by Task 9.

- [ ] **Step 1: Write the failing test**

Create `test/features/settings/settings_home_screen_test.dart`:

```dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/core/di/app_settings_provider.dart';
import 'package:hickory/core/di/autostart_service.dart';
import 'package:hickory/core/di/break_rule_tiers_provider.dart';
import 'package:hickory/core/di/locale_provider.dart';
import 'package:hickory/core/di/update_providers.dart';
import 'package:hickory/core/locale/locale_store.dart';
import 'package:hickory/data/drift/database.dart';
import 'package:hickory/features/projects/projects_providers.dart';
import 'package:hickory/features/settings/general_settings_screen.dart';
import 'package:hickory/features/settings/projects_settings_screen.dart';
import 'package:hickory/features/settings/reset_settings_screen.dart';
import 'package:hickory/features/settings/settings_home_screen.dart';
import 'package:hickory/features/settings/time_tracking_settings_screen.dart';
import 'package:hickory/features/settings/update_settings_screen.dart';
import 'package:hickory/features/shell/nav_shell.dart';
import 'package:hickory/l10n/app_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';

class _FakeAutostartService extends AutostartService {
  @override
  Future<bool> isEnabled() async => false;

  @override
  Future<void> setEnabled(bool value) async {}
}

void main() {
  late Directory localeDir;

  setUpAll(() async {
    // Navigating into General renders GeneralSettingsScreen's date-format
    // dropdown, which calls formatDate(..., 'en') while building its
    // (unopened) options list -- same intl initialization requirement as
    // general_settings_screen_test.dart.
    await initializeDateFormatting('en');
  });

  setUp(() => localeDir = Directory.systemTemp.createTempSync('settings_home_screen_test_'));
  tearDown(() => localeDir.deleteSync(recursive: true));

  Widget makeApp() => ProviderScope(
        overrides: [
          appSettingsProvider.overrideWith(
            (ref) => Stream.value(
              AppSettingsRow(
                id: 'default',
                dateFormat: 'iso',
                timeFormat: '24h',
                quickAddDurationsMinutes: '15,30,45,60',
                countPausedTimeAsBreak: false,
                updatedAt: DateTime.utc(2026, 1, 1),
              ),
            ),
          ),
          breakRuleTiersProvider.overrideWith((ref) => Stream.value(const [])),
          activeProjectsProvider.overrideWith((ref) => Stream.value(const [])),
          archivedProjectsProvider.overrideWith((ref) => Stream.value(const [])),
          autostartServiceProvider.overrideWithValue(_FakeAutostartService()),
          localeStoreProvider.overrideWith(
            (ref) async => LocaleStore(supportDirectory: localeDir),
          ),
          currentAppVersionProvider.overrideWith((ref) async => '1.1.0'),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: NavShell(
            destinations: const [
              NavigationDestination(icon: Icon(Icons.settings), label: 'Settings'),
              NavigationDestination(icon: Icon(Icons.circle), label: 'Other'),
            ],
            // Builds the same nested-Navigator shape SettingsScreen (Task 9)
            // wraps as a thin wrapper, inline -- so this test only depends on
            // SettingsHomeScreen and doesn't need SettingsScreen to exist yet.
            // Task 9's own settings_screen_test.dart separately verifies that
            // SettingsScreen actually produces this same shape.
            children: [
              Navigator(
                onGenerateRoute: (settings) =>
                    MaterialPageRoute(builder: (_) => const SettingsHomeScreen()),
              ),
              const Center(child: Text('Other tab')),
            ],
          ),
        ),
      );

  testWidgets('shows all category rows', (tester) async {
    await tester.pumpWidget(makeApp());
    await tester.pumpAndSettle();

    expect(find.text('General'), findsOneWidget);
    expect(find.text('Time tracking'), findsOneWidget);
    expect(find.text('Projects'), findsOneWidget);
    expect(find.text('Reset'), findsOneWidget);
    if (Platform.isMacOS || Platform.isWindows) {
      expect(find.text('Updates'), findsOneWidget);
    }
  });

  testWidgets(
    'tapping each category row navigates to that category\'s screen, back returns to the list',
    (tester) async {
      await tester.pumpWidget(makeApp());
      await tester.pumpAndSettle();

      Future<void> tapAndVerify(String rowText, Type screenType) async {
        await tester.tap(find.text(rowText));
        await tester.pumpAndSettle();
        expect(find.byType(screenType), findsOneWidget);
        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();
      }

      await tapAndVerify('General', GeneralSettingsScreen);
      await tapAndVerify('Time tracking', TimeTrackingSettingsScreen);
      await tapAndVerify('Projects', ProjectsSettingsScreen);
      if (Platform.isMacOS || Platform.isWindows) {
        await tapAndVerify('Updates', UpdateSettingsScreen);
      }
      await tapAndVerify('Reset', ResetSettingsScreen);
    },
  );

  testWidgets('the bottom nav bar stays visible while browsing a sub-page', (tester) async {
    await tester.pumpWidget(makeApp());
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget);

    await tester.tap(find.text('General'));
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(GeneralSettingsScreen), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/settings/settings_home_screen_test.dart`
Expected: FAIL — `settings_home_screen.dart` doesn't exist yet.

- [ ] **Step 3: Create the screen**

Create `lib/features/settings/settings_home_screen.dart`:

```dart
import 'dart:io';

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import 'general_settings_screen.dart';
import 'projects_settings_screen.dart';
import 'reset_settings_screen.dart';
import 'time_tracking_settings_screen.dart';
import 'update_settings_screen.dart';

/// The Settings tab's landing page: a category list. Each row pushes its
/// own sub-page onto this tab's local Navigator -- see settings_screen.dart
/// and docs/superpowers/specs/2026-08-08-settings-reorganization-design.md.
class SettingsHomeScreen extends StatelessWidget {
  const SettingsHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.settingsTitle, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 16),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.tune),
                  title: Text(l10n.settingsCategoryGeneral),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const GeneralSettingsScreen()),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.timer_outlined),
                  title: Text(l10n.settingsCategoryTimeTracking),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const TimeTrackingSettingsScreen()),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.folder_outlined),
                  title: Text(l10n.settingsProjectsTitle),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const ProjectsSettingsScreen()),
                  ),
                ),
                if (Platform.isMacOS || Platform.isWindows) ...[
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.system_update_outlined),
                    title: Text(l10n.settingsUpdateTitle),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const UpdateSettingsScreen()),
                    ),
                  ),
                ],
                const Divider(height: 1),
                ListTile(
                  leading: Icon(Icons.warning_amber_outlined, color: colorScheme.error),
                  title: Text(
                    l10n.settingsResetTitle,
                    style: TextStyle(color: colorScheme.error),
                  ),
                  trailing: Icon(Icons.chevron_right, color: colorScheme.error),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const ResetSettingsScreen()),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/settings/settings_home_screen_test.dart`
Expected: PASS (3 tests). This test builds its own inline `Navigator` host (see the comment in Step 1) rather than depending on `SettingsScreen`, so it passes independently of Task 9 — the two tasks have no ordering dependency in either direction.

- [ ] **Step 5: Commit**

```bash
git add lib/features/settings/settings_home_screen.dart test/features/settings/settings_home_screen_test.dart
git commit -m "feat(settings): add SettingsHomeScreen category list"
```

---

## Task 9: Rewrite `SettingsScreen`

**Files:**
- Modify: `lib/features/settings/settings_screen.dart` (full replacement)
- Test: `test/features/settings/settings_screen_test.dart` (new)

**Interfaces:**
- Consumes: `SettingsHomeScreen` (Task 8).
- Produces: `SettingsScreen` becomes a `StatelessWidget` hosting its own `Navigator`. `AppShell` (`lib/features/shell/app_shell.dart`) needs no changes — `SettingsScreen`'s public constructor and its role in `NavShell`'s `children` list are unchanged. Independent of Task 8 (no ordering dependency either way — see Task 8's note on why its test doesn't need this file).

- [ ] **Step 1: Write the failing test**

Create `test/features/settings/settings_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/features/settings/settings_screen.dart';
import 'package:hickory/l10n/app_localizations.dart';

void main() {
  testWidgets('shows the category list as its initial route', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: const SettingsScreen(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('General'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/settings/settings_screen_test.dart`
Expected: FAIL — `SettingsScreen` still has its old (pre-refactor) shape (reading `settingsAutostart` etc. directly) and doesn't render `SettingsHomeScreen`.

- [ ] **Step 3: Replace `settings_screen.dart`**

Replace the full contents of `lib/features/settings/settings_screen.dart` with:

```dart
import 'package:flutter/material.dart';

import 'settings_home_screen.dart';

/// The Settings tab's own Navigator, so pushing a category sub-page (see
/// SettingsHomeScreen) only replaces this tab's content -- NavShell's
/// shared bottomNavigationBar and the other three tabs are untouched. See
/// docs/superpowers/specs/2026-08-08-settings-reorganization-design.md
/// section 3.
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

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/settings/settings_screen_test.dart`
Expected: PASS

- [ ] **Step 5: Verify the whole feature compiles clean**

Run: `flutter analyze lib/features/settings/ lib/features/shell/`
Expected: no errors. (`AppShell`/`NavShell` should show zero diff needed — if `flutter analyze` flags anything in `app_shell.dart`, that means an assumption in this plan about `SettingsScreen`'s public API was wrong; stop and report rather than editing `AppShell` to compensate.)

- [ ] **Step 6: Commit**

```bash
git add lib/features/settings/settings_screen.dart test/features/settings/settings_screen_test.dart
git commit -m "feat(settings): host a nested Navigator in SettingsScreen"
```

---

## Task 10: Full verification pass

**Files:** none (verification only)

- [ ] **Step 1: Format**

Run: `dart format lib/features/settings/ test/features/settings/`
Expected: no changes, or only the files this feature touched — if `dart format .` (unscoped) reports unrelated files, that's the known pre-existing local formatter-version drift (see `docs/superpowers/plans/2026-08-07-report-filters.md` Task 11) — leave those alone, only commit formatting for files this feature's tasks actually created/modified.

- [ ] **Step 2: Analyze**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 3: Full test suite**

Run: `flutter test`
Expected: all tests pass, including every pre-existing suite (regression check) — in particular confirm `quick_add_durations_editor_test.dart`, `break_rule_tiers_editor_test.dart`, `language_dropdown_test.dart`, `app_reset_section_test.dart`, `project_form_dialog_test.dart`, and `projects_editor_test.dart` are unaffected (they mount their widgets directly, not via `SettingsScreen`).

- [ ] **Step 4: Manual smoke check (desktop)**

Run: `flutter run -d macos` (or `-d windows`) and in the running app: open Settings, confirm the 5 category rows appear (Zurücksetzen visually marked as a warning); tap into each one and confirm its content matches what used to be on the flat page; confirm the back arrow returns to the list; confirm the bottom nav bar stays visible the whole time; switch to another tab and back to Settings and confirm you're still on whichever sub-page you left (not reset to the list).

- [ ] **Step 5: Update the changelog**

In `CHANGELOG.md`, under `## [Unreleased]` / `### Added` (the section already exists from the prior report-filters entry — add a new bullet to it, don't create a duplicate section):

```markdown
- Reorganize Settings into a category list (General, Zeiterfassung, Projekte, Update, Zurücksetzen) with drill-down sub-pages, replacing the previous single flat stack of cards.
```

- [ ] **Step 6: Commit**

```bash
git add CHANGELOG.md
git commit -m "docs: note settings reorganization in the changelog"
```
