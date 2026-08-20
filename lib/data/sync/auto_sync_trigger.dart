import 'dart:async';

/// Coalesces many "something changed" signals into a single background run
/// of an idempotent sync, and guarantees two runs never overlap.
///
/// The window opens with the *first* [schedule] and is not extended by the
/// ones that follow, so continuous editing cannot starve the run: a change
/// is always reconciled within [debounce] of the first trigger that saw it.
/// A trigger raised while a run is in flight is remembered and honoured
/// after it finishes, because that run may already have read its data
/// before the change landed.
///
/// Failures are swallowed by design: this drives *background* runs, which
/// must never raise UI. A sync service records its own per-row errors (see
/// `lastError`), and the manual button on the Sync screen is what surfaces
/// an outcome to the user.
class AutoSyncTrigger {
  // The callback is a positional initializing formal because a named one
  // cannot be private, and a public field would let callers bypass the
  // coalescing this class exists for.
  AutoSyncTrigger(this._run, {this.debounce = const Duration(seconds: 3)});

  final Future<void> Function() _run;
  final Duration debounce;

  Timer? _timer;
  bool _isRunning = false;
  // A trigger that arrived mid-run, to be honoured once it finishes.
  bool _isMissedTrigger = false;
  bool _isDisposed = false;

  /// Requests a run. Cheap and safe to call on every write.
  void schedule() {
    if (_isDisposed) return;
    if (_isRunning) {
      _isMissedTrigger = true;
      return;
    }
    // A window is already open — let it close on its own schedule.
    if (_timer != null) return;
    _timer = Timer(debounce, _runNow);
  }

  Future<void> _runNow() async {
    _timer = null;
    if (_isDisposed) return;
    _isRunning = true;
    try {
      await _run();
    } catch (_) {
      // Deliberately silent — see the class doc.
    } finally {
      _isRunning = false;
      if (_isMissedTrigger) {
        _isMissedTrigger = false;
        schedule();
      }
    }
  }

  /// Cancels a pending run and makes every later [schedule] a no-op. A run
  /// already in flight is not interrupted; its result is simply ignored.
  void dispose() {
    _isDisposed = true;
    _timer?.cancel();
    _timer = null;
  }
}
