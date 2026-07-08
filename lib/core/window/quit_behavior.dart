import '../../data/drift/database.dart';
import '../../data/sync/synced_writes.dart';

/// Called right before the app actually quits (tray menu "Beenden" — see
/// WindowTrayController.onBeforeQuit). If the current open entry is
/// paused, finalize it now rather than leaving it paused forever with no
/// running app to resume it into. A running (non-paused) entry is left
/// untouched — that's expected to keep counting through an app restart.
Future<void> stopPausedEntryOnQuit(AppDatabase db, SyncedWrites writes) async {
  final running = await db.timeEntriesDao.getRunningEntry();
  if (running != null && running.pausedAt != null) {
    await writes.stopEntry(running.id);
  }
}
