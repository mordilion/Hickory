import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Rect;

import 'package:path/path.dart' as p;

/// Persists the user's chosen window size and position across app restarts.
/// Device-local only (deliberately not synced -- window bounds are a UI
/// preference for this machine, not something that should propagate to the
/// user's other devices, same reasoning as BackgroundNoticeStore). Takes the
/// support directory as a constructor parameter (rather than resolving it
/// internally via path_provider) so it's trivially testable against a temp
/// directory -- the real caller passes `await getApplicationSupportDirectory()`.
class WindowBoundsStore {
  WindowBoundsStore({required this.supportDirectory});

  final Directory supportDirectory;

  File get _boundsFile => File(p.join(supportDirectory.path, 'window_bounds.json'));

  /// Returns null if no bounds have been saved yet, or the file can't be
  /// read/parsed (e.g. a partial write) -- callers fall back to defaults.
  Future<Rect?> read() async {
    try {
      final content = await _boundsFile.readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;
      return Rect.fromLTWH(
        (json['x'] as num).toDouble(),
        (json['y'] as num).toDouble(),
        (json['width'] as num).toDouble(),
        (json['height'] as num).toDouble(),
      );
    } on Object {
      return null;
    }
  }

  Future<void> write(Rect bounds) async {
    await _boundsFile.create(recursive: true);
    await _boundsFile.writeAsString(
      jsonEncode({
        'x': bounds.left,
        'y': bounds.top,
        'width': bounds.width,
        'height': bounds.height,
      }),
    );
  }
}
