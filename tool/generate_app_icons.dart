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
    throw StateError('Image.toByteData returned null -- PNG encoding failed');
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
