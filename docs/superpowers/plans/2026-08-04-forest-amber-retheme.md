# Forest & Amber Re-theme Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace every "Electric Violet" (violet/pink) color token with the "Forest & Amber" (green/amber) values derived from the app icon, per the design spec.

**Architecture:** A pure value swap in two files (`HickoryColors`'s token constants, `AppTheme`'s three hardcoded hex values + seed color) — no structural, logic, or widget changes anywhere.

**Tech Stack:** Flutter `ThemeExtension`/`ThemeData`, no new dependencies.

## Global Constraints

- Only `lib/core/theme/hickory_colors.dart` and `lib/core/theme/app_theme.dart` change — every consuming widget reads tokens, never hardcodes a color.
- Exact values come from `docs/superpowers/specs/2026-08-04-forest-amber-retheme-design.md` Section 3 — don't improvise different hex values.
- No shape, typography, or navigation-structure changes.
- Commit messages follow Conventional Commits: `type(scope): imperative, lowercase, no period, <72 chars`.
- TDD: update the failing assertions in `hickory_colors_test.dart` first, watch them fail, implement, watch them pass.

---

## Task 1: Swap the color tokens

**Files:**
- Modify: `lib/core/theme/hickory_colors.dart`
- Modify: `lib/core/theme/app_theme.dart`
- Modify: `test/core/theme/hickory_colors_test.dart`

**Interfaces:**
- No signature changes anywhere — `HickoryColors`'s field names and `AppTheme`'s public API (`AppTheme.light`, `AppTheme.dark`) are unchanged; only the hex literals inside them change.

- [ ] **Step 1: Update the failing test assertions first**

Edit `test/core/theme/hickory_colors_test.dart` — replace both `test(...)` bodies with the new expected values:

```dart
  test('dark tokens match the spec', () {
    expect(HickoryColors.dark.primaryGradient, const [Color(0xFF5FBF8F), Color(0xFFE8A548)]);
    expect(HickoryColors.dark.surfaceGradient, const [Color(0xFF1B2E22), Color(0xFF20362A)]);
    expect(HickoryColors.dark.onPrimaryGradient, const Color(0xFF12241A));
    expect(HickoryColors.dark.timerNumeral, const Color(0xFF7DDBA8));
    expect(HickoryColors.dark.chipBackground, const Color(0xFF26402F));
    expect(HickoryColors.dark.chipText, const Color(0xFFF2BD7A));
    expect(HickoryColors.dark.navBackground, const Color(0xFF0F1912));
    expect(HickoryColors.dark.navBorder, const Color(0xFF1E3226));
    expect(HickoryColors.dark.navInactive, const Color(0xFF6B7A70));
    expect(HickoryColors.dark.navActiveLabel, const Color(0xFFD7EDDF));
    expect(HickoryColors.dark.navActiveIcon, const Color(0xFF7DDBA8));
  });

  test('light tokens match the spec', () {
    expect(HickoryColors.light.primaryGradient, const [Color(0xFF2F6B4F), Color(0xFFC97D1E)]);
    expect(HickoryColors.light.surfaceGradient, const [Color(0xFFE3F2E8), Color(0xFFFDEEDD)]);
    expect(HickoryColors.light.onPrimaryGradient, const Color(0xFFFFFFFF));
    expect(HickoryColors.light.timerNumeral, const Color(0xFF1E7A4F));
    expect(HickoryColors.light.chipBackground, const Color(0xFFFFFFFF));
    expect(HickoryColors.light.chipText, const Color(0xFF8A5810));
    expect(HickoryColors.light.navBackground, const Color(0xFFFFFFFF));
    expect(HickoryColors.light.navBorder, const Color(0xFFDCEEE0));
    expect(HickoryColors.light.navInactive, const Color(0xFF8FA89A));
    expect(HickoryColors.light.navActiveLabel, const Color(0xFF153D28));
    expect(HickoryColors.light.navActiveIcon, const Color(0xFF1E7A4F));
  });
```

(The third test, `'lerp interpolates toward the other extension...'`, doesn't hardcode
any hex value — leave it exactly as-is.)

- [ ] **Step 2: Run the test, verify it fails**

Run: `flutter test test/core/theme/hickory_colors_test.dart`
Expected: FAIL — both updated tests fail because `HickoryColors.dark`/`.light` still return the old Electric Violet values.

- [ ] **Step 3: Update `HickoryColors`**

Edit `lib/core/theme/hickory_colors.dart` — replace the `light` and `dark` static const definitions:

```dart
  static const light = HickoryColors(
    surfaceGradient: [Color(0xFFE3F2E8), Color(0xFFFDEEDD)],
    primaryGradient: [Color(0xFF2F6B4F), Color(0xFFC97D1E)],
    onPrimaryGradient: Color(0xFFFFFFFF),
    textMuted: Color(0x99152A1F),
    chipBackground: Color(0xFFFFFFFF),
    chipText: Color(0xFF8A5810),
    timerNumeral: Color(0xFF1E7A4F),
    navBackground: Color(0xFFFFFFFF),
    navBorder: Color(0xFFDCEEE0),
    navInactive: Color(0xFF8FA89A),
    navActiveLabel: Color(0xFF153D28),
    navActiveIcon: Color(0xFF1E7A4F),
  );

  static const dark = HickoryColors(
    surfaceGradient: [Color(0xFF1B2E22), Color(0xFF20362A)],
    primaryGradient: [Color(0xFF5FBF8F), Color(0xFFE8A548)],
    onPrimaryGradient: Color(0xFF12241A),
    textMuted: Color(0x99F3EFE2),
    chipBackground: Color(0xFF26402F),
    chipText: Color(0xFFF2BD7A),
    timerNumeral: Color(0xFF7DDBA8),
    navBackground: Color(0xFF0F1912),
    navBorder: Color(0xFF1E3226),
    navInactive: Color(0xFF6B7A70),
    navActiveLabel: Color(0xFFD7EDDF),
    navActiveIcon: Color(0xFF7DDBA8),
  );
```

`textMuted` keeps its existing `0x99` (60%) alpha prefix — only the RGB hex changes,
to the new theme's text-primary color (`#152A1F` light / `#F3EFE2` dark, per Section 3),
matching how the original `textMuted` was derived from its own theme's text-primary.

- [ ] **Step 4: Run the test, verify it passes**

Run: `flutter test test/core/theme/hickory_colors_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Update `AppTheme`'s remaining hardcoded values**

Edit `lib/core/theme/app_theme.dart`:

```dart
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF5FBF8F),
      brightness: brightness,
    ).copyWith(
```

```dart
    final surface = isDark ? const Color(0xFF0E1712) : const Color(0xFFF5FAF6);
    final cardSurface = isDark ? const Color(0xFF182620) : Colors.white;
    final onSurface = isDark ? const Color(0xFFF3EFE2) : const Color(0xFF152A1F);
```

(These three lines and the `seedColor` line are the only hex literals in this file
outside the doc comment — everything else already reads from `tokens`, which Step 3
already updated.)

- [ ] **Step 6: Run the full theme test suite**

Run: `flutter test test/core/theme/ test/core/widgets/gradient_buttons_test.dart`
Expected: PASS (all tests — `app_theme_test.dart` and `gradient_buttons_test.dart` were
never hardcoded to the old hex values, per the design spec's Section 5, so they should
already be green; this confirms it).

- [ ] **Step 7: Run static analysis**

Run: `flutter analyze lib/core/theme/`
Expected: no issues.

- [ ] **Step 8: Run the full project test suite**

Run: `flutter test`
Expected: all tests pass — this is a value-only change with no logic affected, so
nothing outside the theme tests should be able to fail, but confirm rather than assume.

- [ ] **Step 9: Commit**

```bash
git add lib/core/theme/hickory_colors.dart lib/core/theme/app_theme.dart test/core/theme/hickory_colors_test.dart
git commit -m "feat(theme): re-theme from Electric Violet to Forest & Amber"
```

---

## Final Verification

- [ ] `flutter test` passes in full.
- [ ] `flutter analyze` is clean.
- [ ] Manually confirm in a running build (or hot-reload of the already-running
      instance): Timer tab's running-timer card, Start/Pause button, project chips,
      and bottom nav all render in the green/amber palette in both light and dark
      mode, matching the approved mockup.
