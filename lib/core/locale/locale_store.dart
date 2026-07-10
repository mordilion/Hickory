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
