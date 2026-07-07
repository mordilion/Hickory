# Hickory Visual Redesign — "Electric Violet"

## Context

Hickory's UI was pure Material3 defaults (a generic blue `colorSchemeSeed`, stock component shapes, no custom typography) — functional but with no intentional visual identity. The user asked for a full visual redesign with a bold, modern, energetic personality, explicitly stepping away from M6 (mobile folder access) to do this first.

The direction below was validated interactively through the brainstorming visual companion: three rounds of mockups (color/type direction → shape language → navigation structure → light/dark pairing), with the user picking a direction at each step and one round of concrete feedback (nav-tab baseline alignment) that's folded in below.

## Design decisions

1. **Mood**: Bold & energetic — not minimal/calm, not premium/cold, not warm/mascot-driven.
2. **No mascot or nursery-rhyme reference** ("Hickory Dickory Dock") — the visual identity is abstract and self-standing, not illustrative.
3. **Light and dark themes are equal-priority**, both fully designed now, not one derived as an afterthought.
4. **Color — "Electric Violet"**: violet primary + pink secondary as a gradient duo, dark aubergine surfaces in dark mode, soft violet-tinted white surfaces in light mode.
5. **Typography**: **Unbounded** for display moments (app title, timer numerals, section headlines) + **Manrope** for everything else (body text, list rows, buttons, nav labels, form fields).
6. **Shape language — "Pill & Playful"**: pill-shaped buttons/chips/list rows, 20–24px rounded cards, gradient (violet→pink) fill on primary actions.
7. **Navigation**: bottom navigation bar with 3 tabs (Timer / Reports / Sync), replacing the current AppBar icon buttons and the Sync dialog. Every tab uses the same icon+label layout in both active and inactive states — confirmed with the user after an initial mockup shifted the label position when a tab became active.

## Color system

### Dark theme

| Token | Value | Use |
|---|---|---|
| Background | `#150F1E` | Screen background |
| Surface | `#1F1729` | Entry rows, default cards |
| Surface gradient (hero) | `#241A30` → `#2E1B38` | Running-timer card |
| Primary gradient | `#B678FF` → `#FF6FA9` | Start/Stop button, FAB |
| Primary solid | `#B678FF` | Icons, accents where a gradient doesn't fit |
| On-primary | `#160A22` | Text/icons on gradient fills |
| Text primary | `#F1ECF7` | Body text |
| Text muted | `#F1ECF7` @ ~55–65% opacity | Secondary/meta text |
| Chip background | `#3A2A4A` | Project chips |
| Chip text | `#FF9ED6` | Project chip label |
| Timer numeral | `#C89BFF` | Hero elapsed-time display |
| Nav bar background | `#1A1420`, border `#2A2033` | Bottom nav |
| Nav inactive | `#6E6478` | Inactive tab icon+label |
| Nav active | label `#E4D5FF`, icon `#C89BFF` | Active tab |

### Light theme

| Token | Value | Use |
|---|---|---|
| Background | `#FBF7FF` | Screen background |
| Surface | `#FFFFFF` + shadow `0 1px 3px rgba(60,20,90,0.08)` | Entry rows, default cards |
| Surface gradient (hero) | `#F1E4FF` → `#FDE6F1` | Running-timer card |
| Primary gradient | `#8B4FE0` → `#E0568F` | Start/Stop button, FAB |
| On-primary | `#FFFFFF` | Text/icons on gradient fills |
| Text primary | `#241A30` | Body text |
| Chip background | `#FFFFFF` | Project chips |
| Chip text | `#C0287A` | Project chip label |
| Timer numeral | `#7C3AED` | Hero elapsed-time display |
| Nav bar background | `#FFFFFF`, border `#EEE3FA` | Bottom nav |
| Nav inactive | `#A99BB8` | Inactive tab icon+label |
| Nav active | label `#4C1D95`, icon `#7C3AED` | Active tab |

Light-mode tones are deliberately deeper/more saturated than their dark-mode counterparts (e.g. primary text-use violet `#7C3AED` vs. decorative `#B678FF`) to keep contrast on a light background — same hue family, tuned per-theme rather than one color reused verbatim in both.

## Typography

- **Display** (Unbounded, weights 500/700/900): app title/logo, the timer's elapsed-time numerals, screen headlines. Reserved for a small number of large, high-impact moments — not used for small text (nav labels, chip text, list rows), since Unbounded's character loses legibility at small sizes.
- **Body/UI** (Manrope, weights 400/500/600/700): everything else — body text, list rows, form fields, chip labels, nav labels, and button labels (including the primary Start/Stop button — bold Manrope, not Unbounded).
- Implementation via the `google_fonts` package. Flutter's `TextTheme` doesn't support mixed families per role automatically, so build it explicitly: `displayLarge`/`headlineLarge`/etc. get `GoogleFonts.unbounded(textStyle: ...)`, `bodyLarge`/`labelLarge`/etc. get `GoogleFonts.manrope(textStyle: ...)`. The timer numeral itself is a bespoke `TextStyle` (not pulled from the theme) since nothing else needs its exact size/weight/tabular-figure treatment.

## Shape & component language

- Corner radius scale: **24px** for cards/containers, **999px (pill)** for buttons, chips, and list rows.
- Primary actions (Start/Stop, FAB): gradient fill (violet → pink per theme), pill shape, bold Manrope label, no elevation shadow in dark mode (glow via the gradient itself is enough) / soft shadow in light mode.
- Secondary buttons: solid surface color, pill shape, no gradient.
- Time-entry rows: each entry is its own pill-shaped row (not a divided list) with internal padding — replaces the current `ListTile`-in-`ListView` look.
- The running-timer card uses the diagonal surface gradient (not the primary gradient) as its background, with the primary gradient reserved for the Stop button inside it.
- **Bottom padding requirement**: the entries list must reserve bottom padding ≥ FAB height + margin (~88px) so the floating action button never visually overlaps the last entry — caught and fixed during mockup review (an early nav mockup had the FAB overlapping list content).

## Navigation structure

Replaces today's single-screen-with-AppBar-icons layout with a persistent bottom navigation bar, three destinations: **Timer**, **Reports**, **Sync**.

- Every tab renders the *same* icon+label structure regardless of active state — only color (and icon tint) changes. No conditional element (e.g. a dot) that would shift the label's vertical position between states; this was an explicit fix requested after the first navigation mockup didn't keep labels aligned across states.
- Implementation: a shell widget hosts Flutter's Material 3 `NavigationBar` and switches between the three screens' *body* content (each screen stops owning its own `Scaffold`/`AppBar`).
- The FAB (manual entry) is shell-level UI tied to the Timer tab only — visible when Timer is active, hidden otherwise.
- Sync moves from a modal dialog to a full tab/screen, since it's now a primary navigation destination rather than a secondary action.
- Nav icons in the mockups are emoji placeholders (⏱ 📊 ⟳); the implementation uses real Material icons — `Icons.timer_outlined`/`Icons.timer` (Timer), `Icons.bar_chart_outlined`/`Icons.bar_chart` (Reports), `Icons.sync_outlined`/`Icons.sync` (Sync), outlined for inactive and filled for active, consistent with the "same structure, only color/weight changes" rule above.

## Screens affected

- **`lib/core/theme/`** *(new)* — color tokens (light + dark `ColorScheme`, hand-authored rather than `colorSchemeSeed` since Material3's algorithmic seed generation desaturates toward accessible-but-muted tones and would lose the vividness validated in the mockups), a `TextTheme` builder mixing Unbounded/Manrope, and component theme data (pill `ButtonStyle`s, `CardThemeData`, `NavigationBarThemeData`) with the radius/shape tokens above.
- **`lib/app.dart`** — rebuilt `ThemeData`/`darkTheme` from the new theme package instead of `colorSchemeSeed`.
- **`lib/features/shell/`** *(new)* — the `NavigationBar` shell hosting Timer/Reports/Sync as tabs, owning the single `Scaffold`, `AppBar`, and the Timer-only FAB.
- **`lib/features/timer/timer_screen.dart`** — drops its own `Scaffold`/`AppBar`; becomes body content only. Running-timer card and Stop button restyled per the shape/color system; start-card restyled to match.
- **`lib/features/entries/entries_list.dart`** — rows restyled as pills; bottom padding added for the FAB (see above).
- **`lib/features/reports/reports_screen.dart`** — drops its own `Scaffold`/`AppBar`; chips and list restyled to match.
- **`lib/features/sync/`** — `sync_settings_dialog.dart`'s content becomes a full screen (new `sync_screen.dart`) instead of a dialog, matching the new Sync tab. The folder-picking/manual-sync logic already in the dialog carries over unchanged.
- Manual entry dialog, new-project dialog, idle-prompt dialog: visual restyle only (pill buttons, 24px dialog corners, new color tokens) — structure and logic unchanged.

## Known pre-existing issue, resolved incidentally

While testing the current build, the AppBar's Reports/Sync icon buttons were found not rendering in the live app (confirmed via a real window screenshot, not a capture artifact — worth a root-cause look if it recurs elsewhere). This redesign removes the AppBar actions entirely in favor of the bottom nav, so the specific symptom becomes moot; the new nav icons should simply be verified to render correctly where the old ones didn't.

## Out of scope

- No changes to the data model, sync engine, drift schema, or business logic — this is a presentation-layer redesign only.
- No app icon / installer branding changes (belongs with M7 packaging).
- No mobile-specific layout work (M6) — this targets the desktop window, though the bottom-nav structure was chosen partly because it translates reasonably to mobile later.

## Verification

- `flutter analyze` clean; `flutter test` green — existing tests shouldn't need behavior changes since DAOs/providers/business logic are untouched.
- Manual: build and launch on Windows, screenshot the Timer and Reports tabs in both light and dark mode, compare against the approved mockups (`.superpowers/brainstorm/294-1783448401/content/`) for the color/type/shape/nav decisions above.
