# Hickory Color Re-theme — "Forest & Amber"

Date: 2026-08-04
Status: Approved for planning

## 1. Goal & Scope

Hickory's UI currently uses the "Electric Violet" palette (violet→pink gradients,
documented in `docs/superpowers/specs/2026-07-07-electric-violet-redesign-design.md`),
predating the app icon redesign to a forest-green/amber leaf-and-clock mark
(`docs/superpowers/specs/2026-08-03-logo-redesign-design.md`). The two no longer match.
This re-theme replaces the violet/pink hue family with a green/amber one derived from
the logo's actual colors, keeping every other design decision from Electric Violet
unchanged: pill shapes, 24px card radius, Unbounded/Manrope typography, the gradient
hero card, bottom navigation structure.

In scope: `lib/core/theme/hickory_colors.dart` (token values) and
`lib/core/theme/app_theme.dart` (the few hardcoded hex values outside the token
struct: seed color, background/surface/onSurface). No other file should need
changes — every consuming widget reads `HickoryColors`/`Theme.of(context)`, never a
hardcoded color (verified: only `app_theme.dart`, `hickory_colors.dart`,
`reports_screen.dart`, and `timer_screen.dart` reference these tokens at all, and the
latter two only read tokens, never define new hex literals).

Out of scope: shape language, typography, navigation structure, component structure —
none of that changes, matching the user's request to re-theme colors only.

## 2. Design Approach

Same structural pattern as Electric Violet (a two-hue gradient duo for primary
actions, deeper/more saturated tones in light mode vs. lighter/softer tones in dark
mode, hue-tinted near-black/near-white backgrounds) with green as the primary hue
(replacing violet) and amber as the secondary accent (replacing pink) — validated
visually against the visual companion mockup (running-timer card, nav bar, chips,
entry row, both themes) before finalizing values below.

Where possible, values are reused directly from the logo (not just hue-matched) to
reinforce the connection: the light-mode CTA gradient starts at the logo's own
`#2F6B4F`, and dark-mode primary body text uses the logo mark's cream `#F3EFE2`.

## 3. Color System

### Dark theme

| Token | Value | Use |
|---|---|---|
| Background | `#0E1712` | Screen background |
| Surface | `#182620` | Entry rows, default cards |
| Surface gradient (hero) | `#1B2E22` → `#20362A` | Running-timer card |
| Primary gradient | `#5FBF8F` → `#E8A548` | Start/Pause button, FAB |
| Primary solid | `#5FBF8F` | Icons, accents where a gradient doesn't fit |
| On-primary | `#12241A` | Text/icons on gradient fills |
| Text primary | `#F3EFE2` | Body text (the logo mark's own cream) |
| Text muted | `#F3EFE2` @ ~55–65% opacity | Secondary/meta text |
| Chip background | `#26402F` | Project chips |
| Chip text | `#F2BD7A` | Project chip label |
| Timer numeral | `#7DDBA8` | Hero elapsed-time display |
| Nav bar background | `#0F1912`, border `#1E3226` | Bottom nav |
| Nav inactive | `#6B7A70` | Inactive tab icon+label |
| Nav active | label `#D7EDDF`, icon `#7DDBA8` | Active tab |

### Light theme

| Token | Value | Use |
|---|---|---|
| Background | `#F5FAF6` | Screen background |
| Surface | `#FFFFFF` + shadow `0 1px 3px rgba(20,52,42,0.08)` | Entry rows, default cards |
| Surface gradient (hero) | `#E3F2E8` → `#FDEEDD` | Running-timer card |
| Primary gradient | `#2F6B4F` → `#C97D1E` | Start/Pause button, FAB |
| On-primary | `#FFFFFF` | Text/icons on gradient fills |
| Text primary | `#152A1F` | Body text |
| Chip background | `#FFFFFF` | Project chips |
| Chip text | `#8A5810` | Project chip label |
| Timer numeral | `#1E7A4F` | Hero elapsed-time display |
| Nav bar background | `#FFFFFF`, border `#DCEEE0` | Bottom nav |
| Nav inactive | `#8FA89A` | Inactive tab icon+label |
| Nav active | label `#153D28`, icon `#1E7A4F` | Active tab |

As with Electric Violet, light-mode tones are deliberately deeper/more saturated than
their dark-mode counterparts for contrast on a light background — same hue family,
tuned per-theme.

## 4. Implementation Notes

- `HickoryColors.light`/`.dark`: replace every hex literal per the tables above.
  Field names, structure, and every consuming call site stay identical — this is a
  value-only change to an existing `ThemeExtension`.
- `AppTheme._build`: update the three hardcoded values outside the token struct —
  `surface` (`#150F1E`/`#FBF7FF` → `#0E1712`/`#F5FAF6`), `cardSurface` (dark:
  `#1F1729` → `#182620`; light stays `Colors.white`), `onSurface` (`#F1ECF7`/`#241A30`
  → `#F3EFE2`/`#152A1F`) — and the `ColorScheme.fromSeed` seed color
  (`#B678FF` → `#5FBF8F`, the new dark-mode primary solid) so any unthemed Material
  component still lands in the green family rather than defaulting back to violet.
- No changes to `app_text_theme.dart` (typography untouched) or any shape/component
  theme data in `app_theme.dart` beyond the colors named above.

## 5. Testing

- `test/core/theme/hickory_colors_test.dart` pins every current token's exact hex
  value in two tests ("dark tokens match the spec" / "light tokens match the spec")
  — both need updating to the Section 3 values above; this is the primary place the
  re-theme's correctness is actually verified.
- `test/core/theme/app_theme_test.dart` asserts structure only (brightness, that
  `HickoryColors` is registered as a theme extension, pill/24px shapes, nav label
  behavior) — no hex values, unaffected by this change.
- `test/core/widgets/gradient_buttons_test.dart` passes its own arbitrary `Color`
  literals as `GradientPillButton` parameters to test the widget's rendering
  mechanism — these aren't `HickoryColors` values and don't need to change.
- `flutter analyze` clean, full `flutter test` suite green.
- Manual: build and launch on Windows, visually compare the Timer tab (light + dark)
  against the approved mockup.
