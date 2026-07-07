# Electric Violet Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Hickory's default Material3 theme and single-screen-with-AppBar-icons layout with the "Electric Violet" visual system (hand-authored light/dark color tokens, Unbounded/Manrope typography, pill-shaped gradient components) and a bottom-navigation shell, per `docs/superpowers/specs/2026-07-07-electric-violet-redesign-design.md`.

**Architecture:** A `lib/core/theme/` package supplies the color tokens (as a `ThemeExtension`), text theme, and `ThemeData` for both brightnesses; existing screens stop owning their own `Scaffold`/`AppBar` and become body-only content hosted by a new `NavigationBar` shell. Two small reusable widgets (`GradientPillButton`, `GradientFab`) cover the gradient-filled primary actions that Flutter's built-in `ButtonStyle`/`FloatingActionButton` can't express natively.

**Tech Stack:** Flutter/Dart, `google_fonts` (new dependency), Riverpod (existing), `flutter_test` for pure-Dart and isolated-widget tests.

## Global Constraints

- Presentation-layer only: no changes to the data model, sync engine, drift schema, DAOs, or Riverpod business-logic providers.
- Color/type/shape/navigation values must match `docs/superpowers/specs/2026-07-07-electric-violet-redesign-design.md` exactly (hex codes, font names, radii) — that spec was validated interactively with the user; treat its tables as source of truth, not this plan's prose.
- Every task must leave `flutter analyze` clean (zero issues) and the existing non-widget test suite green.
- Avoid adding new `testWidgets` tests that pump a widget tree wired to real Riverpod providers with live timers/streams (`timerTickProvider`, `syncWatcherProvider`, `idleSecondsProvider`, `activeWindowChangesProvider`) — an earlier attempt at this hit a known `flutter_test` false positive ("A Timer is still pending...", https://github.com/flutter/flutter/issues/144472) and 5–10 minute run times on this machine. New widget tests in this plan are deliberately scoped to widgets with zero such dependencies (see Tasks 5 and 10).
- Windows is the only platform actually buildable/testable in this environment; verify there via `flutter build windows --debug` + a real launch, not just `flutter analyze`.

---

## File Structure

New files:
- `lib/core/theme/hickory_colors.dart` — the `HickoryColors` `ThemeExtension` (light/dark token sets not covered by `ColorScheme`)
- `lib/core/theme/app_text_theme.dart` — `buildAppTextTheme(Brightness)` (Unbounded display roles, Manrope everything else)
- `lib/core/theme/app_theme.dart` — `AppTheme.light` / `AppTheme.dark` (full `ThemeData`: seeded `ColorScheme` pinned to spec hexes, text theme, pill/rounded component themes)
- `lib/core/widgets/gradient_buttons.dart` — `GradientPillButton`, `GradientFab` (gradient-filled controls `ButtonStyle` can't express)
- `lib/features/shell/nav_shell.dart` — `NavShell`, a generic (no Riverpod) bottom-nav container: index state, `IndexedStack`, `NavigationBar`, optional per-tab FAB
- `lib/features/shell/app_shell.dart` — `AppShell`, wires `NavShell` to the real Timer/Reports/Sync screens and the manual-entry FAB
- `lib/features/sync/sync_screen.dart` — full-screen replacement for the current Sync dialog

Modified files:
- `pubspec.yaml` — add `google_fonts`
- `lib/app.dart` — use `AppTheme.light`/`AppTheme.dark`; `home` becomes `AppShell`
- `lib/features/timer/timer_screen.dart` — drops its own `Scaffold`/`AppBar`; running-timer card and Start/Stop button restyled
- `lib/features/entries/entries_list.dart` — pill-shaped rows, bottom padding for the shell's FAB
- `lib/features/reports/reports_screen.dart` — drops its own `Scaffold`/`AppBar`; choice-chip selected color tuned to the token set
- `test/widget_test.dart` — unaffected (stays as the pure `formatDuration` test)

Deleted files:
- `lib/features/sync/sync_settings_dialog.dart` — superseded by `sync_screen.dart`; its last reference (the old AppBar icon) is removed in Task 6, and the file itself is deleted in Task 8 alongside its replacement

---

### Task 1: HickoryColors design tokens

**Files:**
- Create: `lib/core/theme/hickory_colors.dart`
- Test: `test/core/theme/hickory_colors_test.dart`

**Interfaces:**
- Produces: `class HickoryColors extends ThemeExtension<HickoryColors>` with fields `surfaceGradient` (`List<Color>`, 2 stops), `primaryGradient` (`List<Color>`, 2 stops), `onPrimaryGradient` (`Color`), `textMuted` (`Color`), `chipBackground` (`Color`), `chipText` (`Color`), `timerNumeral` (`Color`), `navBackground` (`Color`), `navBorder` (`Color`), `navInactive` (`Color`), `navActiveLabel` (`Color`), `navActiveIcon` (`Color`); static const instances `HickoryColors.light` and `HickoryColors.dark`; static helper `HickoryColors.of(BuildContext)`.

- [ ] **Step 1: Write the failing test**

```dart
// test/core/theme/hickory_colors_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/core/theme/hickory_colors.dart';

void main() {
  test('dark tokens match the spec', () {
    expect(HickoryColors.dark.primaryGradient, const [Color(0xFFB678FF), Color(0xFFFF6FA9)]);
    expect(HickoryColors.dark.surfaceGradient, const [Color(0xFF241A30), Color(0xFF2E1B38)]);
    expect(HickoryColors.dark.onPrimaryGradient, const Color(0xFF160A22));
    expect(HickoryColors.dark.timerNumeral, const Color(0xFFC89BFF));
    expect(HickoryColors.dark.chipBackground, const Color(0xFF3A2A4A));
    expect(HickoryColors.dark.chipText, const Color(0xFFFF9ED6));
    expect(HickoryColors.dark.navBackground, const Color(0xFF1A1420));
    expect(HickoryColors.dark.navBorder, const Color(0xFF2A2033));
    expect(HickoryColors.dark.navInactive, const Color(0xFF6E6478));
    expect(HickoryColors.dark.navActiveLabel, const Color(0xFFE4D5FF));
    expect(HickoryColors.dark.navActiveIcon, const Color(0xFFC89BFF));
  });

  test('light tokens match the spec', () {
    expect(HickoryColors.light.primaryGradient, const [Color(0xFF8B4FE0), Color(0xFFE0568F)]);
    expect(HickoryColors.light.surfaceGradient, const [Color(0xFFF1E4FF), Color(0xFFFDE6F1)]);
    expect(HickoryColors.light.onPrimaryGradient, const Color(0xFFFFFFFF));
    expect(HickoryColors.light.timerNumeral, const Color(0xFF7C3AED));
    expect(HickoryColors.light.chipBackground, const Color(0xFFFFFFFF));
    expect(HickoryColors.light.chipText, const Color(0xFFC0287A));
    expect(HickoryColors.light.navBackground, const Color(0xFFFFFFFF));
    expect(HickoryColors.light.navBorder, const Color(0xFFEEE3FA));
    expect(HickoryColors.light.navInactive, const Color(0xFFA99BB8));
    expect(HickoryColors.light.navActiveLabel, const Color(0xFF4C1D95));
    expect(HickoryColors.light.navActiveIcon, const Color(0xFF7C3AED));
  });

  test('lerp interpolates toward the other extension, and passes through unrelated types', () {
    final atStart = HickoryColors.dark.lerp(HickoryColors.light, 0);
    final atEnd = HickoryColors.dark.lerp(HickoryColors.light, 1);
    expect(atStart.timerNumeral, HickoryColors.dark.timerNumeral);
    expect(atEnd.timerNumeral, HickoryColors.light.timerNumeral);

    final unchanged = HickoryColors.dark.lerp(null, 0.5);
    expect(unchanged, same(HickoryColors.dark));
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/core/theme/hickory_colors_test.dart`
Expected: FAIL — `package:hickory/core/theme/hickory_colors.dart` doesn't exist yet.

- [ ] **Step 3: Write the implementation**

```dart
// lib/core/theme/hickory_colors.dart
import 'package:flutter/material.dart';

/// Design tokens from docs/superpowers/specs/2026-07-07-electric-violet-redesign-design.md
/// that don't map onto Flutter's built-in ColorScheme roles: gradients,
/// chip colors, nav-bar colors, and the hero timer-numeral color.
/// `background`/`surface`/`onSurface`/text-primary are pinned directly on
/// ColorScheme instead (see AppTheme) rather than duplicated here.
@immutable
class HickoryColors extends ThemeExtension<HickoryColors> {
  const HickoryColors({
    required this.surfaceGradient,
    required this.primaryGradient,
    required this.onPrimaryGradient,
    required this.textMuted,
    required this.chipBackground,
    required this.chipText,
    required this.timerNumeral,
    required this.navBackground,
    required this.navBorder,
    required this.navInactive,
    required this.navActiveLabel,
    required this.navActiveIcon,
  });

  final List<Color> surfaceGradient;
  final List<Color> primaryGradient;
  final Color onPrimaryGradient;
  final Color textMuted;
  final Color chipBackground;
  final Color chipText;
  final Color timerNumeral;
  final Color navBackground;
  final Color navBorder;
  final Color navInactive;
  final Color navActiveLabel;
  final Color navActiveIcon;

  static const light = HickoryColors(
    surfaceGradient: [Color(0xFFF1E4FF), Color(0xFFFDE6F1)],
    primaryGradient: [Color(0xFF8B4FE0), Color(0xFFE0568F)],
    onPrimaryGradient: Color(0xFFFFFFFF),
    textMuted: Color(0x99241A30),
    chipBackground: Color(0xFFFFFFFF),
    chipText: Color(0xFFC0287A),
    timerNumeral: Color(0xFF7C3AED),
    navBackground: Color(0xFFFFFFFF),
    navBorder: Color(0xFFEEE3FA),
    navInactive: Color(0xFFA99BB8),
    navActiveLabel: Color(0xFF4C1D95),
    navActiveIcon: Color(0xFF7C3AED),
  );

  static const dark = HickoryColors(
    surfaceGradient: [Color(0xFF241A30), Color(0xFF2E1B38)],
    primaryGradient: [Color(0xFFB678FF), Color(0xFFFF6FA9)],
    onPrimaryGradient: Color(0xFF160A22),
    textMuted: Color(0x99F1ECF7),
    chipBackground: Color(0xFF3A2A4A),
    chipText: Color(0xFFFF9ED6),
    timerNumeral: Color(0xFFC89BFF),
    navBackground: Color(0xFF1A1420),
    navBorder: Color(0xFF2A2033),
    navInactive: Color(0xFF6E6478),
    navActiveLabel: Color(0xFFE4D5FF),
    navActiveIcon: Color(0xFFC89BFF),
  );

  @override
  HickoryColors copyWith({
    List<Color>? surfaceGradient,
    List<Color>? primaryGradient,
    Color? onPrimaryGradient,
    Color? textMuted,
    Color? chipBackground,
    Color? chipText,
    Color? timerNumeral,
    Color? navBackground,
    Color? navBorder,
    Color? navInactive,
    Color? navActiveLabel,
    Color? navActiveIcon,
  }) {
    return HickoryColors(
      surfaceGradient: surfaceGradient ?? this.surfaceGradient,
      primaryGradient: primaryGradient ?? this.primaryGradient,
      onPrimaryGradient: onPrimaryGradient ?? this.onPrimaryGradient,
      textMuted: textMuted ?? this.textMuted,
      chipBackground: chipBackground ?? this.chipBackground,
      chipText: chipText ?? this.chipText,
      timerNumeral: timerNumeral ?? this.timerNumeral,
      navBackground: navBackground ?? this.navBackground,
      navBorder: navBorder ?? this.navBorder,
      navInactive: navInactive ?? this.navInactive,
      navActiveLabel: navActiveLabel ?? this.navActiveLabel,
      navActiveIcon: navActiveIcon ?? this.navActiveIcon,
    );
  }

  @override
  HickoryColors lerp(ThemeExtension<HickoryColors>? other, double t) {
    if (other is! HickoryColors) return this;
    Color lerpColor(Color a, Color b) => Color.lerp(a, b, t)!;
    List<Color> lerpGradient(List<Color> a, List<Color> b) =>
        [lerpColor(a[0], b[0]), lerpColor(a[1], b[1])];
    return HickoryColors(
      surfaceGradient: lerpGradient(surfaceGradient, other.surfaceGradient),
      primaryGradient: lerpGradient(primaryGradient, other.primaryGradient),
      onPrimaryGradient: lerpColor(onPrimaryGradient, other.onPrimaryGradient),
      textMuted: lerpColor(textMuted, other.textMuted),
      chipBackground: lerpColor(chipBackground, other.chipBackground),
      chipText: lerpColor(chipText, other.chipText),
      timerNumeral: lerpColor(timerNumeral, other.timerNumeral),
      navBackground: lerpColor(navBackground, other.navBackground),
      navBorder: lerpColor(navBorder, other.navBorder),
      navInactive: lerpColor(navInactive, other.navInactive),
      navActiveLabel: lerpColor(navActiveLabel, other.navActiveLabel),
      navActiveIcon: lerpColor(navActiveIcon, other.navActiveIcon),
    );
  }

  /// Theme.of(context).extension<HickoryColors>() always succeeds in this
  /// app (registered on both themes by AppTheme), so this throws in debug
  /// mode rather than silently returning a wrong-looking fallback.
  static HickoryColors of(BuildContext context) {
    final colors = Theme.of(context).extension<HickoryColors>();
    assert(colors != null, 'HickoryColors not registered on the current Theme');
    return colors!;
  }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/core/theme/hickory_colors_test.dart`
Expected: PASS (3 tests) — this is a plain `test()`, not `testWidgets`, so it runs in well under a second.

- [ ] **Step 5: Analyze and commit**

Run: `flutter analyze`
Expected: `No issues found!`

```bash
git add lib/core/theme/hickory_colors.dart test/core/theme/hickory_colors_test.dart
git commit -m "Add HickoryColors design tokens for the Electric Violet redesign"
```

---

### Task 2: Text theme (Unbounded + Manrope)

**Files:**
- Modify: `pubspec.yaml`
- Create: `lib/core/theme/app_text_theme.dart`
- Test: `test/core/theme/app_text_theme_test.dart`

**Interfaces:**
- Consumes: nothing from Task 1.
- Produces: `TextTheme buildAppTextTheme(Brightness brightness)`.

- [ ] **Step 1: Add the google_fonts dependency**

Run: `flutter pub add google_fonts`
Expected: `pubspec.yaml` gains a `google_fonts: ^<version>` line under `dependencies`; command exits 0.

- [ ] **Step 2: Write the failing test**

```dart
// test/core/theme/app_text_theme_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/core/theme/app_text_theme.dart';

void main() {
  test('display and headline roles use Unbounded', () {
    final theme = buildAppTextTheme(Brightness.dark);
    expect(theme.displayLarge!.fontFamily, contains('Unbounded'));
    expect(theme.displayMedium!.fontFamily, contains('Unbounded'));
    expect(theme.headlineMedium!.fontFamily, contains('Unbounded'));
    expect(theme.titleLarge!.fontFamily, contains('Unbounded'));
  });

  test('body and label roles use Manrope', () {
    final theme = buildAppTextTheme(Brightness.dark);
    expect(theme.bodyLarge!.fontFamily, contains('Manrope'));
    expect(theme.bodyMedium!.fontFamily, contains('Manrope'));
    expect(theme.labelSmall!.fontFamily, contains('Manrope'));
    expect(theme.titleMedium!.fontFamily, contains('Manrope'));
  });

  test('builds for both brightnesses without throwing', () {
    expect(() => buildAppTextTheme(Brightness.light), returnsNormally);
    expect(() => buildAppTextTheme(Brightness.dark), returnsNormally);
  });
}
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `flutter test test/core/theme/app_text_theme_test.dart`
Expected: FAIL — `package:hickory/core/theme/app_text_theme.dart` doesn't exist yet.

- [ ] **Step 4: Write the implementation**

```dart
// lib/core/theme/app_text_theme.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Display roles (large, high-impact text: app title, the timer's elapsed-
/// time numerals, screen headlines) use Unbounded; everything else uses
/// Manrope. Unbounded is deliberately not used for label/body roles — it
/// loses legibility at small sizes.
/// See docs/superpowers/specs/2026-07-07-electric-violet-redesign-design.md.
TextTheme buildAppTextTheme(Brightness brightness) {
  final base = ThemeData(brightness: brightness, useMaterial3: true).textTheme;

  TextStyle display(TextStyle? style) =>
      GoogleFonts.unbounded(textStyle: style, fontWeight: FontWeight.w700);
  TextStyle body(TextStyle? style) => GoogleFonts.manrope(textStyle: style);

  return base.copyWith(
    displayLarge: display(base.displayLarge),
    displayMedium: display(base.displayMedium),
    displaySmall: display(base.displaySmall),
    headlineLarge: display(base.headlineLarge),
    headlineMedium: display(base.headlineMedium),
    headlineSmall: display(base.headlineSmall),
    titleLarge: display(base.titleLarge),
    titleMedium: body(base.titleMedium),
    titleSmall: body(base.titleSmall),
    bodyLarge: body(base.bodyLarge),
    bodyMedium: body(base.bodyMedium),
    bodySmall: body(base.bodySmall),
    labelLarge: body(base.labelLarge),
    labelMedium: body(base.labelMedium),
    labelSmall: body(base.labelSmall),
  );
}
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `flutter test test/core/theme/app_text_theme_test.dart`
Expected: PASS (3 tests). Still a plain `test()` — fast.

- [ ] **Step 6: Analyze and commit**

Run: `flutter analyze`
Expected: `No issues found!`

```bash
git add pubspec.yaml pubspec.lock lib/core/theme/app_text_theme.dart test/core/theme/app_text_theme_test.dart
git commit -m "Add Unbounded/Manrope text theme for the Electric Violet redesign"
```

---

### Task 3: AppTheme (ColorScheme + component themes)

**Files:**
- Create: `lib/core/theme/app_theme.dart`
- Test: `test/core/theme/app_theme_test.dart`

**Interfaces:**
- Consumes: `HickoryColors.light`/`.dark` (Task 1), `buildAppTextTheme` (Task 2).
- Produces: `AppTheme.light` and `AppTheme.dark` (both `ThemeData` getters).

- [ ] **Step 1: Write the failing test**

```dart
// test/core/theme/app_theme_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/core/theme/app_theme.dart';
import 'package:hickory/core/theme/hickory_colors.dart';

void main() {
  test('light/dark themes report the right brightness', () {
    expect(AppTheme.light.brightness, Brightness.light);
    expect(AppTheme.dark.brightness, Brightness.dark);
  });

  test('HickoryColors is registered as a theme extension on both themes', () {
    expect(AppTheme.light.extension<HickoryColors>(), HickoryColors.light);
    expect(AppTheme.dark.extension<HickoryColors>(), HickoryColors.dark);
  });

  test('buttons are pill-shaped and cards use 24px corners', () {
    final buttonShape = AppTheme.dark.filledButtonTheme.style?.shape?.resolve({});
    expect(buttonShape, isA<StadiumBorder>());

    final cardShape = AppTheme.dark.cardTheme.shape as RoundedRectangleBorder?;
    expect(cardShape?.borderRadius, BorderRadius.circular(24));
  });

  test('nav bar always shows labels so the active/inactive layout never shifts', () {
    expect(
      AppTheme.dark.navigationBarTheme.labelBehavior,
      NavigationDestinationLabelBehavior.alwaysShow,
    );
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/core/theme/app_theme_test.dart`
Expected: FAIL — `package:hickory/core/theme/app_theme.dart` doesn't exist yet.

- [ ] **Step 3: Write the implementation**

```dart
// lib/core/theme/app_theme.dart
import 'package:flutter/material.dart';

import 'app_text_theme.dart';
import 'hickory_colors.dart';

/// Builds Hickory's light/dark ThemeData from the Electric Violet tokens in
/// docs/superpowers/specs/2026-07-07-electric-violet-redesign-design.md.
///
/// Starts from ColorScheme.fromSeed (so any Material component we haven't
/// explicitly themed still gets a reasonable, harmonious color) and then
/// pins the roles the spec cares about to its exact hex values — the seed
/// algorithm alone tends to desaturate toward muted, accessible-but-flat
/// tones and would lose the vividness validated in the design mockups.
abstract final class AppTheme {
  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);

  static const _pillShape = StadiumBorder();
  static const _cardRadius = 24.0;

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final tokens = isDark ? HickoryColors.dark : HickoryColors.light;
    final surface = isDark ? const Color(0xFF150F1E) : const Color(0xFFFBF7FF);
    final cardSurface = isDark ? const Color(0xFF1F1729) : Colors.white;
    final onSurface = isDark ? const Color(0xFFF1ECF7) : const Color(0xFF241A30);

    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFFB678FF),
      brightness: brightness,
    ).copyWith(
      primary: tokens.timerNumeral,
      onPrimary: tokens.onPrimaryGradient,
      secondary: tokens.chipText,
      surface: surface,
      onSurface: onSurface,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: surface,
      textTheme: buildAppTextTheme(brightness),
      extensions: [tokens],
      cardTheme: CardThemeData(
        color: cardSurface,
        elevation: isDark ? 0 : 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_cardRadius)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: _pillShape,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: _pillShape,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        ),
      ),
      textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(shape: _pillShape)),
      chipTheme: ChipThemeData(
        backgroundColor: tokens.chipBackground,
        labelStyle: TextStyle(color: tokens.chipText, fontWeight: FontWeight.w600, fontSize: 11),
        shape: _pillShape,
        side: BorderSide.none,
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_cardRadius)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: tokens.navBackground,
        indicatorColor: tokens.navActiveIcon.withValues(alpha: 0.16),
        indicatorShape: _pillShape,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected) ? tokens.navActiveIcon : tokens.navInactive,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: states.contains(WidgetState.selected) ? tokens.navActiveLabel : tokens.navInactive,
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/core/theme/app_theme_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5: Analyze and commit**

Run: `flutter analyze`
Expected: `No issues found!`

```bash
git add lib/core/theme/app_theme.dart test/core/theme/app_theme_test.dart
git commit -m "Add AppTheme combining tokens, text theme, and pill/rounded component themes"
```

---

### Task 4: Wire app.dart to AppTheme

**Files:**
- Modify: `lib/app.dart`

**Interfaces:**
- Consumes: `AppTheme.light`, `AppTheme.dark` (Task 3).

- [ ] **Step 1: Replace the theme construction**

Current `lib/app.dart`:

```dart
import 'package:flutter/material.dart';

import 'features/timer/timer_screen.dart';

class HickoryApp extends StatelessWidget {
  const HickoryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Hickory',
      theme: ThemeData(colorSchemeSeed: const Color(0xFF5B8DEF), useMaterial3: true),
      darkTheme: ThemeData(
        colorSchemeSeed: const Color(0xFF5B8DEF),
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: const TimerScreen(),
    );
  }
}
```

New `lib/app.dart`:

```dart
import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'features/timer/timer_screen.dart';

class HickoryApp extends StatelessWidget {
  const HickoryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Hickory',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      home: const TimerScreen(),
    );
  }
}
```

`home` stays `TimerScreen` for now — the shell lands in Task 10. This step is a pure re-theme: existing screens keep their own `Scaffold`/`AppBar` and just render with the new colors, pill buttons, and fonts, which is a good checkpoint to verify the token/theme layer is wired correctly before restructuring navigation.

- [ ] **Step 2: Analyze**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 3: Run the full test suite**

Run: `flutter test`
Expected: all existing tests still pass (`formatDuration`, sync round-trip/watcher, report calculations, csv export) plus the 10 new theme tests from Tasks 1–3 — none of this touches business logic, so nothing here should break.

- [ ] **Step 4: Build and manually confirm the re-theme**

Run: `flutter build windows --debug`
Expected: builds successfully.

Launch `build\windows\x64\runner\Debug\hickory.exe` and confirm visually (or via a screenshot — see Task 11 for the capture procedure) that the Start button and cards now render in violet/pink tones with pill-shaped buttons, Unbounded numerals, instead of the old default blue Material look.

- [ ] **Step 5: Commit**

```bash
git add lib/app.dart
git commit -m "Wire AppTheme into HickoryApp"
```

---

### Task 5: Gradient button widgets

**Files:**
- Create: `lib/core/widgets/gradient_buttons.dart`
- Test: `test/core/widgets/gradient_buttons_test.dart`

**Interfaces:**
- Produces:
  - `GradientPillButton({required String label, required IconData icon, required List<Color> gradient, required Color foregroundColor, required VoidCallback? onPressed})` — always full-width, pill-shaped, gradient-filled.
  - `GradientFab({required IconData icon, required List<Color> gradient, required Color foregroundColor, required VoidCallback? onPressed})` — 56×56 circular gradient FAB.

This is the first `testWidgets` test in this plan. It has **no** Riverpod/timer/stream dependency, so it doesn't hit the pending-timer issue noted in Global Constraints — but expect the `flutter test` run to take several minutes on this machine purely from `flutter_tester` engine startup (a one-time cost per run, not per test).

- [ ] **Step 1: Write the failing test**

```dart
// test/core/widgets/gradient_buttons_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/core/widgets/gradient_buttons.dart';

void main() {
  testWidgets('GradientPillButton renders its label and invokes onPressed', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GradientPillButton(
            label: 'Stop',
            icon: Icons.stop,
            gradient: const [Color(0xFFB678FF), Color(0xFFFF6FA9)],
            foregroundColor: const Color(0xFF160A22),
            onPressed: () => tapped = true,
          ),
        ),
      ),
    );

    expect(find.text('Stop'), findsOneWidget);

    await tester.tap(find.text('Stop'));
    await tester.pump();

    expect(tapped, isTrue);
  });

  testWidgets('GradientFab renders its icon and invokes onPressed', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GradientFab(
            icon: Icons.add,
            gradient: const [Color(0xFFB678FF), Color(0xFFFF6FA9)],
            foregroundColor: const Color(0xFF160A22),
            onPressed: () => tapped = true,
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.add), findsOneWidget);

    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();

    expect(tapped, isTrue);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/core/widgets/gradient_buttons_test.dart`
Expected: FAIL — `package:hickory/core/widgets/gradient_buttons.dart` doesn't exist yet.

- [ ] **Step 3: Write the implementation**

```dart
// lib/core/widgets/gradient_buttons.dart
import 'package:flutter/material.dart';

/// A full-width, pill-shaped button with a gradient fill — Flutter's
/// ButtonStyle can't express a gradient background, so primary actions
/// (Start/Stop) use this instead of FilledButton.
class GradientPillButton extends StatelessWidget {
  const GradientPillButton({
    super.key,
    required this.label,
    required this.icon,
    required this.gradient,
    required this.foregroundColor,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final List<Color> gradient;
  final Color foregroundColor;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Material(
        color: Colors.transparent,
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: Ink(
          decoration: BoxDecoration(gradient: LinearGradient(colors: gradient)),
          child: InkWell(
            onTap: onPressed,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 18, color: foregroundColor),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: TextStyle(
                      color: foregroundColor,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A circular, gradient-filled floating action button — same rationale as
/// GradientPillButton: FloatingActionButton's backgroundColor can't be a
/// gradient.
class GradientFab extends StatelessWidget {
  const GradientFab({
    super.key,
    required this.icon,
    required this.gradient,
    required this.foregroundColor,
    required this.onPressed,
  });

  final IconData icon;
  final List<Color> gradient;
  final Color foregroundColor;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      elevation: 4,
      child: Ink(
        width: 56,
        height: 56,
        decoration: BoxDecoration(gradient: LinearGradient(colors: gradient), shape: BoxShape.circle),
        child: InkWell(
          onTap: onPressed,
          child: Icon(icon, color: foregroundColor),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/core/widgets/gradient_buttons_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Analyze and commit**

Run: `flutter analyze`
Expected: `No issues found!`

```bash
git add lib/core/widgets/gradient_buttons.dart test/core/widgets/gradient_buttons_test.dart
git commit -m "Add GradientPillButton and GradientFab widgets"
```

---

### Task 6: Restyle TimerScreen and drop its Scaffold/AppBar

**Files:**
- Modify: `lib/features/timer/timer_screen.dart`

**Interfaces:**
- Consumes: `HickoryColors.of(BuildContext)` (Task 1), `GradientPillButton` (Task 5).
- Produces: `TimerScreen` now returns body-only content (no `Scaffold`/`AppBar`) — the Task 10 shell relies on this.

After this task, Reports and Sync are temporarily unreachable from the UI (their trigger points, the AppBar icons, are removed here) until the shell lands in Task 10. This is expected for this refactor — `flutter analyze`/`flutter test`/the build stay green throughout, which is the bar for each task in this plan. `lib/features/sync/sync_settings_dialog.dart` becomes unreferenced after this task but isn't deleted until Task 8, where its replacement (`sync_screen.dart`) is created in the same task — avoids a gap where neither file exists.

- [ ] **Step 1: Replace the file**

New `lib/features/timer/timer_screen.dart`:

```dart
import 'package:activity_tracker/activity_tracker.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/device_id_provider.dart';
import '../../core/di/sync_providers.dart';
import '../../core/format/duration_format.dart';
import '../../core/theme/hickory_colors.dart';
import '../../core/widgets/gradient_buttons.dart';
import '../../data/drift/database.dart';
import '../entries/entries_list.dart';
import '../entries/manual_entry_dialog.dart';
import '../projects/new_project_dialog.dart';
import '../projects/projects_providers.dart';
import 'idle_prompt_dialog.dart';
import 'idle_tracking.dart';
import 'timer_providers.dart';

/// Idle time is prompted about once it reaches this threshold, on desktop
/// only (see [isDesktopTrackingSupported]).
const _idleThresholdSeconds = 5 * 60;

/// Timer tab content — hosted by the app shell (features/shell/app_shell.dart),
/// which owns the Scaffold, AppBar, bottom nav, and the manual-entry FAB.
class TimerScreen extends ConsumerStatefulWidget {
  const TimerScreen({super.key});

  @override
  ConsumerState<TimerScreen> createState() => _TimerScreenState();
}

class _TimerScreenState extends ConsumerState<TimerScreen> {
  final _descriptionController = TextEditingController();
  String? _selectedProjectId;
  bool _idlePromptShowing = false;

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _handleIdleSecondsChanged(int idleSeconds) async {
    if (idleSeconds < _idleThresholdSeconds) {
      _idlePromptShowing = false;
      return;
    }
    if (_idlePromptShowing) return;
    final running = ref.read(runningEntryProvider).value;
    if (running == null) return;

    _idlePromptShowing = true;
    final idleDuration = Duration(seconds: idleSeconds);
    final shouldTrim = await showIdlePromptDialog(context, idleDuration);
    if (!mounted) return;
    if (shouldTrim) {
      final writes = await ref.read(syncedWritesProvider.future);
      final idleStart = DateTime.now().subtract(idleDuration);
      await writes.updateEntry(running.id, endAt: Value(idleStart.toUtc()));
    }
    _idlePromptShowing = false;
  }

  Future<void> _recordActivitySample(ActivitySample sample) async {
    final running = ref.read(runningEntryProvider).value;
    if (running == null) return;
    final deviceId = await ref.read(deviceIdProvider.future);
    final writes = await ref.read(syncedWritesProvider.future);
    await writes.recordActivitySample(
      deviceId: deviceId,
      appName: sample.appName,
      windowTitle: sample.windowTitle,
      observedAt: sample.observedAt,
    );
  }

  Future<void> _start() async {
    final deviceId = await ref.read(deviceIdProvider.future);
    final writes = await ref.read(syncedWritesProvider.future);
    await writes.startEntry(
      deviceId: deviceId,
      projectId: _selectedProjectId,
      description: _descriptionController.text.trim().isEmpty
          ? null
          : _descriptionController.text.trim(),
    );
    _descriptionController.clear();
  }

  Future<void> _stop(TimeEntry running) async {
    final writes = await ref.read(syncedWritesProvider.future);
    await writes.stopEntry(running.id);
  }

  @override
  Widget build(BuildContext context) {
    final runningAsync = ref.watch(runningEntryProvider);
    ref.watch(timerTickProvider);
    ref.watch(syncWatcherProvider);

    ref.listen<AsyncValue<int>>(idleSecondsProvider, (previous, next) {
      final idleSeconds = next.value;
      if (idleSeconds != null) _handleIdleSecondsChanged(idleSeconds);
    });
    ref.listen<AsyncValue<ActivitySample>>(activeWindowChangesProvider, (previous, next) {
      final sample = next.value;
      if (sample != null) _recordActivitySample(sample);
    });

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          runningAsync.when(
            data: (running) => running != null
                ? _RunningCard(running: running, onStop: () => _stop(running))
                : _StartCard(
                    descriptionController: _descriptionController,
                    selectedProjectId: _selectedProjectId,
                    onProjectChanged: (id) => setState(() => _selectedProjectId = id),
                    onStart: _start,
                  ),
            loading: () => const CircularProgressIndicator(),
            error: (e, _) => Text('Fehler: $e'),
          ),
          const SizedBox(height: 16),
          const Expanded(child: EntriesList()),
        ],
      ),
    );
  }
}

class _RunningCard extends ConsumerWidget {
  const _RunningCard({required this.running, required this.onStop});

  final TimeEntry running;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final elapsed = DateTime.now().toUtc().difference(running.startAt);
    final tokens = HickoryColors.of(context);
    final projectsAsync = ref.watch(activeProjectsProvider);
    final projectsById = {
      for (final p in projectsAsync.value ?? const <Project>[]) p.id: p,
    };
    final project = running.projectId == null ? null : projectsById[running.projectId];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: tokens.surfaceGradient,
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            formatDuration(elapsed),
            style: TextStyle(
              fontFamily: Theme.of(context).textTheme.displayLarge?.fontFamily,
              fontWeight: FontWeight.w700,
              fontSize: 34,
              color: tokens.timerNumeral,
            ),
          ),
          if (running.description?.isNotEmpty ?? false) ...[
            const SizedBox(height: 6),
            Text(running.description!),
          ],
          if (project != null) ...[
            const SizedBox(height: 8),
            Chip(label: Text(project.name)),
          ],
          const SizedBox(height: 16),
          GradientPillButton(
            label: 'Stop',
            icon: Icons.stop,
            gradient: tokens.primaryGradient,
            foregroundColor: tokens.onPrimaryGradient,
            onPressed: onStop,
          ),
        ],
      ),
    );
  }
}

class _StartCard extends ConsumerWidget {
  const _StartCard({
    required this.descriptionController,
    required this.selectedProjectId,
    required this.onProjectChanged,
    required this.onStart,
  });

  final TextEditingController descriptionController;
  final String? selectedProjectId;
  final ValueChanged<String?> onProjectChanged;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projectsAsync = ref.watch(activeProjectsProvider);
    final tokens = HickoryColors.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: descriptionController,
              decoration: const InputDecoration(labelText: 'Was arbeitest du gerade?'),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: projectsAsync.when(
                    data: (projects) => DropdownButtonFormField<String?>(
                      initialValue: selectedProjectId,
                      decoration: const InputDecoration(labelText: 'Projekt'),
                      items: [
                        const DropdownMenuItem<String?>(value: null, child: Text('Kein Projekt')),
                        ...projects.map(
                          (p) => DropdownMenuItem<String?>(value: p.id, child: Text(p.name)),
                        ),
                      ],
                      onChanged: onProjectChanged,
                    ),
                    loading: () => const LinearProgressIndicator(),
                    error: (e, _) => Text('Fehler: $e'),
                  ),
                ),
                IconButton(
                  tooltip: 'Neues Projekt',
                  onPressed: () => showNewProjectDialog(context, ref),
                  icon: const Icon(Icons.add_box_outlined),
                ),
              ],
            ),
            const SizedBox(height: 12),
            GradientPillButton(
              label: 'Start',
              icon: Icons.play_arrow,
              gradient: tokens.primaryGradient,
              foregroundColor: tokens.onPrimaryGradient,
              onPressed: onStart,
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Analyze**

Run: `flutter analyze`
Expected: `No issues found!` (confirms `showManualEntryDialog`/`showNewProjectDialog` imports are still used; `sync_settings_dialog.dart` still compiles standalone even though nothing imports it anymore — Dart doesn't flag unreferenced files, only unused imports/members within reachable code).

- [ ] **Step 3: Run the full test suite**

Run: `flutter test`
Expected: all tests still pass — this task only touches presentation code.

- [ ] **Step 4: Commit**

```bash
git add lib/features/timer/timer_screen.dart
git commit -m "Restyle TimerScreen for Electric Violet; drop its Scaffold/AppBar"
```

---

### Task 7: Restyle EntriesList (pill rows, FAB clearance)

**Files:**
- Modify: `lib/features/entries/entries_list.dart`

**Interfaces:**
- Consumes: nothing new (styling only; `syncedWritesProvider`, `allEntriesProvider`, `activeProjectsProvider` already in use).

The Task 10 shell places a FAB in the bottom-right, floating above the bottom nav bar. `ListView`'s default padding is zero, so without reserved space the FAB would sit on top of the last entry — this is the overlap the user caught during the mockup review. Reserve `88` logical pixels (56px FAB + 16px margin on each side, rounded up) at the bottom of the scrollable list.

- [ ] **Step 1: Replace the file**

New `lib/features/entries/entries_list.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/sync_providers.dart';
import '../../core/format/duration_format.dart';
import '../../data/drift/database.dart';
import '../projects/projects_providers.dart';
import '../timer/timer_providers.dart';
import 'manual_entry_dialog.dart';

/// Reserves space so the shell's floating action button (56px + margin)
/// never overlaps the last entry — caught during design review, when an
/// early mockup had the FAB sitting on top of list content.
const _bottomPaddingForFab = 88.0;

class EntriesList extends ConsumerWidget {
  const EntriesList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entriesAsync = ref.watch(allEntriesProvider);
    final projectsAsync = ref.watch(activeProjectsProvider);

    return entriesAsync.when(
      data: (entries) {
        final finished = entries.where((e) => e.endAt != null).toList();
        if (finished.isEmpty) {
          return const Center(child: Text('Noch keine Einträge.'));
        }
        final projectsById = {
          for (final p in projectsAsync.value ?? const <Project>[]) p.id: p,
        };
        return ListView.builder(
          padding: const EdgeInsets.only(bottom: _bottomPaddingForFab),
          itemCount: finished.length,
          itemBuilder: (context, index) {
            final entry = finished[index];
            final project = entry.projectId == null ? null : projectsById[entry.projectId];
            final duration = entry.endAt!.difference(entry.startAt);
            return Dismissible(
              key: ValueKey(entry.id),
              direction: DismissDirection.endToStart,
              background: Container(
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(999),
                ),
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: const Icon(Icons.delete_outline),
              ),
              onDismissed: (_) {
                ref.read(syncedWritesProvider.future).then((w) => w.deleteEntry(entry.id));
              },
              child: Card(
                margin: const EdgeInsets.only(bottom: 8),
                shape: const StadiumBorder(),
                child: ListTile(
                  shape: const StadiumBorder(),
                  leading: CircleAvatar(
                    backgroundColor: project != null
                        ? Color(int.parse(project.colorHex.replaceFirst('#', '0xFF')))
                        : Colors.grey,
                    radius: 8,
                    child: const SizedBox.shrink(),
                  ),
                  title: Text(entry.description?.isNotEmpty == true
                      ? entry.description!
                      : (project?.name ?? 'Ohne Beschreibung')),
                  subtitle: Text(
                    '${project?.name ?? 'Kein Projekt'} · ${entry.startAt.toLocal()}',
                  ),
                  trailing: Text(formatDuration(duration)),
                  onTap: () => showManualEntryDialog(context, ref, existing: entry),
                ),
              ),
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => Center(child: Text('Fehler: $error')),
    );
  }
}
```

The `Card`'s own `CardThemeData` (24px corners, from Task 3) is overridden per-row to `StadiumBorder()` since a fixed pill radius, not the global card radius, is what makes a short row read as a pill — matching the entries in the approved mockups.

- [ ] **Step 2: Analyze**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 3: Run the full test suite**

Run: `flutter test`
Expected: all tests still pass.

- [ ] **Step 4: Commit**

```bash
git add lib/features/entries/entries_list.dart
git commit -m "Restyle EntriesList as pill rows; reserve bottom space for the FAB"
```

---

### Task 8: SyncScreen (promote the dialog to a full screen)

**Files:**
- Create: `lib/features/sync/sync_screen.dart`
- Delete: `lib/features/sync/sync_settings_dialog.dart` (unreferenced since Task 6; kept until now so its replacement lands in the same task)

**Interfaces:**
- Consumes: `configuredSyncFolderPathProvider`, `pickAndApplySyncFolder`, `syncIngestorProvider` (all existing, from `core/di/sync_providers.dart`).
- Produces: `class SyncScreen extends ConsumerStatefulWidget` — body-only content (no own `Scaffold`), consumed by the Task 10 shell.

This carries over the logic from `sync_settings_dialog.dart` (unreferenced since Task 6, deleted in this task's Step 2) unchanged — only the presentation shell (dialog chrome → screen body) and buttons (now themed pill-shaped via Task 3, no bespoke styling needed) change.

- [ ] **Step 1: Write the file**

```dart
// lib/features/sync/sync_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/sync_providers.dart';

class SyncScreen extends ConsumerStatefulWidget {
  const SyncScreen({super.key});

  @override
  ConsumerState<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends ConsumerState<SyncScreen> {
  bool _busy = false;
  String? _statusMessage;

  Future<void> _pickFolder() async {
    setState(() {
      _busy = true;
      _statusMessage = null;
    });
    try {
      final picked = await pickAndApplySyncFolder(ref);
      setState(() {
        _statusMessage = picked == null ? null : 'Ordner gewählt: $picked';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _syncNow() async {
    setState(() {
      _busy = true;
      _statusMessage = null;
    });
    try {
      final ingestor = await ref.read(syncIngestorProvider.future);
      await ingestor.syncNow();
      setState(() => _statusMessage = 'Synchronisierung abgeschlossen.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final folderAsync = ref.watch(configuredSyncFolderPathProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Sync-Einstellungen', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  folderAsync.when(
                    data: (path) => Text(
                      path == null
                          ? 'Kein Ordner gewählt – Daten bleiben nur lokal auf diesem Gerät.'
                          : 'Sync-Ordner: $path',
                    ),
                    loading: () => const LinearProgressIndicator(),
                    error: (e, _) => Text('Fehler: $e'),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Wähle einen Ordner, der bereits von iCloud Drive, Google Drive, '
                    'Dropbox o.ä. synchronisiert wird. Hickory schreibt dort nur '
                    'eigene Dateien und synchronisiert sich selbst nicht mit der Cloud.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (_statusMessage != null) ...[
                    const SizedBox(height: 12),
                    Text(_statusMessage!, style: Theme.of(context).textTheme.bodySmall),
                  ],
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      OutlinedButton(
                        onPressed: _busy ? null : _syncNow,
                        child: const Text('Jetzt synchronisieren'),
                      ),
                      FilledButton(
                        onPressed: _busy ? null : _pickFolder,
                        child: const Text('Ordner wählen'),
                      ),
                    ],
                  ),
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

- [ ] **Step 2: Delete the old dialog it replaces**

```bash
rm lib/features/sync/sync_settings_dialog.dart
```

- [ ] **Step 3: Analyze**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 4: Commit**

```bash
git add lib/features/sync/sync_screen.dart
git rm lib/features/sync/sync_settings_dialog.dart
git commit -m "Add SyncScreen as a full-screen replacement for the Sync dialog"
```

---

### Task 9: Restyle ReportsScreen and drop its Scaffold/AppBar

**Files:**
- Modify: `lib/features/reports/reports_screen.dart`

**Interfaces:**
- Produces: `ReportsScreen` now returns body-only content (no `Scaffold`/`AppBar`) — the Task 10 shell relies on this.

`ChoiceChip`'s selected-state color isn't covered by the global `ChipThemeData` from Task 3 (that theme only sets the default/unselected look), so the selected state is tinted explicitly here to the same violet used elsewhere for "active" state (matches `HickoryColors.navActiveIcon`, reused for consistency rather than inventing a new token).

- [ ] **Step 1: Replace the file**

New `lib/features/reports/reports_screen.dart`:

```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format/duration_format.dart';
import '../../core/theme/hickory_colors.dart';
import '../../data/drift/database.dart';
import 'csv_export.dart';
import 'report_calculations.dart';
import 'reports_providers.dart';

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  ReportRangePreset? _selectedPreset = ReportRangePreset.thisMonth;
  String? _exportStatus;

  void _selectPreset(ReportRangePreset preset) {
    setState(() => _selectedPreset = preset);
    ref.read(reportRangeProvider.notifier).state = rangeForPreset(preset);
  }

  Future<void> _selectCustomRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 1),
      initialDateRange: ref.read(reportRangeProvider),
    );
    if (picked == null) return;
    setState(() => _selectedPreset = null);
    // showDateRangePicker's end date is inclusive-at-midnight; our range end
    // is exclusive, so push it one day forward to include the whole day.
    ref.read(reportRangeProvider.notifier).state = DateTimeRange(
      start: DateTime(picked.start.year, picked.start.month, picked.start.day),
      end: DateTime(
        picked.end.year,
        picked.end.month,
        picked.end.day,
      ).add(const Duration(days: 1)),
    );
  }

  Future<void> _exportCsv(List<TimeEntry> entries, List<Project> projects) async {
    final csv = entriesToCsv(entries, projects);
    final path = await FilePicker.saveFile(
      dialogTitle: 'CSV exportieren',
      fileName: 'hickory-export.csv',
      type: FileType.custom,
      allowedExtensions: ['csv'],
      bytes: Uint8List.fromList(utf8.encode(csv)),
    );
    if (!mounted) return;
    setState(() => _exportStatus = path == null ? null : 'Exportiert nach: $path');
  }

  @override
  Widget build(BuildContext context) {
    final entriesAsync = ref.watch(reportEntriesProvider);
    final projectsAsync = ref.watch(reportProjectsProvider);
    final tokens = HickoryColors.of(context);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Reports', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _presetChip('Diese Woche', ReportRangePreset.thisWeek, tokens),
              _presetChip('Dieser Monat', ReportRangePreset.thisMonth, tokens),
              _presetChip('Letzte 30 Tage', ReportRangePreset.last30Days, tokens),
              _presetChip('Alle', ReportRangePreset.all, tokens),
              ActionChip(
                label: const Text('Benutzerdefiniert…'),
                onPressed: _selectCustomRange,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: entriesAsync.when(
              data: (entries) => projectsAsync.when(
                data: (projects) => _ReportBody(
                  entries: entries,
                  projects: projects,
                  onExport: () => _exportCsv(entries, projects),
                ),
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Fehler: $e')),
              ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Fehler: $e')),
            ),
          ),
          if (_exportStatus != null) ...[
            const SizedBox(height: 8),
            Text(_exportStatus!, style: Theme.of(context).textTheme.bodySmall),
          ],
        ],
      ),
    );
  }

  Widget _presetChip(String label, ReportRangePreset preset, HickoryColors tokens) {
    final selected = _selectedPreset == preset;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      selectedColor: tokens.navActiveIcon.withValues(alpha: 0.22),
      onSelected: (_) => _selectPreset(preset),
    );
  }
}

class _ReportBody extends StatelessWidget {
  const _ReportBody({required this.entries, required this.projects, required this.onExport});

  final List<TimeEntry> entries;
  final List<Project> projects;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    final totals = totalsByProject(entries, projects);
    final totalDuration = totals.fold<Duration>(Duration.zero, (sum, t) => sum + t.duration);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Gesamt: ${formatDuration(totalDuration)}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            FilledButton.icon(
              onPressed: entries.isEmpty ? null : onExport,
              icon: const Icon(Icons.download),
              label: const Text('CSV exportieren'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: totals.isEmpty
              ? const Center(child: Text('Keine Einträge in diesem Zeitraum.'))
              : ListView.builder(
                  itemCount: totals.length,
                  itemBuilder: (context, index) {
                    final total = totals[index];
                    final amount = total.amountCents == null
                        ? null
                        : '${(total.amountCents! / 100).toStringAsFixed(2)} ${total.currency ?? ''}';
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      shape: const StadiumBorder(),
                      child: ListTile(
                        shape: const StadiumBorder(),
                        title: Text(total.projectName),
                        subtitle: amount == null ? null : Text(amount),
                        trailing: Text(formatDuration(total.duration)),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
```

- [ ] **Step 2: Analyze**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 3: Run the full test suite**

Run: `flutter test`
Expected: all tests still pass — `report_calculations_test.dart`/`csv_export_test.dart` exercise `totalsByProject`/`entriesToCsv` directly and aren't affected by this widget-only change.

- [ ] **Step 4: Commit**

```bash
git add lib/features/reports/reports_screen.dart
git commit -m "Restyle ReportsScreen for Electric Violet; drop its Scaffold/AppBar"
```

---

### Task 10: Bottom-nav shell

**Files:**
- Create: `lib/features/shell/nav_shell.dart`
- Create: `lib/features/shell/app_shell.dart`
- Modify: `lib/app.dart`
- Test: `test/features/shell/nav_shell_test.dart`

**Interfaces:**
- Consumes: `TimerScreen` (Task 6), `ReportsScreen` (Task 9), `SyncScreen` (Task 8), `showManualEntryDialog` (existing).
- Produces:
  - `NavShell({required List<Widget> children, required List<NavigationDestination> destinations, int initialIndex = 0, Widget? Function(int selectedIndex)? fabBuilder})` — no Riverpod dependency, generic bottom-nav container.
  - `AppShell` — `ConsumerWidget` wiring `NavShell` to the three real screens.

`NavShell` is deliberately generic and Riverpod-free (takes plain widgets/destinations as parameters) specifically so it's testable with dummy children — pumping the *real* `TimerScreen` would drag in `timerTickProvider`/`syncWatcherProvider`/etc., which is exactly the flakiness this plan's Global Constraints steer away from. `AppShell` is the thin, untested-by-widget-test layer that wires the real screens in.

- [ ] **Step 1: Write the failing test**

```dart
// test/features/shell/nav_shell_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/features/shell/nav_shell.dart';

void main() {
  testWidgets('shows the initial tab and its FAB, switches on tap, hides the FAB '
      'on tabs with none', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: NavShell(
          destinations: const [
            NavigationDestination(icon: Icon(Icons.timer_outlined), label: 'Timer'),
            NavigationDestination(icon: Icon(Icons.bar_chart_outlined), label: 'Reports'),
          ],
          children: const [
            Center(child: Text('Timer content')),
            Center(child: Text('Reports content')),
          ],
          fabBuilder: (selectedIndex) =>
              selectedIndex == 0 ? FloatingActionButton(onPressed: () {}, child: const Icon(Icons.add)) : null,
        ),
      ),
    );

    expect(find.text('Timer content'), findsOneWidget);
    expect(find.text('Reports content'), findsNothing);
    expect(find.byType(FloatingActionButton), findsOneWidget);

    await tester.tap(find.text('Reports'));
    await tester.pumpAndSettle();

    expect(find.text('Timer content'), findsNothing);
    expect(find.text('Reports content'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/features/shell/nav_shell_test.dart`
Expected: FAIL — `package:hickory/features/shell/nav_shell.dart` doesn't exist yet.

- [ ] **Step 3: Write NavShell**

```dart
// lib/features/shell/nav_shell.dart
import 'package:flutter/material.dart';

/// A generic bottom-navigation container: index state, an IndexedStack of
/// [children], a NavigationBar built from [destinations], and an optional
/// per-tab floating action button via [fabBuilder]. Has no Riverpod (or any
/// other app-specific) dependency on purpose — see AppShell for the real
/// wiring, and Task 10 in the implementation plan for why that split
/// exists (keeps this widget cheaply testable with dummy children).
class NavShell extends StatefulWidget {
  const NavShell({
    super.key,
    required this.children,
    required this.destinations,
    this.initialIndex = 0,
    this.fabBuilder,
  }) : assert(children.length == destinations.length);

  final List<Widget> children;
  final List<NavigationDestination> destinations;
  final int initialIndex;
  final Widget? Function(int selectedIndex)? fabBuilder;

  @override
  State<NavShell> createState() => _NavShellState();
}

class _NavShellState extends State<NavShell> {
  late int _selectedIndex = widget.initialIndex;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Hickory')),
      body: IndexedStack(index: _selectedIndex, children: widget.children),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        destinations: widget.destinations,
        onDestinationSelected: (index) => setState(() => _selectedIndex = index),
      ),
      floatingActionButton: widget.fabBuilder?.call(_selectedIndex),
    );
  }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/features/shell/nav_shell_test.dart`
Expected: PASS (1 test).

- [ ] **Step 5: Write AppShell**

```dart
// lib/features/shell/app_shell.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../entries/manual_entry_dialog.dart';
import '../reports/reports_screen.dart';
import '../sync/sync_screen.dart';
import '../timer/timer_screen.dart';
import 'nav_shell.dart';

/// Wires the real Timer/Reports/Sync screens and the manual-entry FAB into
/// NavShell. This is Hickory's app-level navigation root (used as
/// MaterialApp.home in lib/app.dart).
class AppShell extends ConsumerWidget {
  const AppShell({super.key});

  static const _destinations = [
    NavigationDestination(
      icon: Icon(Icons.timer_outlined),
      selectedIcon: Icon(Icons.timer),
      label: 'Timer',
    ),
    NavigationDestination(
      icon: Icon(Icons.bar_chart_outlined),
      selectedIcon: Icon(Icons.bar_chart),
      label: 'Reports',
    ),
    NavigationDestination(
      icon: Icon(Icons.sync_outlined),
      selectedIcon: Icon(Icons.sync),
      label: 'Sync',
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return NavShell(
      destinations: _destinations,
      children: const [TimerScreen(), ReportsScreen(), SyncScreen()],
      fabBuilder: (selectedIndex) => selectedIndex == 0
          ? FloatingActionButton(
              onPressed: () => showManualEntryDialog(context, ref),
              child: const Icon(Icons.add),
            )
          : null,
    );
  }
}
```

`FloatingActionButton` (not `GradientFab`) is used here deliberately for now — see Task 11's manual verification step, which should visually confirm whether the plain themed FAB reads well enough against the spec's gradient-FAB mockup or whether a follow-up swap to `GradientFab` is warranted; wiring `GradientFab` here directly is one line (`GradientFab(icon: Icons.add, gradient: HickoryColors.of(context).primaryGradient, foregroundColor: HickoryColors.of(context).onPrimaryGradient, onPressed: ...)`) if so.

- [ ] **Step 6: Wire app.dart to AppShell**

In `lib/app.dart`, replace:

```dart
import 'features/timer/timer_screen.dart';
```

with:

```dart
import 'features/shell/app_shell.dart';
```

and replace:

```dart
      home: const TimerScreen(),
```

with:

```dart
      home: const AppShell(),
```

- [ ] **Step 7: Analyze**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 8: Run the full test suite**

Run: `flutter test`
Expected: all tests pass, including the new `nav_shell_test.dart`.

- [ ] **Step 9: Build and manually verify navigation**

Run: `flutter build windows --debug`, launch the exe, and confirm all three tabs are reachable, the FAB only shows on the Timer tab, and tapping a manual-entry FAB still opens the dialog. See Task 11 for the full screenshot-based verification procedure.

- [ ] **Step 10: Commit**

```bash
git add lib/features/shell/nav_shell.dart lib/features/shell/app_shell.dart lib/app.dart test/features/shell/nav_shell_test.dart
git commit -m "Add bottom-nav shell (NavShell + AppShell); wire it as the app root"
```

---

### Task 11: Manual visual verification

**Files:** none (verification only).

- [ ] **Step 1: Build**

```powershell
flutter build windows --debug
```

Expected: `✓ Built build\windows\x64\runner\Debug\hickory.exe`

- [ ] **Step 2: Launch and force it to the foreground**

`PrintWindow`-based capture was tried during design review and silently dropped the AppBar's action icons (a real capture bug on this machine, not a rendering bug) — use `AttachThreadInput` + `SetForegroundWindow` + a full-screen `CopyFromScreen`, which was confirmed to capture correctly:

```powershell
$exePath = "C:\Users\mordi\Development\hickory\build\windows\x64\runner\Debug\hickory.exe"
$proc = Start-Process -FilePath $exePath -PassThru
Start-Sleep -Seconds 3

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class Win32Force {
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, IntPtr ProcessId);
    [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint idAttach, uint idAttachTo, bool fAttach);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
}
"@ -ErrorAction SilentlyContinue

$proc.Refresh()
$hwnd = $proc.MainWindowHandle
$fgWindow = [Win32Force]::GetForegroundWindow()
$fgThread = [Win32Force]::GetWindowThreadProcessId($fgWindow, [IntPtr]::Zero)
$curThread = [Win32Force]::GetCurrentThreadId()

[Win32Force]::AttachThreadInput($curThread, $fgThread, $true) | Out-Null
[Win32Force]::ShowWindow($hwnd, 3) | Out-Null
[Win32Force]::SetForegroundWindow($hwnd) | Out-Null
[Win32Force]::AttachThreadInput($curThread, $fgThread, $false) | Out-Null
Start-Sleep -Seconds 2

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$bitmap = New-Object System.Drawing.Bitmap $bounds.Width, $bounds.Height
$g = [System.Drawing.Graphics]::FromImage($bitmap)
$g.CopyFromScreen($bounds.Location, [System.Drawing.Point]::Empty, $bounds.Size)
$outPath = "$env:TEMP\hickory_verify_timer.png"
$bitmap.Save($outPath, [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bitmap.Dispose()
Write-Output "Saved: $outPath"
```

- [ ] **Step 3: Inspect the Timer tab screenshot**

Read `$env:TEMP\hickory_verify_timer.png` (the Read tool renders PNGs). Check against the approved mockup (`docs/superpowers/specs/2026-07-07-electric-violet-redesign-design.md`, "Dark theme" table, and the mockups under the design's linked brainstorming session): violet/pink gradient running-timer card, Unbounded numerals, pill Stop button, bottom nav with Timer/Reports/Sync, FAB visible.

- [ ] **Step 4: Switch tabs and re-screenshot**

In the running app, click the "Reports" tab (or drive it via the same window-automation approach), then re-run Step 2's capture (skip the `Start-Process`/`Start-Sleep 3` lines — the app is already running) to `$env:TEMP\hickory_verify_reports.png`. Confirm: FAB is gone, Reports content shows date-range chips and the project totals list, both restyled per tokens.

- [ ] **Step 5: Toggle OS theme and re-verify (light mode)**

Windows Settings → Personalization → Colors → switch "Choose your mode" to Light, relaunch `hickory.exe`, repeat Step 2's capture. Confirm the light-theme tokens from the spec (deeper violet `#7C3AED`/`#8B4FE0`→`#E0568F` gradient, `#FBF7FF` background) render correctly, matching the light-mode mockup. Switch the OS back to your preferred mode afterward.

- [ ] **Step 6: Clean up test processes**

```powershell
Stop-Process -Name hickory -Force -ErrorAction SilentlyContinue
```

- [ ] **Step 7: Final full-suite check**

```bash
flutter analyze
flutter test
```

Expected: both clean/green — this closes out the redesign.

---

## Self-Review Notes

- **Spec coverage:** color tokens (Task 1), typography (Task 2), component shapes/AppTheme (Task 3), gradient primary actions (Task 5), running-timer card + Start/Stop (Task 6), entry rows + FAB clearance fix (Task 7), Sync promoted to a screen (Task 8), Reports restyle (Task 9), bottom-nav structure with non-shifting labels (Task 10, via `NavigationDestinationLabelBehavior.alwaysShow` + matched icon/label pairs), light+dark parity (Task 11 verification). The "known pre-existing AppBar icon bug" from the spec is resolved structurally by Task 6/10 removing the old AppBar actions entirely.
- **Placeholder scan:** none found — every step has complete, real code or an exact command.
- **Type consistency:** `HickoryColors` fields/constructor (Task 1) match every later usage (`tokens.primaryGradient`, `tokens.timerNumeral`, etc. in Tasks 6/9); `GradientPillButton`/`GradientFab` constructors (Task 5) match their call sites in Task 6; `NavShell`'s `children`/`destinations`/`fabBuilder` (Task 10) match `AppShell`'s usage in the same task.
