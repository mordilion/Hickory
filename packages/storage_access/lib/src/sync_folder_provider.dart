import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:watcher/watcher.dart';

/// Desktop-only folder access for Hickory's sync directory.
///
/// The app never talks to a cloud provider's API directly — the user picks
/// any local directory (typically one already synced by iCloud Drive,
/// Google Drive, Dropbox, or similar), and this class only ever does plain
/// filesystem operations against it. On desktop that's trivial: the OS's
/// native directory picker plus a filesystem watcher. Mobile can't do
/// either the same way (no live watcher, and folder access goes through
/// SAF/UIDocumentPicker instead) — that's a separate implementation added
/// in a later milestone.
class SyncFolderProvider {
  /// Opens the native "choose a folder" dialog. Returns null if the user
  /// cancelled.
  Future<String?> pickFolder() {
    return FilePicker.getDirectoryPath(dialogTitle: 'Sync-Ordner auswählen');
  }

  Future<void> persistFolderPath(String path) async {
    final file = await _configFile();
    await file.writeAsString(path);
  }

  Future<void> clearPersistedFolder() async {
    final file = await _configFile();
    if (await file.exists()) await file.delete();
  }

  /// Returns the last persisted folder path, or null if none was ever set
  /// or the folder no longer exists on disk.
  Future<String?> restorePersistedFolder() async {
    final file = await _configFile();
    if (!await file.exists()) return null;
    final path = (await file.readAsString()).trim();
    if (path.isEmpty) return null;
    return Directory(path).existsSync() ? path : null;
  }

  /// Emits once, debounced by [debounce], after any file under [path]
  /// changes. Meant to trigger a sync pass — callers should still offer a
  /// manual "sync now" action too, since filesystem watchers can miss
  /// events under heavy I/O.
  Stream<void> watch(String path, {Duration debounce = const Duration(milliseconds: 750)}) {
    final controller = StreamController<void>();
    Timer? debounceTimer;
    final subscription = DirectoryWatcher(path).events.listen((_) {
      debounceTimer?.cancel();
      debounceTimer = Timer(debounce, () {
        if (!controller.isClosed) controller.add(null);
      });
    });
    controller.onCancel = () {
      debounceTimer?.cancel();
      unawaited(subscription.cancel());
    };
    return controller.stream;
  }

  Future<File> _configFile() async {
    final dir = await getApplicationSupportDirectory();
    return File(p.join(dir.path, 'sync_folder_path.txt'));
  }
}
