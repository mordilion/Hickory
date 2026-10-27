# Bugs and Fixes

Root-cause notes for bugs that reached a release. One entry per bug, newest first.

## Up to 1.5.0 crashed on Windows on every quit

- **Symptom:** quitting via the tray menu ("Beenden") killed `hickory.exe` with a Windows
  crash dialog instead of exiting. Same at the end of an in-app update, which quits
  through the same path. Diagnosed from three WER minidumps, all identical:
  `0xC0000005` reading `0x10` (the matching small dumps show `0xC000041D`,
  `STATUS_FATAL_USER_CALLBACK_EXCEPTION`, because the exception escaped a kernel
  callback).
- **Cause, in order:**
  1. `windowManager.destroy()` is only `PostQuitMessage(0)` on Windows
     (`window_manager/windows/window_manager.cpp`) — it does **not** destroy the window.
  2. `wWinMain`'s message loop ends with the top-level window still alive, and the stack
     object `FlutterWindow window` is destroyed.
  3. `~FlutterWindow` was empty, so the `flutter_controller_` member was deleted by the
     `unique_ptr`'s own destructor — which deletes **without nulling the member**.
  4. That destroys Flutter's child window; Windows delivers `WM_PARENTNOTIFY`
     (`wParam = WM_DESTROY`) to the still-alive parent **synchronously**.
  5. `FlutterWindow::MessageHandler` sees `flutter_controller_` as still non-null, calls
     `HandleTopLevelWindowProc`, and the engine dereferences its already-released view.
- **Fix:** `~FlutterWindow` assigns `nullptr` to `flutter_controller_` first
  (`unique_ptr::reset` nulls before deleting, so the re-entrant call sees no controller).
  The unguarded `flutter_controller_->` in the `WM_FONTCHANGE` case — the same latent
  null deref, never yet triggered — got a guard in the same change.
- **Why no test caught it:** the runner is C++ with no test harness, and the crash only
  happens on a real quit. CI builds `flutter build windows` but never runs the binary.
  Verification is manual: quit from the tray on Windows and confirm no crash dialog.
- **Worth knowing:** `destroy()` skips the native close sequence by design. The X button
  is intercepted (`setPreventClose(true)` → hide to tray), so `WM_CLOSE`/`WM_DESTROY`
  never run in Hickory at all — which is why the bug hit 100% of quits rather than
  intermittently. The runner fix covers every exit path; changing the Dart side to
  `close()` would only cover the call sites it touches.

## 1.4.0 bricked every upgrade from 1.3.x (endless spinner)

- **Symptom:** after updating 1.3.2 → 1.4.0 the app showed a spinner forever. No error
  reached the user: the database never opened, so every provider stayed pending.
- **Cause:** `onUpgrade` in `lib/data/drift/database.dart` ran
  `if (from < 11) createTable(absences)` and then
  `if (from < 12) addColumn(absences, halfDayPart)`. `Migrator.createTable` builds the
  table from its **current** definition, so the table already had `half_day_part` and the
  `ALTER TABLE` failed with `duplicate column name`.
- **Why no test caught it:** nothing exercised `onUpgrade` at all, and a developer's
  database is always *past* the create step when the column step is written — locally
  `from` was 11, so the two branches never ran together. Only a released version jumps
  8 → 13 in one pass.
- **Why it was worse than a crash:** the migration was not transactional. SQLite kept the
  tables and columns written before the error while `user_version` stayed at 8, so a
  merely corrected build would have failed again on the *next* step over work already
  done. Half-migrated files exist in the wild and have to heal themselves.
- **Fix (1.4.1):** all steps run inside one `BEGIN`/`COMMIT`/`ROLLBACK` via
  `customStatement`, and `_addColumnIfMissing` treats `duplicate column name` as done.
  `test/data/drift/migration_test.dart` seeds databases at schema 2, 8, 10, 11 and at the
  half-migrated 1.4.0 state, and asserts a failing step rolls everything back.
- **Rule that came out of it:** migrations are always transactional and always idempotent,
  and the upgrade path is tested from every released schema version. Written down in
  `.claude/rules/processes/dart-database-migrations.md`.
