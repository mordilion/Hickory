// Regenerates assets/icon/*.png and assets/tray_icon.png from the vector
// mark described in
// docs/superpowers/specs/2026-08-03-logo-redesign-design.md (Sections 3-4).
//
// Run via `flutter test tool/generate_app_icons.dart` -- NOT `dart run`.
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

/// All drawing happens in a fixed logical space matching the validated
/// brainstorming mockups; [_renderPng] scales the canvas to the requested
/// output resolution.
const _canvasSize = 120.0;

/// Inset for the rounded-square icon body, so its drop shadow has room to
/// render within the canvas instead of being clipped at the edge (a
/// full-bleed rrect casts a shadow entirely outside the visible image).
const _iconPadding = 8.0;
const _iconCornerRadius = 22.0;

/// Android's adaptive icon system only guarantees the center ~66% (diameter)
/// of icon_foreground.png stays visible regardless of the launcher's mask
/// shape (circle, squircle, rounded square, teardrop) -- content outside
/// that safe circle can be cropped. [_paintMark] is scaled down by this
/// factor for the foreground-only render so the stem and leaf apex stay
/// inside it; the full composited icon (icon.png/icon_macos.png/tray_icon.png)
/// isn't masked by an OS-controlled shape, so it keeps the mark at full size.
const _foregroundSafeZoneScale = 0.82;

/// Rounded-square gradient body with a drop shadow, used for the complete
/// icon renders (icon.png/icon_macos.png/tray_icon.png) -- NOT for
/// icon_background.png, which must stay a full-bleed, unrounded gradient
/// since Android applies its own mask shape to that layer.
void _paintIconBody(ui.Canvas canvas) {
  final rrect = ui.RRect.fromRectAndRadius(
    const ui.Rect.fromLTWH(
      _iconPadding,
      _iconPadding,
      _canvasSize - _iconPadding * 2,
      _canvasSize - _iconPadding * 2,
    ),
    const ui.Radius.circular(_iconCornerRadius),
  );
  // A solid, fully-opaque offset shape instead of Canvas.drawShadow's soft
  // blurred shadow: the blurred version produces a wide band of
  // semi-transparent pixels which flutter_launcher_icons' iOS alpha-removal
  // step (remove_alpha_ios) blends incorrectly -- a visible bright-green
  // fringe around the whole icon, confirmed by generating and visually
  // inspecting the flattened iOS output. An opaque offset shape has no
  // meaningful alpha gradient for that step to mishandle, at the cost of a
  // crisp (not blurred) shadow edge instead of a soft one.
  final shadowRRect = rrect.shift(const ui.Offset(2, 3));
  canvas.drawRRect(shadowRRect, ui.Paint()..color = const ui.Color(0xFF0F241A));
  final paint = ui.Paint()
    ..shader = ui.Gradient.linear(
      const ui.Offset(_iconPadding, _iconPadding),
      const ui.Offset(_canvasSize - _iconPadding, _canvasSize - _iconPadding),
      [_gradientStart, _gradientEnd],
    );
  canvas.drawRRect(rrect, paint);
}

/// Full-bleed gradient with no rounding or shadow, for icon_background.png
/// (see [_paintIconBody]'s doc comment for why it must differ).
void _paintFullBleedGradient(ui.Canvas canvas) {
  final paint = ui.Paint()
    ..shader = ui.Gradient.linear(
      const ui.Offset(0, 0),
      const ui.Offset(_canvasSize, _canvasSize),
      [_gradientStart, _gradientEnd],
    );
  canvas.drawRect(const ui.Rect.fromLTWH(0, 0, _canvasSize, _canvasSize), paint);
}

void _paintMark(ui.Canvas canvas, {double scale = 1}) {
  canvas.save();
  canvas.translate(60, 60);
  canvas.scale(scale);
  canvas.translate(-60, -60);

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

  canvas.restore();
}

enum _Composition {
  /// icon.png / icon_macos.png / tray_icon.png: rounded body + shadow + mark
  /// at full scale.
  fullIcon,

  /// icon_background.png: full-bleed gradient only, no mark.
  backgroundOnly,

  /// icon_foreground.png: mark only (safe-zone-scaled), transparent
  /// background, for Android's adaptive icon foreground layer.
  foregroundOnly,
}

Future<Uint8List> _renderPng({required _Composition composition, required int size}) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.scale(size / _canvasSize);
  switch (composition) {
    case _Composition.fullIcon:
      _paintIconBody(canvas);
      _paintMark(canvas);
      break;
    case _Composition.backgroundOnly:
      _paintFullBleedGradient(canvas);
      break;
    case _Composition.foregroundOnly:
      _paintMark(canvas, scale: _foregroundSafeZoneScale);
      break;
  }
  final picture = recorder.endRecording();
  final image = await picture.toImage(size, size);
  try {
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) {
      throw StateError('Image.toByteData returned null -- PNG encoding failed');
    }
    return byteData.buffer.asUint8List();
  } finally {
    image.dispose();
    picture.dispose();
  }
}

Future<void> _write(String path, Uint8List bytes) async {
  final file = File(path);
  await file.parent.create(recursive: true);
  await file.writeAsBytes(bytes);
}

const _mainIconSize = 1024;
const _trayIconSize = 64;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('generate app icon assets', () async {
    final iconPng = await _renderPng(
      composition: _Composition.fullIcon,
      size: _mainIconSize,
    );
    await _write('assets/icon/icon.png', iconPng);
    await _write('assets/icon/icon_macos.png', iconPng);
    await _write(
      'assets/icon/icon_background.png',
      await _renderPng(composition: _Composition.backgroundOnly, size: _mainIconSize),
    );
    await _write(
      'assets/icon/icon_foreground.png',
      await _renderPng(composition: _Composition.foregroundOnly, size: _mainIconSize),
    );
    await _write(
      'assets/tray_icon.png',
      await _renderPng(composition: _Composition.fullIcon, size: _trayIconSize),
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
