import 'dart:io';

import 'package:path/path.dart' as p;

/// Tracks whether the user has already been shown the one-time "Hickory
/// keeps running in the background" message after their first
/// minimize/close-to-tray. Takes the support directory as a constructor
/// parameter (rather than resolving it internally via path_provider) so
/// it's trivially testable against a temp directory — the real caller
/// passes `await getApplicationSupportDirectory()`.
class BackgroundNoticeStore {
  BackgroundNoticeStore({required this.supportDirectory});

  final Directory supportDirectory;

  File get _flagFile => File(p.join(supportDirectory.path, 'background_notice_shown'));

  Future<bool> hasBeenShown() => _flagFile.exists();

  Future<void> markShown() async {
    await _flagFile.create(recursive: true);
  }
}
