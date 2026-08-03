# Logo / App Icon Redesign — Design

Date: 2026-08-03
Status: Approved for planning

## 1. Goal & Scope

Redesign Hickory's app icon (`assets/icon/*.png`, `assets/tray_icon.png`) to fix three
problems with the current mark: it reads as an eye/leaf/almond depending on the
viewer rather than clearly evoking "Hickory" or "time tracking," the purple→pink
gradient feels like a generic wellness-app palette, and the overall result doesn't
feel intentional/polished.

In scope: the icon source images consumed by `flutter_launcher_icons.yaml`
(`icon.png`, `icon_background.png`, `icon_foreground.png`, `icon_macos.png`) and the
standalone `assets/tray_icon.png`.

Explicitly out of scope: the in-app color theme (`HickoryColors`,
`docs/superpowers/specs/2026-07-07-electric-violet-redesign-design.md`) — the app's
UI gradient/palette is not part of this change, only the icon. If the two are ever
meant to match, that's a separate follow-up decision, not assumed here.

## 2. Concept — Direction & Iteration

Explored four symbolic directions (hickory nut, pure stopwatch, refined leaf+clock
hybrid, abstract "H" monogram) and four color treatments on a shared visual-companion
session; **refined leaf+clock hybrid** in a **forest green + amber accent** palette was
selected, then iterated twice more (adding a stem, verifying at real tray-icon scale)
based on direct feedback that it still read clearly and didn't restore the eye/almond
ambiguity.

## 3. Final Mark

A solid (non-outline) leaf silhouette with a short stem at the top, containing a small
dark circle near its center with two short clock-hand strokes — the leaf establishes
"Hickory" (the tree), the clock hands establish "time tracking," and both are legible
as distinct elements rather than merged into one ambiguous shape (the current icon's
problem: a single thin vertical line inside a leaf/eye outline).

Composition (1024×1024 canvas, scaled proportionally to `120×120` in the mockups
below):
- **Leaf body**: bezier silhouette, apex at top-center, tapering to a point at the
  bottom — same general leaf proportions validated in the mockups, redrawn at full
  resolution during implementation rather than traced from the 120px preview.
- **Stem**: short straight line, same fill color as the leaf, extending up from the
  leaf's top apex.
- **Clock glyph**: a filled circle roughly 40% of the leaf's height (diameter 28
  units on the 120-unit mockup grid, leaf height 70 units), centered essentially at
  the leaf's vertical middle, containing two short accent-colored strokes (hour/minute
  hands) meeting at the circle's center at a fixed 90° angle — a 12-o'clock and a
  3-o'clock hand, not the "~45°" originally sketched in an earlier iteration of this
  spec, corrected here to match the geometry actually validated during brainstorming
  and implemented in `tool/generate_app_icons.dart` (not live/animated — this is a
  static mark).

## 4. Colors

| Role | Hex | Used for |
|---|---|---|
| Background gradient start | `#2F6B4F` | Top-left of icon background gradient |
| Background gradient end | `#14342A` | Bottom-right of icon background gradient |
| Mark (leaf + stem) | `#F3EFE2` | Leaf silhouette and stem — warm off-white, not pure white, to avoid a stark/clinical look |
| Clock circle fill | `#14342A` | Same as gradient's dark end, so the circle reads as a "cutout" into the dark tone |
| Clock hands | `#E8A548` | Amber accent — the only non-green/off-white color in the mark, drawing the eye to the time element |

Rationale: green ties directly to "Hickory" the tree without being a literal/cartoon
leaf-clipart color; amber (wood/nut tone) as a single accent avoids a second full
gradient competing for attention, and gives the mark better legibility at small sizes
since the accent color is concentrated in one small area rather than spread across a
gradient.

## 5. Per-Asset Treatment

| File | Treatment |
|---|---|
| `icon.png` (main/Windows source) | Full composition: rounded-square background gradient (Section 4) + mark, with a shadow behind the rounded-square body. Implemented as a solid, fully-opaque offset shape (not a blurred `Canvas.drawShadow`) — a soft blurred shadow produces a wide semi-transparent edge that `flutter_launcher_icons`' iOS alpha-flattening (`remove_alpha_ios`) blends incorrectly into a visible colored fringe around the whole icon, discovered and fixed during implementation. |
| `icon_macos.png` | Same composition; macOS's own rendering pipeline expects the pre-rounded/shadowed form, consistent with the current file. |
| `icon_background.png` | Background gradient only, full-bleed, no mark — same role as today (Android adaptive-icon background layer). |
| `icon_foreground.png` | Mark only (leaf + stem + clock glyph, transparent background) — same role as today (Android adaptive-icon foreground layer, allows OS-driven parallax/masking). Scaled to ~82% of the full-size mark so the stem stays inside Android's guaranteed-visible center-66%-diameter safe zone regardless of the launcher's mask shape; `icon.png`/`icon_macos.png`/`tray_icon.png` are not OS-masked, so they keep the mark at full size. |
| `tray_icon.png` | Small-scale render of the full colored composition (background + mark), **not** a monochrome/template icon — chosen over the OS-auto-recolor convention to keep the brand's amber/green identifiable even at menu-bar/taskbar size. Verified legible at 18px during the design session. |

## 6. Implementation Note (for the plan)

No SVG/raster tooling (ImageMagick, Inkscape, rsvg-convert, cairosvg) is available in
this environment. The plan should render the final artwork using the project's
existing toolchain — a small Dart script using `dart:ui`'s `PictureRecorder` /
`Canvas` (already a transitive dependency via Flutter, no new package) to draw the
mark programmatically and export each required PNG at its target resolution — rather
than introducing a new external dependency or asking the user to run a design tool
manually. `flutter_launcher_icons` then regenerates all platform-specific sizes from
the four source files as it already does today (`flutter pub run
flutter_launcher_icons`).

## 7. Testing / Verification

- Visual check of generated platform assets (Android adaptive icon preview, iOS/macOS
  app icon, Windows .ico, tray icon in both light and dark OS themes) after running
  `flutter_launcher_icons` — this is an asset-generation change, not logic, so no unit
  tests apply.
- Confirm `flutter_launcher_icons.yaml` needs no changes (same four file paths/roles,
  only pixel content changes).
