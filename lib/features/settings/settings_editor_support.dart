import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';

/// Shared write plumbing for the settings editors. Each of them edits the
/// same singleton settings row through a read-modify-write cycle, so two
/// writes in flight at once could lose one of them.
///
/// The queue lives on the State that mixes this in, so it serialises the
/// writes of *one* editor, not of two editors at once. That is enough here
/// because each editor is its own sub-page and only one of them can be on
/// screen -- a genuinely concurrent pair of editors would need a queue
/// above the widget layer.
///
/// Writes are therefore queued, not dropped. Refusing the second write
/// would lose it outright, and losing a value the user entered is the
/// failure these two editors exist to avoid -- their fields commit on
/// focus loss precisely so that nothing typed goes missing.
///
/// A failed write must never be silent either: the editors keep showing
/// the user's own selection, so without a message the screen would go on
/// claiming a value the database never received. The same reasoning covers
/// rejected input, which is why [showMessage] is public.
mixin SettingsWriteGuard<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  /// The tail of the write queue; every new write is chained behind it.
  Future<void> _queue = Future<void>.value();
  int _inFlight = 0;

  /// True while at least one write started by [guardedWrite] has not
  /// settled yet. Used to disable the discrete controls (chips, dropdowns,
  /// the mode toggle) -- never the text fields, whose focus is what
  /// commits them.
  bool get busy => _inFlight > 0;

  /// The localized message shown when a write throws. Implemented per
  /// editor so the user is told which setting failed, not just "settings".
  String saveErrorMessage(AppLocalizations l10n);

  /// Queues [write] behind any write already running and reports whether
  /// it went through. Any failure is reported through [saveErrorMessage]
  /// and swallowed, so callers can fire this and forget it without an
  /// unhandled error escaping; a caller that remembers what it just saved
  /// awaits the `false` instead and puts its own state back.
  Future<bool> guardedWrite(Future<void> Function() write) {
    // Counted before the queue is joined, so the controls disable on the
    // gesture rather than when this write's turn comes round.
    _inFlight++;
    if (mounted) setState(() {});
    final result = _queue.then((_) => _runGuarded(write));
    // The tail must never carry an error: `then` would propagate it in
    // place of running the next write's body, jamming the queue for good.
    _queue = result.then((_) {}).catchError((Object _) {});
    return result;
  }

  Future<bool> _runGuarded(Future<void> Function() write) async {
    try {
      await write();
      return true;
    } catch (error) {
      debugPrint('${widget.runtimeType} failed to save: $error');
      if (mounted) showMessage(saveErrorMessage(AppLocalizations.of(context)));
      return false;
    } finally {
      _inFlight--;
      if (mounted) setState(() {});
    }
  }

  /// Shows [message] as a SnackBar, the house pattern for a settings write
  /// that could not be carried out.
  void showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}

/// Calls [onCommit] whenever [child] loses focus.
///
/// The work-time fields have no Save button, so a value typed into one is
/// only ever persisted by an explicit commit. On desktop -- this app's
/// primary platform -- Tab and a click elsewhere move focus without firing
/// `onSubmitted`, so a submit-only field discards what the user typed with
/// no feedback at all. Every field in these two editors is therefore
/// wrapped in this and commits on both paths.
class CommitOnFocusLoss extends StatelessWidget {
  const CommitOnFocusLoss({super.key, required this.onCommit, required this.child});

  final VoidCallback onCommit;
  final Widget child;

  @override
  Widget build(BuildContext context) => Focus(
        // An observer, not a stop of its own: a Focus node that can take
        // focus would sit in the traversal order in front of the field it
        // wraps, so Tab would need two presses per field. onFocusChange
        // still fires, because a node's hasFocus covers its descendants.
        canRequestFocus: false,
        skipTraversal: true,
        onFocusChange: (hasFocus) {
          if (!hasFocus) onCommit();
        },
        child: child,
      );
}
