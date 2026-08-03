# Logo / App Icon Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Hickory's app-icon source images (`assets/icon/*.png`, `assets/tray_icon.png`) with the redesigned mark validated during brainstorming (leaf + stem + clock glyph, forest-green/amber palette), then regenerate every platform-specific icon from those sources.

**Architecture:** A single generation script (`tool/generate_app_icons.dart`) draws the mark with `dart:ui`'s `Canvas`/`PictureRecorder` and rasterizes it to PNG at each source file's required resolution — no new dependency, since this project has no SVG/raster tool installed (see the design spec, Section 6). `dart:ui` rasterization needs Flutter's engine bindings, which only `flutter_test` initializes outside a running app, so the script is a `flutter_test`-style file run via `flutter test`, not `dart run`. `flutter_launcher_icons` (already a dev dependency, already configured in `flutter_launcher_icons.yaml`) then regenerates every platform-specific icon file from the four `assets/icon/*.png` sources, exactly as it does today.

**Tech Stack:** `dart:ui` (Canvas/Picture/Image, via `flutter_test`'s engine bindings), `flutter_launcher_icons` (existing dev dependency).

## Global Constraints

- No new pub dependencies — `dart:ui`, `dart:io`, and `flutter_test` are already available.
- Exact colors and geometry come from `docs/superpowers/specs/2026-08-03-logo-redesign-design.md` (Sections 3–4) — don't improvise different values.
- `assets/tray_icon.png` gets the full colored composition (not a monochrome/template icon) per that spec.
- `flutter_launcher_icons.yaml` itself does not change — same four source file paths/roles as today.
- Commit messages follow Conventional Commits: `type(scope): imperative, lowercase, no period, <72 chars`.

---

## Task 1: Generate the redesigned icon assets and regenerate platform icons

**Files:**
- Create: `tool/generate_app_icons.dart`
- Generated (overwritten by the script, not hand-edited): `assets/icon/icon.png`, `assets/icon/icon_macos.png`, `assets/icon/icon_background.png`, `assets/icon/icon_foreground.png`, `assets/tray_icon.png`
- Generated (overwritten by `flutter_launcher_icons`, not hand-edited): `android/app/src/main/res/mipmap-*/ic_launcher.png`, `ios/Runner/Assets.xcassets/AppIcon.appiconset/*.png`, `macos/Runner/Assets.xcassets/AppIcon.appiconset/*.png`, `windows/runner/resources/app_icon.ico`

**Interfaces:**
- Produces: the five `assets/**` PNG files listed above, at their existing resolutions (1024×1024 for the four `assets/icon/*.png`, 64×64 for `assets/tray_icon.png`, matching what's already in the repo).

- [ ] **Step 1: Write the generation script**

Create `tool/generate_app_icons.dart`:

```dart
// Regenerates assets/icon/*.png and assets/tray_icon.png from the vector
// mark described in
// docs/superpowers/specs/2026-08-03-logo-redesign-design.md (Sections 3–4).
//
// Run via `flutter test tool/generate_app_icons.dart` — NOT `dart run`.
// dart:ui's Canvas/Picture rasterization needs Flutter engine bindings that
// only flutter_test sets up outside a running app; this project has no
// SVG/raster tool installed (see the design spec, Section 6), so this is
// the available option that needs no new dependency.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

const _gradientStart = ui.Color(0xFF2F6B4F);
const _gradientEnd = ui.Color(0xFF14342A);
const _markColor = ui.Color(0xFFF3EFE2);
const _clockCircleColor = ui.Color(0xFF14342A);
const _clockHandColor = ui.Color(0xFFE8A548);

/// All drawing happens in a fixed 120x120 logical space (matching the
/// validated brainstorming mockups); [_renderPng] scales the canvas to the
/// requested output resolution.
void _paintBackground(ui.Canvas canvas) {
  final rrect = ui.RRect.fromRectAndRadius(
    const ui.Rect.fromLTWH(0, 0, 120, 120),
    const ui.Radius.circular(26),
  );
  final shadowPath = ui.Path()..addRRect(rrect);
  canvas.drawShadow(shadowPath, const ui.Color(0xFF000000), 6, false);
  final paint = ui.Paint()
    ..shader = ui.Gradient.linear(
      const ui.Offset(0, 0),
      const ui.Offset(120, 120),
      [_gradientStart, _gradientEnd],
    );
  canvas.drawRRect(rrect, paint);
}

void _paintMark(ui.Canvas canvas) {
  final stemPaint = ui.Paint()
    ..color = _markColor
    ..style = ui.PaintingStyle.stroke
    ..strokeWidth = 4
    ..strokeCap = ui.StrokeCap.round;
  canvas.drawLine(const ui.Offset(60, 24), const ui.Offset(60, 18), stemPaint);

  final leafPath = ui.Path()
    ..moveTo(60, 24)
    ..cubicTo(80, 36, 86, 54, 78, 72)
    ..cubicTo(72, 86, 60, 94, 60, 94)
    ..cubicTo(60, 94, 48, 86, 42, 72)
    ..cubicTo(34, 54, 40, 36, 60, 24)
    ..close();
  canvas.drawPath(leafPath, ui.Paint()..color = _markColor);

  canvas.drawCircle(const ui.Offset(60, 60), 14, ui.Paint()..color = _clockCircleColor);

  final handPaint = ui.Paint()
    ..color = _clockHandColor
    ..style = ui.PaintingStyle.stroke
    ..strokeWidth = 3.5
    ..strokeCap = ui.StrokeCap.round;
  canvas.drawLine(const ui.Offset(60, 60), const ui.Offset(60, 50), handPaint);
  canvas.drawLine(const ui.Offset(60, 60), const ui.Offset(67, 60), handPaint);
}

Future<Uint8List> _renderPng({
  required bool background,
  required bool mark,
  required int size,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.scale(size / 120);
  if (background) _paintBackground(canvas);
  if (mark) _paintMark(canvas);
  final picture = recorder.endRecording();
  final image = await picture.toImage(size, size);
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  if (byteData == null) {
    throw StateError('Image.toByteData returned null — PNG encoding failed');
  }
  return byteData.buffer.asUint8List();
}

Future<void> _write(String path, Uint8List bytes) async {
  final file = File(path);
  await file.parent.create(recursive: true);
  await file.writeAsBytes(bytes);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('generate app icon assets', () async {
    final iconPng = await _renderPng(background: true, mark: true, size: 1024);
    await _write('assets/icon/icon.png', iconPng);
    await _write('assets/icon/icon_macos.png', iconPng);
    await _write(
      'assets/icon/icon_background.png',
      await _renderPng(background: true, mark: false, size: 1024),
    );
    await _write(
      'assets/icon/icon_foreground.png',
      await _renderPng(background: false, mark: true, size: 1024),
    );
    await _write(
      'assets/tray_icon.png',
      await _renderPng(background: true, mark: true, size: 64),
    );

    for (final path in [
      'assets/icon/icon.png',
      'assets/icon/icon_macos.png',
      'assets/icon/icon_background.png',
      'assets/icon/icon_foreground.png',
      'assets/tray_icon.png',
    ]) {
      expect(File(path).existsSync(), isTrue, reason: '$path should have been written');
      expect(File(path).lengthSync(), greaterThan(0), reason: '$path should not be empty');
    }
  });
}
```

- [ ] **Step 2: Run the script**

Run: `flutter test tool/generate_app_icons.dart`
Expected: PASS (1 test) — `assets/icon/icon.png`, `assets/icon/icon_macos.png`, `assets/icon/icon_background.png`, `assets/icon/icon_foreground.png`, and `assets/tray_icon.png` are all overwritten.

If this fails with an error about image encoding or a null rasterizer: this repo's own widget tests (e.g. `test/core/widgets/gradient_buttons_test.dart`) already pump and render real widgets via `flutter test` on this machine, which exercises the same underlying rasterizer this script needs — so first confirm `flutter test test/core/widgets/gradient_buttons_test.dart` still passes. If it does but this script still fails, the specific failure is in `Picture.toImage`/`toByteData` (not widget rendering); as a fallback, wrap the same drawing calls in a `CustomPainter`, render it inside a `testWidgets` body via `tester.runAsync(() => RepaintBoundary(...).toImage())` against a pumped widget instead of a bare `PictureRecorder`, which forces the rasterizer through the same path `matchesGoldenFile` uses.

- [ ] **Step 3: Visually confirm the regenerated source assets**

Open `assets/icon/icon.png`, `assets/icon/icon_background.png`, `assets/icon/icon_foreground.png`, and `assets/tray_icon.png` in an image viewer. Confirm:
- `icon.png`/`icon_macos.png`: forest-green-to-dark gradient rounded square, cream leaf-with-stem mark, dark circle with amber clock hands, soft drop shadow.
- `icon_background.png`: the same gradient, no mark.
- `icon_foreground.png`: only the mark, transparent background.
- `tray_icon.png`: same as `icon.png` but 64×64.

If anything looks wrong (wrong colors, missing shadow, mark misplaced), fix the corresponding constant or path in `tool/generate_app_icons.dart` and rerun Step 2 before continuing.

- [ ] **Step 4: Regenerate every platform-specific icon**

Run: `dart run flutter_launcher_icons`
Expected: succeeds; overwrites `android/app/src/main/res/mipmap-*/ic_launcher.png`, `ios/Runner/Assets.xcassets/AppIcon.appiconset/*.png`, `macos/Runner/Assets.xcassets/AppIcon.appiconset/*.png`, and `windows/runner/resources/app_icon.ico` from the four `assets/icon/*.png` files.

- [ ] **Step 5: Confirm the app still analyzes and builds**

Run: `flutter analyze`
Expected: no issues (the generation script lives under `tool/`, outside `lib/`, so it doesn't affect app analysis; this just confirms nothing else broke).

- [ ] **Step 6: Manually verify on a running build**

Run: `flutter run -d windows` (or `-d macos`)
Expected: the app window's title-bar/taskbar icon shows the new mark; on Windows, the system-tray icon (via `windows/runner/resources/app_icon.ico`, per `lib/core/window/window_tray_controller.dart`) also shows it, since `flutter_launcher_icons` regenerates that same `.ico` from `assets/icon/icon.png`. On macOS, additionally confirm the menu-bar tray icon (from `assets/tray_icon.png`) is legible at its actual small size.

- [ ] **Step 7: Commit**

```bash
git add tool/generate_app_icons.dart assets/icon assets/tray_icon.png android/app/src/main/res/mipmap-anydpi-v26 android/app/src/main/res/mipmap-hdpi android/app/src/main/res/mipmap-mdpi android/app/src/main/res/mipmap-xhdpi android/app/src/main/res/mipmap-xxhdpi android/app/src/main/res/mipmap-xxxhdpi ios/Runner/Assets.xcassets/AppIcon.appiconset macos/Runner/Assets.xcassets/AppIcon.appiconset windows/runner/resources/app_icon.ico
git commit -m "feat(icon): redesign the app icon and regenerate platform assets"
```

---

## Final Verification

- [ ] `flutter test tool/generate_app_icons.dart` passes.
- [ ] `flutter analyze` is clean.
- [ ] The app icon is visibly changed (new mark, new colors) on at least one platform you can run locally, per Step 6.
