# Language Setting & i18n Infrastructure Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Internationalize Hickory's hardcoded-German UI via Flutter gen_l10n (ARB) and add a per-device language setting supporting de, en, fr, es, it, nl.

**Architecture:** Official `gen_l10n` codegen with `app_de.arb` as template. A `LocaleStore` (plain file in the app support dir, modeled on `BackgroundNoticeStore`) persists the choice per device; a keepAlive Riverpod `LocaleController` (`AsyncNotifier<Locale?>`, `null` = follow system) feeds `MaterialApp.locale`. Unsupported system locales resolve to English via a pure `resolveLocale()` helper. The tray menu (outside the widget tree) is re-labeled through `lookupAppLocalizations` on locale changes.

**Tech Stack:** Flutter 3.44 / Dart 3, `flutter_localizations` (SDK), `intl ^0.20.3` (already present), Riverpod 3 with `@riverpod` codegen (`dart run build_runner build --delete-conflicting-outputs`), `flutter_test`.

**Spec:** `docs/superpowers/specs/2026-07-10-language-setting-design.md`

## Global Constraints

- Supported languages, exactly these six: `de`, `en`, `fr`, `es`, `it`, `nl`.
- Default = system locale; fall back to **English** when unsupported; an explicit choice always wins.
- The preference is **per device**, stored locally, **never** synced (do NOT touch the `app_settings` Drift entity).
- German keeps today's exact wording — extraction must not reword any German text.
- Language names in the picker are endonyms: Deutsch, English, Français, Español, Italiano, Nederlands.
- ARB key style: lowerCamelCase, prefixed by surface (`settings…`, `timer…`, `entries…`, `projects…`, `reports…`, `sync…`, `tray…`, `common…` for shared).
- Every new key must be added to **all six** ARB files in the same commit (the completeness test enforces this).
- The brand name "Hickory" (window title, tray tooltip, app title) is not translated.
- All commits: imperative subject, end body with `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`.
- After each task: `flutter analyze` clean, `flutter test` green.

---

### Task 1: gen_l10n scaffolding + ARB completeness test

**Files:**
- Modify: `pubspec.yaml` (dependencies + `generate: true`)
- Create: `l10n.yaml`
- Create: `lib/l10n/app_de.arb`, `lib/l10n/app_en.arb`, `lib/l10n/app_fr.arb`, `lib/l10n/app_es.arb`, `lib/l10n/app_it.arb`, `lib/l10n/app_nl.arb`
- Test: `test/l10n/arb_completeness_test.dart`

**Interfaces:**
- Consumes: nothing (first task).
- Produces: generated `AppLocalizations` class (import `package:hickory/l10n/app_localizations.dart` or relative `../../l10n/app_localizations.dart`), `AppLocalizations.localizationsDelegates`, `AppLocalizations.supportedLocales`, `lookupAppLocalizations(Locale)`. Seed keys: `trayOpen`, `trayQuit`, `trayBackgroundNotice`, `settingsLanguage`, `settingsLanguageSystem(String language)`.

- [ ] **Step 1: Write the failing completeness test**

```dart
// test/l10n/arb_completeness_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Every language must define exactly the same message keys as the German
/// template. Metadata entries (@key, @@locale) are ignored.
void main() {
  const languages = ['de', 'en', 'fr', 'es', 'it', 'nl'];

  Set<String> keysOf(String lang) {
    final file = File('lib/l10n/app_$lang.arb');
    expect(file.existsSync(), isTrue, reason: 'missing ${file.path}');
    final map = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    return map.keys.where((k) => !k.startsWith('@')).toSet();
  }

  test('all ARB files define the same keys as the template', () {
    final template = keysOf('de');
    expect(template, isNotEmpty);
    for (final lang in languages.skip(1)) {
      final keys = keysOf(lang);
      expect(keys.difference(template), isEmpty, reason: 'extra keys in $lang');
      expect(template.difference(keys), isEmpty, reason: 'missing keys in $lang');
    }
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/l10n/arb_completeness_test.dart`
Expected: FAIL with `missing lib/l10n/app_de.arb`

- [ ] **Step 3: Add dependencies and l10n config**

In `pubspec.yaml`, under `dependencies:` (next to the existing `flutter:` sdk block) add:

```yaml
  flutter_localizations:
    sdk: flutter
```

and in the `flutter:` section (where `uses-material-design: true` lives) add:

```yaml
  generate: true
```

Create `l10n.yaml` in the repo root:

```yaml
arb-dir: lib/l10n
template-arb-file: app_de.arb
output-localization-file: app_localizations.dart
nullable-getter: false
untranslated-messages-file: build/untranslated_messages.json
```

- [ ] **Step 4: Create the six ARB files with the seed keys**

`lib/l10n/app_de.arb` (template — German wording is verbatim from today's code):

```json
{
  "@@locale": "de",
  "trayOpen": "Öffnen",
  "trayQuit": "Beenden",
  "trayBackgroundNotice": "Hickory läuft im Hintergrund weiter.",
  "settingsLanguage": "Sprache",
  "settingsLanguageSystem": "Systemstandard ({language})",
  "@settingsLanguageSystem": {
    "placeholders": {
      "language": { "type": "String" }
    }
  }
}
```

`lib/l10n/app_en.arb`:

```json
{
  "@@locale": "en",
  "trayOpen": "Open",
  "trayQuit": "Quit",
  "trayBackgroundNotice": "Hickory keeps running in the background.",
  "settingsLanguage": "Language",
  "settingsLanguageSystem": "System default ({language})"
}
```

`lib/l10n/app_fr.arb`:

```json
{
  "@@locale": "fr",
  "trayOpen": "Ouvrir",
  "trayQuit": "Quitter",
  "trayBackgroundNotice": "Hickory continue de fonctionner en arrière-plan.",
  "settingsLanguage": "Langue",
  "settingsLanguageSystem": "Paramètre système ({language})"
}
```

`lib/l10n/app_es.arb`:

```json
{
  "@@locale": "es",
  "trayOpen": "Abrir",
  "trayQuit": "Salir",
  "trayBackgroundNotice": "Hickory sigue ejecutándose en segundo plano.",
  "settingsLanguage": "Idioma",
  "settingsLanguageSystem": "Predeterminado del sistema ({language})"
}
```

`lib/l10n/app_it.arb`:

```json
{
  "@@locale": "it",
  "trayOpen": "Apri",
  "trayQuit": "Esci",
  "trayBackgroundNotice": "Hickory continua a funzionare in background.",
  "settingsLanguage": "Lingua",
  "settingsLanguageSystem": "Predefinita di sistema ({language})"
}
```

`lib/l10n/app_nl.arb`:

```json
{
  "@@locale": "nl",
  "trayOpen": "Openen",
  "trayQuit": "Afsluiten",
  "trayBackgroundNotice": "Hickory blijft op de achtergrond draaien.",
  "settingsLanguage": "Taal",
  "settingsLanguageSystem": "Systeemstandaard ({language})"
}
```

- [ ] **Step 5: Generate and verify**

Run: `flutter pub get && flutter gen-l10n`
Expected: exit 0; `lib/l10n/app_localizations.dart` (plus one `app_localizations_<lang>.dart` per language) exists.

Run: `flutter test test/l10n/arb_completeness_test.dart`
Expected: PASS

Run: `flutter analyze`
Expected: No issues found!

Note: if `flutter analyze` flags the generated files, add `lib/l10n/app_localizations*.dart` to the `analyzer: exclude:` list in `analysis_options.yaml` instead of touching the generated code.

- [ ] **Step 6: Commit**

```bash
git add pubspec.yaml pubspec.lock l10n.yaml lib/l10n/ test/l10n/arb_completeness_test.dart analysis_options.yaml
git commit -m "Add gen_l10n scaffolding with six-language ARB files"
```

---

### Task 2: Locale resolution helper

**Files:**
- Create: `lib/core/locale/locale_resolution.dart`
- Test: `test/core/locale/locale_resolution_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `const List<Locale> supportedLocales` — `[Locale('de'), Locale('en'), Locale('fr'), Locale('es'), Locale('it'), Locale('nl')]`
  - `const Map<String, String> languageDisplayNames` — endonyms keyed by language code
  - `Locale resolveLocale(Locale? deviceLocale)` — returns the matching supported locale (by languageCode) or `Locale('en')`

- [ ] **Step 1: Write the failing test**

```dart
// test/core/locale/locale_resolution_test.dart
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/core/locale/locale_resolution.dart';

void main() {
  test('supported device locale is used as-is (language code match)', () {
    expect(resolveLocale(const Locale('de', 'AT')), const Locale('de'));
    expect(resolveLocale(const Locale('fr')), const Locale('fr'));
  });

  test('unsupported device locale falls back to English', () {
    expect(resolveLocale(const Locale('ja')), const Locale('en'));
  });

  test('null device locale falls back to English', () {
    expect(resolveLocale(null), const Locale('en'));
  });

  test('display names cover exactly the supported locales', () {
    expect(
      languageDisplayNames.keys.toSet(),
      supportedLocales.map((l) => l.languageCode).toSet(),
    );
    expect(languageDisplayNames['de'], 'Deutsch');
    expect(languageDisplayNames['nl'], 'Nederlands');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/locale/locale_resolution_test.dart`
Expected: FAIL (file `locale_resolution.dart` does not exist)

- [ ] **Step 3: Write the implementation**

```dart
// lib/core/locale/locale_resolution.dart
import 'dart:ui';

/// The six languages Hickory ships translations for. Order = picker order.
const supportedLocales = [
  Locale('de'),
  Locale('en'),
  Locale('fr'),
  Locale('es'),
  Locale('it'),
  Locale('nl'),
];

/// Endonyms for the language picker — deliberately NOT localized, every
/// language is shown in its own name.
const languageDisplayNames = {
  'de': 'Deutsch',
  'en': 'English',
  'fr': 'Français',
  'es': 'Español',
  'it': 'Italiano',
  'nl': 'Nederlands',
};

/// Maps a device/system locale onto a supported one; English is the
/// spec-mandated fallback for unsupported (or unknown) system languages.
Locale resolveLocale(Locale? deviceLocale) {
  final code = deviceLocale?.languageCode;
  for (final locale in supportedLocales) {
    if (locale.languageCode == code) return locale;
  }
  return const Locale('en');
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/core/locale/locale_resolution_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/core/locale/locale_resolution.dart test/core/locale/locale_resolution_test.dart
git commit -m "Add locale resolution helper with English fallback"
```

---

### Task 3: LocaleStore (per-device persistence)

**Files:**
- Create: `lib/core/locale/locale_store.dart`
- Test: `test/core/locale/locale_store_test.dart`

**Interfaces:**
- Consumes: `languageDisplayNames` keys pattern from Task 2 (validation set).
- Produces: `class LocaleStore { LocaleStore({required Directory supportDirectory}); Future<String?> read(); Future<void> write(String languageCode); Future<void> clear(); }` — `read()` returns `null` for missing file, unreadable file, or a code outside the six supported ones.

- [ ] **Step 1: Write the failing test**

```dart
// test/core/locale/locale_store_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/core/locale/locale_store.dart';

void main() {
  late Directory tempDir;
  late LocaleStore store;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('locale_store_test');
    store = LocaleStore(supportDirectory: tempDir);
  });

  tearDown(() => tempDir.deleteSync(recursive: true));

  test('read returns null when no file exists', () async {
    expect(await store.read(), isNull);
  });

  test('write/read round-trip', () async {
    await store.write('fr');
    expect(await store.read(), 'fr');
  });

  test('clear removes the preference', () async {
    await store.write('it');
    await store.clear();
    expect(await store.read(), isNull);
  });

  test('clear on a missing file is a no-op', () async {
    await store.clear();
    expect(await store.read(), isNull);
  });

  test('unsupported code in the file yields null (e.g. after downgrade)', () async {
    File('${tempDir.path}/locale').writeAsStringSync('ja');
    expect(await store.read(), isNull);
  });

  test('corrupt content yields null', () async {
    File('${tempDir.path}/locale').writeAsStringSync('\x00\x01garbage');
    expect(await store.read(), isNull);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/locale/locale_store_test.dart`
Expected: FAIL (file `locale_store.dart` does not exist)

- [ ] **Step 3: Write the implementation**

```dart
// lib/core/locale/locale_store.dart
import 'dart:io';

import 'package:path/path.dart' as p;

import 'locale_resolution.dart';

/// Persists the per-device language choice as a plain file in the app
/// support directory (same pattern as [BackgroundNoticeStore]). A missing
/// file means "follow the system locale". Takes the directory as a
/// constructor parameter so tests can point it at a temp dir — the real
/// caller passes `await getApplicationSupportDirectory()`.
class LocaleStore {
  LocaleStore({required this.supportDirectory});

  final Directory supportDirectory;

  File get _file => File(p.join(supportDirectory.path, 'locale'));

  /// Returns the stored language code, or null when the preference is
  /// absent, unreadable, or no longer supported (spec: silently fall back
  /// to the system default rather than crash).
  Future<String?> read() async {
    final String content;
    try {
      content = (await _file.readAsString()).trim();
    } catch (_) {
      return null;
    }
    final supported = supportedLocales.any((l) => l.languageCode == content);
    return supported ? content : null;
  }

  Future<void> write(String languageCode) async {
    await _file.create(recursive: true);
    await _file.writeAsString(languageCode);
  }

  Future<void> clear() async {
    try {
      await _file.delete();
    } on PathNotFoundException {
      // Already absent — nothing to do.
    }
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/core/locale/`
Expected: PASS (all)

- [ ] **Step 5: Commit**

```bash
git add lib/core/locale/locale_store.dart test/core/locale/locale_store_test.dart
git commit -m "Add LocaleStore for the per-device language preference"
```

---

### Task 4: LocaleController Riverpod provider

**Files:**
- Create: `lib/core/di/locale_provider.dart` (+ generated `locale_provider.g.dart` via build_runner)
- Test: `test/core/di/locale_provider_test.dart`

**Interfaces:**
- Consumes: `LocaleStore` (Task 3).
- Produces:
  - `localeStoreProvider` — `Future<LocaleStore>`, resolves the real support directory; overridden in tests.
  - `localeControllerProvider` — `AsyncValue<Locale?>` state; `null` = follow system.
  - `LocaleController.setLocale(Locale? locale)` — updates state immediately (session-effective even if persisting fails), persists via write/clear, logs write failures.

- [ ] **Step 1: Write the failing test**

```dart
// test/core/di/locale_provider_test.dart
import 'dart:io';
import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/core/di/locale_provider.dart';
import 'package:hickory/core/locale/locale_store.dart';

void main() {
  late Directory tempDir;

  setUp(() => tempDir = Directory.systemTemp.createTempSync('locale_provider_test'));
  tearDown(() => tempDir.deleteSync(recursive: true));

  ProviderContainer makeContainer() => ProviderContainer(
        overrides: [
          localeStoreProvider.overrideWith(
            (ref) async => LocaleStore(supportDirectory: tempDir),
          ),
        ],
      );

  test('starts as null (follow system) when nothing is stored', () async {
    final container = makeContainer();
    addTearDown(container.dispose);
    expect(await container.read(localeControllerProvider.future), isNull);
  });

  test('setLocale updates state and persists across containers', () async {
    final first = makeContainer();
    await first.read(localeControllerProvider.future);
    await first.read(localeControllerProvider.notifier).setLocale(const Locale('nl'));
    expect(first.read(localeControllerProvider).value, const Locale('nl'));
    first.dispose();

    final second = makeContainer();
    addTearDown(second.dispose);
    expect(await second.read(localeControllerProvider.future), const Locale('nl'));
  });

  test('setLocale(null) reverts to following the system', () async {
    final container = makeContainer();
    addTearDown(container.dispose);
    await container.read(localeControllerProvider.future);
    final controller = container.read(localeControllerProvider.notifier);
    await controller.setLocale(const Locale('es'));
    await controller.setLocale(null);
    expect(container.read(localeControllerProvider).value, isNull);
    expect(await LocaleStore(supportDirectory: tempDir).read(), isNull);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/di/locale_provider_test.dart`
Expected: FAIL (file `locale_provider.dart` does not exist)

- [ ] **Step 3: Write the implementation**

Follow the existing style in `lib/core/di/` (e.g. `database_provider.dart`) — `@Riverpod(keepAlive: true)` codegen, `part` directive:

```dart
// lib/core/di/locale_provider.dart
import 'dart:ui';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:path_provider/path_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../locale/locale_store.dart';

part 'locale_provider.g.dart';

@Riverpod(keepAlive: true)
Future<LocaleStore> localeStore(Ref ref) async =>
    LocaleStore(supportDirectory: await getApplicationSupportDirectory());

/// The user's explicit language choice; `null` means "follow the system
/// locale". Per device by design — deliberately NOT part of the synced
/// app_settings entity (devices may run different OS languages).
@Riverpod(keepAlive: true)
class LocaleController extends _$LocaleController {
  @override
  Future<Locale?> build() async {
    final store = await ref.watch(localeStoreProvider.future);
    final code = await store.read();
    return code == null ? null : Locale(code);
  }

  Future<void> setLocale(Locale? locale) async {
    // State first: the choice applies to the running session even when
    // persisting fails (spec's error-handling rule).
    state = AsyncData(locale);
    try {
      final store = await ref.read(localeStoreProvider.future);
      if (locale == null) {
        await store.clear();
      } else {
        await store.write(locale.languageCode);
      }
    } catch (error) {
      debugPrint('Failed to persist locale preference: $error');
    }
  }
}
```

- [ ] **Step 4: Generate the provider code**

Run: `dart run build_runner build --delete-conflicting-outputs`
Expected: exit 0, `lib/core/di/locale_provider.g.dart` created.

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/core/di/locale_provider_test.dart`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add lib/core/di/locale_provider.dart lib/core/di/locale_provider.g.dart test/core/di/locale_provider_test.dart
git commit -m "Add LocaleController provider backed by LocaleStore"
```

---

### Task 5: Wire the locale into MaterialApp

**Files:**
- Modify: `lib/app.dart` (whole file, currently 21 lines)
- Modify: `lib/main.dart:14-15` (date-symbol init for all six languages)

**Interfaces:**
- Consumes: `localeControllerProvider` (Task 4), `resolveLocale` (Task 2), generated `AppLocalizations` (Task 1).
- Produces: a `MaterialApp` whose `locale` reacts to the controller; every later widget task may call `AppLocalizations.of(context)`.

- [ ] **Step 1: Rewrite `lib/app.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/di/locale_provider.dart';
import 'core/locale/locale_resolution.dart';
import 'core/theme/app_theme.dart';
import 'features/shell/app_shell.dart';
import 'l10n/app_localizations.dart';

class HickoryApp extends ConsumerWidget {
  const HickoryApp({super.key, required this.scaffoldMessengerKey});

  final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // null (loading or "follow system") lets localeResolutionCallback pick.
    final locale = ref.watch(localeControllerProvider).valueOrNull;

    return MaterialApp(
      title: 'Hickory',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      localeResolutionCallback: (deviceLocale, _) => resolveLocale(deviceLocale),
      scaffoldMessengerKey: scaffoldMessengerKey,
      home: const AppShell(),
    );
  }
}
```

Adjust the import path if gen_l10n emitted elsewhere (check where `app_localizations.dart` landed in Task 1).

- [ ] **Step 2: Initialize date symbols for all six languages in `lib/main.dart`**

Replace lines 14–15 (`await initializeDateFormatting('de_DE'); await initializeDateFormatting('en_US');`) with:

```dart
  for (final localeName in ['de_DE', 'en_US', 'de', 'en', 'fr', 'es', 'it', 'nl']) {
    await initializeDateFormatting(localeName);
  }
```

(`de_DE`/`en_US` stay because `formatDate`/`formatTime` still default to them until Task 8.)

- [ ] **Step 3: Verify**

Run: `flutter analyze`
Expected: No issues found!

Run: `flutter test`
Expected: all PASS (no widget test exists for HickoryApp; the reactive switch is covered by Task 6's widget test).

- [ ] **Step 4: Commit**

```bash
git add lib/app.dart lib/main.dart
git commit -m "Wire the locale preference into MaterialApp with English fallback"
```

---

### Task 6: Language dropdown in Settings

**Files:**
- Create: `lib/features/settings/language_dropdown.dart`
- Modify: `lib/features/settings/settings_screen.dart:96-110` (add dropdown below the time-format dropdown)
- Test: `test/features/settings/language_dropdown_test.dart`

**Interfaces:**
- Consumes: `localeControllerProvider` + `LocaleController.setLocale` (Task 4), `languageDisplayNames`, `supportedLocales`, `resolveLocale` (Task 2), `AppLocalizations` keys `settingsLanguage`, `settingsLanguageSystem` (Task 1).
- Produces: `class LanguageDropdown extends ConsumerWidget` (no parameters).

- [ ] **Step 1: Write the failing widget test**

```dart
// test/features/settings/language_dropdown_test.dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/core/di/locale_provider.dart';
import 'package:hickory/core/locale/locale_store.dart';
import 'package:hickory/features/settings/language_dropdown.dart';
import 'package:hickory/l10n/app_localizations.dart';

void main() {
  late Directory tempDir;

  setUp(() => tempDir = Directory.systemTemp.createTempSync('language_dropdown_test'));
  tearDown(() => tempDir.deleteSync(recursive: true));

  // Mirrors HickoryApp's locale wiring (locale follows the controller, so
  // the "switch re-renders immediately" behavior is actually under test);
  // starts at German because nothing is stored and resolveLocale of the
  // test binding's en_US would give English — so pin the platform locale.
  Widget makeApp() => ProviderScope(
        overrides: [
          localeStoreProvider.overrideWith(
            (ref) async => LocaleStore(supportDirectory: tempDir),
          ),
        ],
        child: Consumer(
          builder: (context, ref, _) {
            final locale = ref.watch(localeControllerProvider).valueOrNull;
            return MaterialApp(
              locale: locale ?? const Locale('de'),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: const Scaffold(body: LanguageDropdown()),
            );
          },
        ),
      );

  testWidgets('shows the system-default option with the resolved language', (tester) async {
    await tester.pumpWidget(makeApp());
    await tester.pumpAndSettle();
    expect(find.text('Sprache'), findsOneWidget);
    // Test binding's platform locale is en_US → resolved display name English.
    expect(find.textContaining('Systemstandard'), findsOneWidget);
  });

  testWidgets('selecting a language persists it via the controller', (tester) async {
    await tester.pumpWidget(makeApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Français').last);
    await tester.pumpAndSettle();

    // Persisted AND immediately re-rendered: the dropdown label is now French.
    expect(await LocaleStore(supportDirectory: tempDir).read(), 'fr');
    expect(find.text('Langue'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/settings/language_dropdown_test.dart`
Expected: FAIL (file `language_dropdown.dart` does not exist)

- [ ] **Step 3: Write the widget**

```dart
// lib/features/settings/language_dropdown.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/locale_provider.dart';
import '../../core/locale/locale_resolution.dart';
import '../../l10n/app_localizations.dart';

/// Sentinel dropdown value for "follow the system locale" (the stored
/// preference is absent in that case, so there is no language code to use).
const _systemValue = 'system';

class LanguageDropdown extends ConsumerWidget {
  const LanguageDropdown({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final explicit = ref.watch(localeControllerProvider).valueOrNull;
    final systemResolved =
        resolveLocale(WidgetsBinding.instance.platformDispatcher.locale);
    final systemName = languageDisplayNames[systemResolved.languageCode]!;

    return DropdownButtonFormField<String>(
      initialValue: explicit?.languageCode ?? _systemValue,
      decoration: InputDecoration(labelText: l10n.settingsLanguage),
      items: [
        DropdownMenuItem(
          value: _systemValue,
          child: Text(l10n.settingsLanguageSystem(systemName)),
        ),
        for (final locale in supportedLocales)
          DropdownMenuItem(
            value: locale.languageCode,
            child: Text(languageDisplayNames[locale.languageCode]!),
          ),
      ],
      onChanged: (value) {
        if (value == null) return;
        ref
            .read(localeControllerProvider.notifier)
            .setLocale(value == _systemValue ? null : Locale(value));
      },
    );
  }
}
```

- [ ] **Step 4: Integrate into the settings screen**

In `lib/features/settings/settings_screen.dart`, add the import:

```dart
import 'language_dropdown.dart';
```

and insert directly after the time-format `DropdownButtonFormField` (after line 109's closing `),`), inside the same `Column`:

```dart
                  const SizedBox(height: 12),
                  const LanguageDropdown(),
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `flutter test test/features/settings/language_dropdown_test.dart && flutter analyze`
Expected: PASS / No issues found!

- [ ] **Step 6: Commit**

```bash
git add lib/features/settings/language_dropdown.dart lib/features/settings/settings_screen.dart test/features/settings/language_dropdown_test.dart
git commit -m "Add language dropdown to the settings screen"
```

---

### Task 7: Localize the tray menu and background notice

**Files:**
- Modify: `lib/core/window/window_tray_controller.dart` (menu labels + snackbar text)
- Modify: `lib/main.dart` (label sync on locale changes)

**Interfaces:**
- Consumes: `lookupAppLocalizations` (Task 1), `localeControllerProvider` (Task 4), `resolveLocale` (Task 2).
- Produces: `WindowTrayController.updateContextMenu({required String openLabel, required String quitLabel})` and field `String Function()? backgroundNoticeMessage`.

- [ ] **Step 1: Make the tray controller label-injectable**

In `lib/core/window/window_tray_controller.dart`:

Add a field next to `onBeforeQuit`:

```dart
  /// Supplies the localized "runs in background" snackbar text. Set by
  /// `main()` (like [onBeforeQuit]) because localization lookup needs the
  /// active locale, which lives in the provider container this controller
  /// deliberately has no access to. Falls back to German when unset.
  String Function()? backgroundNoticeMessage;
```

Extract the menu construction into a public method and call it from `initialize()` (replacing the inline `setContextMenu` block at lines 64–72):

```dart
  /// (Re)builds the tray context menu; called at startup with German
  /// defaults and again by `main()` whenever the locale changes.
  Future<void> updateContextMenu({
    String openLabel = 'Öffnen',
    String quitLabel = 'Beenden',
  }) async {
    await trayManager.setContextMenu(
      Menu(
        items: [
          MenuItem(key: 'open', label: openLabel, onClick: (_) => _restore()),
          MenuItem.separator(),
          MenuItem(key: 'quit', label: quitLabel, onClick: (_) => _quit()),
        ],
      ),
    );
  }
```

In `initialize()`, the block becomes: `await updateContextMenu();`

In `_hideToTray()`, replace the hardcoded snackbar text:

```dart
      scaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(
          content: Text(
            backgroundNoticeMessage?.call() ?? 'Hickory läuft im Hintergrund weiter.',
          ),
        ),
      );
```

- [ ] **Step 2: Sync labels from `lib/main.dart`**

After `await windowTrayController.initialize();` (line 27) add:

```dart
  AppLocalizations trayL10n() {
    final explicit = container.read(localeControllerProvider).valueOrNull;
    final locale = explicit ??
        resolveLocale(WidgetsBinding.instance.platformDispatcher.locale);
    return lookupAppLocalizations(locale);
  }

  windowTrayController.backgroundNoticeMessage = () => trayL10n().trayBackgroundNotice;
  container.listen<AsyncValue<Locale?>>(
    localeControllerProvider,
    (_, __) {
      final l10n = trayL10n();
      unawaited(
        windowTrayController.updateContextMenu(
          openLabel: l10n.trayOpen,
          quitLabel: l10n.trayQuit,
        ),
      );
    },
    fireImmediately: true,
  );
```

Add the needed imports to `main.dart`:

```dart
import 'dart:async';

import 'core/di/locale_provider.dart';
import 'core/locale/locale_resolution.dart';
import 'l10n/app_localizations.dart';
```

(`Locale` and `AsyncValue` come from the already-present `flutter/material.dart` and `flutter_riverpod` imports.)

- [ ] **Step 3: Verify**

Run: `flutter analyze && flutter test`
Expected: clean / all PASS.

Manual check (native tray isn't reachable from widget tests): `flutter run -d windows`, switch the language to English in Settings, right-click the tray icon.
Expected: menu shows "Open" / "Quit"; minimizing shows the English notice.

- [ ] **Step 4: Commit**

```bash
git add lib/core/window/window_tray_controller.dart lib/main.dart
git commit -m "Localize the tray menu and background notice"
```

---

### Task 8: Locale-aware date names

**Files:**
- Modify: `lib/core/format/date_format.dart:51-60` (`formatDate` gains a locale parameter)
- Modify: every `formatDate(` call site in `lib/features/` (pass the ambient locale; find them with `grep -rn "formatDate(" lib/`)
- Test: `test/core/format/date_format_test.dart` (extend)

**Interfaces:**
- Consumes: existing `DateFormatStyle`, `formatDate` (unchanged call sites keep compiling via the default).
- Produces: `String formatDate(DateTime dt, [DateFormatStyle style = defaultDateFormatStyle, String localeName = 'de_DE'])` — only `DateFormatStyle.long` output actually varies by locale (the other patterns are all-numeric).

- [ ] **Step 1: Write the failing test** (append to the existing `test/core/format/date_format_test.dart`; its `setUpAll` must call `initializeDateFormatting` for `fr` and `en` in addition to what it already initializes)

```dart
  test('long style renders month names in the requested locale', () {
    final date = DateTime(2026, 12, 5, 12);
    expect(formatDate(date, DateFormatStyle.long, 'fr'), '5 déc. 2026');
    expect(formatDate(date, DateFormatStyle.long, 'en'), 'Dec 5, 2026');
    // Default stays German so existing call sites are unaffected.
    expect(formatDate(date, DateFormatStyle.long), '5. Dez. 2026');
  });
```

Note: exact expected strings depend on CLDR data — after the first failing run, verify the actual output is the correctly-localized form and pin the assertion to it (the failure message shows the actual). `'en'` needs a locale-appropriate pattern, see Step 3.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/format/date_format_test.dart`
Expected: FAIL (formatDate takes no third parameter)

- [ ] **Step 3: Implement**

Replace `formatDate` (lines 51–60) with:

```dart
/// Date patterns are all-numeric except [DateFormatStyle.long], whose month
/// abbreviation follows [localeName] (the active app language). The default
/// stays 'de_DE' so callers that don't care keep today's output. For the
/// long style, use a skeleton so ordering/punctuation localize too.
/// Requires `initializeDateFormatting(localeName)` to have run first (see
/// `main.dart`); tests must call it in `setUpAll`.
String formatDate(
  DateTime dt, [
  DateFormatStyle style = defaultDateFormatStyle,
  String localeName = 'de_DE',
]) {
  final local = dt.toLocal();
  if (style == DateFormatStyle.long) {
    return DateFormat.yMMMd(localeName).format(local);
  }
  final pattern = switch (style) {
    DateFormatStyle.de => 'dd.MM.yyyy',
    DateFormatStyle.iso => 'yyyy-MM-dd',
    DateFormatStyle.us => 'MM/dd/yyyy',
    DateFormatStyle.long => throw StateError('handled above'),
  };
  return DateFormat(pattern, localeName).format(local);
}
```

If the existing German long-style test asserted `'d. MMM y'` output, `DateFormat.yMMMd('de_DE')` produces the same rendering — if any existing assertion breaks, keep the old pattern for `de_DE` only if the output genuinely differs, and note it in the commit message.

- [ ] **Step 4: Pass the ambient locale at widget call sites**

For each `formatDate(...)` call inside a widget `build` method (found via the grep in **Files**), append the locale argument:

```dart
formatDate(date, dateStyle, Localizations.localeOf(context).languageCode)
```

CSV export and other non-widget call sites keep the default for now (CSV headers are handled in Task 12, where the reports screen passes its locale through).

- [ ] **Step 5: Run tests to verify they pass**

Run: `flutter test && flutter analyze`
Expected: all PASS / No issues found!

- [ ] **Step 6: Commit**

```bash
git add lib/core/format/date_format.dart lib/features/ test/core/format/date_format_test.dart
git commit -m "Render long-style dates in the active app language"
```

---

### Task 9: Extract strings — Settings & Sync screens

**Files:**
- Modify: `lib/features/settings/settings_screen.dart`, `lib/features/sync/sync_screen.dart`
- Modify: all six `lib/l10n/app_*.arb`

**Interfaces:**
- Consumes: `AppLocalizations.of(context)` (Task 5 wired the delegates).
- Produces: keys prefixed `settings…` / `sync…` present in all six ARBs.

**Extraction procedure (identical for Tasks 9–12):**

1. Inventory the file's user-visible literals:
   `grep -nE "'[^']{2,}'" lib/features/<file>.dart` — skip technical strings (asset paths, wire names, keys).
2. For each literal, add a lowerCamelCase key with the surface prefix to `app_de.arb` with the **verbatim** German text, then add the translation to the other five ARBs in the same edit. Dynamic fragments become placeholders (declare them in the template's `@key` metadata); count-dependent texts use ICU plurals, e.g. in `app_de.arb`:
   `"reportsEntryCount": "{count, plural, =1{1 Eintrag} other{{count} Einträge}}"` with `"@reportsEntryCount": {"placeholders": {"count": {"type": "int"}}}`.
3. In the widget, `final l10n = AppLocalizations.of(context);` at the top of `build` and replace each literal with `l10n.<key>` (or `l10n.<key>(arg)` for placeholders). Add the import `../../l10n/app_localizations.dart`.
4. Run `flutter gen-l10n` after editing ARBs so the getters exist.

Example from `settings_screen.dart` (line 62 and 71):

```dart
// Before
Text('Einstellungen', style: Theme.of(context).textTheme.headlineSmall),
...
title: const Text('Beim Systemstart öffnen'),

// After
Text(l10n.settingsTitle, style: Theme.of(context).textTheme.headlineSmall),
...
title: Text(l10n.settingsAutostart),
```

with `app_de.arb` gaining `"settingsTitle": "Einstellungen", "settingsAutostart": "Beim Systemstart öffnen", "settingsDateFormat": "Datumsformat", "settingsTimeFormat": "Zeitformat"` (lines 85 and 99 hold the two dropdown labels) and the five translations, e.g. `app_en.arb`: `"settingsTitle": "Settings", "settingsAutostart": "Launch at system startup", "settingsDateFormat": "Date format", "settingsTimeFormat": "Time format"`.

- [ ] **Step 1: Extract `settings_screen.dart` (procedure above)**
- [ ] **Step 2: Extract `sync_screen.dart` (procedure above, `sync…` prefix)**
- [ ] **Step 3: Verify no German literals remain**

Run: `grep -nE "'[^']{2,}'" lib/features/settings/settings_screen.dart lib/features/sync/sync_screen.dart`
Expected: no user-visible German text in the output (technical strings are fine).

- [ ] **Step 4: Run tests**

Run: `flutter gen-l10n && flutter test && flutter analyze`
Expected: all PASS (the completeness test proves all six ARBs stayed in sync) / No issues found!

- [ ] **Step 5: Commit**

```bash
git add lib/features/settings/ lib/features/sync/ lib/l10n/
git commit -m "Extract settings and sync screen strings into ARB files"
```

---

### Task 10: Extract strings — Shell & Timer

**Files:**
- Modify: `lib/features/shell/app_shell.dart`, `lib/features/shell/nav_shell.dart`, `lib/features/timer/timer_screen.dart`, `lib/features/timer/idle_prompt_dialog.dart`
- Modify: all six `lib/l10n/app_*.arb`

**Interfaces:**
- Consumes: extraction procedure from Task 9.
- Produces: keys prefixed `nav…` (shell navigation labels), `timer…` present in all six ARBs.

- [ ] **Step 1: Extract `app_shell.dart` + `nav_shell.dart` (`nav…` prefix — the four navigation destinations)**
- [ ] **Step 2: Extract `timer_screen.dart` (`timer…` prefix; ~10 literals incl. the "Was arbeitest…" prompt and "Kein Projekt")**

"Kein Projekt" appears on multiple screens — make it a shared key `commonNoProject` instead of one per surface.

- [ ] **Step 3: Extract `idle_prompt_dialog.dart` (`timerIdle…` prefix; the dialog's duration placeholder becomes an ARB placeholder, not string interpolation)**
- [ ] **Step 4: Verify + test**

Run: `grep -nE "'[^']{2,}'" lib/features/shell/*.dart lib/features/timer/timer_screen.dart lib/features/timer/idle_prompt_dialog.dart`
Expected: no user-visible German text.

Run: `flutter gen-l10n && flutter test && flutter analyze`
Expected: all PASS / No issues found!

- [ ] **Step 5: Commit**

```bash
git add lib/features/shell/ lib/features/timer/ lib/l10n/
git commit -m "Extract shell and timer strings into ARB files"
```

---

### Task 11: Extract strings — Entries & Projects

**Files:**
- Modify: `lib/features/entries/entries_list.dart`, `lib/features/entries/manual_entry_dialog.dart`, `lib/features/projects/new_project_dialog.dart`
- Modify: all six `lib/l10n/app_*.arb`

**Interfaces:**
- Consumes: extraction procedure from Task 9; `commonNoProject` from Task 10.
- Produces: keys prefixed `entries…` / `projects…` / `common…` (dialog buttons like "Abbrechen"/"Speichern" become `commonCancel`/`commonSave`, shared with Task 10's dialog if it defined them — reuse, don't duplicate).

- [ ] **Step 1: Extract `entries_list.dart` (`entries…` prefix; reuse `commonNoProject`)**
- [ ] **Step 2: Extract `manual_entry_dialog.dart` (~11 literals; form labels and validation messages all become keys — validation text is user-visible)**
- [ ] **Step 3: Extract `new_project_dialog.dart` (`projects…` prefix)**
- [ ] **Step 4: Verify + test**

Run: `grep -nE "'[^']{2,}'" lib/features/entries/*.dart lib/features/projects/new_project_dialog.dart`
Expected: no user-visible German text.

Run: `flutter gen-l10n && flutter test && flutter analyze`
Expected: all PASS / No issues found!

- [ ] **Step 5: Commit**

```bash
git add lib/features/entries/ lib/features/projects/ lib/l10n/
git commit -m "Extract entries and project dialog strings into ARB files"
```

---

### Task 12: Extract strings — Reports & CSV export

**Files:**
- Modify: `lib/features/reports/reports_screen.dart`, `lib/features/reports/csv_export.dart`
- Modify: all six `lib/l10n/app_*.arb`
- Test: `test/features/reports/csv_export_test.dart` (adapt to the new signature)

**Interfaces:**
- Consumes: extraction procedure from Task 9; `AppLocalizations` instance.
- Produces: keys prefixed `reports…` / `csv…`; `csv_export.dart`'s export function gains a `required AppLocalizations l10n` parameter for its column headers (it has no BuildContext — the reports screen passes `AppLocalizations.of(context)` through).

- [ ] **Step 1: Extract `reports_screen.dart` (`reports…` prefix, ~13 literals)**
- [ ] **Step 2: Localize the CSV headers**

In `csv_export.dart`, replace the hardcoded header strings with `csv…` keys read from a new `AppLocalizations l10n` parameter on the export function; update the call site in `reports_screen.dart` to pass `AppLocalizations.of(context)`. Update `test/features/reports/csv_export_test.dart` to construct localizations directly (no widget tree needed):

```dart
final l10n = lookupAppLocalizations(const Locale('de'));
```

and assert the German headers stay byte-identical to the pre-change CSV output (regression guard: existing users' CSV consumers must not break under the default language).

- [ ] **Step 3: Verify + test**

Run: `grep -nE "'[^']{2,}'" lib/features/reports/*.dart`
Expected: no user-visible German text.

Run: `flutter gen-l10n && flutter test && flutter analyze`
Expected: all PASS / No issues found!

- [ ] **Step 4: Commit**

```bash
git add lib/features/reports/ lib/l10n/ test/features/reports/csv_export_test.dart
git commit -m "Extract report strings and localize CSV export headers"
```

---

### Task 13: Final verification

**Files:**
- No new files; whole-tree verification.

**Interfaces:**
- Consumes: everything above.
- Produces: the shippable feature.

- [ ] **Step 1: Full-tree German-literal sweep**

Run: `grep -rnE "'[^']*[äöüßÄÖÜ][^']*'" lib --include=*.dart | grep -v "\.g\.dart" | grep -v "lib/l10n/"`
Expected: no matches outside comments (ARB files and generated l10n code are the only places German text lives now).

- [ ] **Step 2: Untranslated-messages check**

Run: `flutter gen-l10n && cat build/untranslated_messages.json`
Expected: empty JSON (`{}`) — no language is missing messages.

- [ ] **Step 3: Full suite**

Run: `flutter analyze && flutter test`
Expected: No issues found! / all PASS.

- [ ] **Step 4: Manual smoke test**

Run: `flutter run -d windows`
Check: (1) app starts in German (system locale de) with wording identical to before; (2) Settings → Sprache → English switches every visible screen immediately, incl. tray menu on right-click; (3) "Systemstandard (…)" option returns to German; (4) restart the app — the choice survives; (5) long date style in Settings preview shows localized month names.

- [ ] **Step 5: Commit any stragglers, then done**

```bash
git status --short   # should be clean; commit anything intentional that remains
```
