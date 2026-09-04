import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';

/// Shared write plumbing for the work-time settings editors. Both of them
/// edit the same singleton settings row through a read-modify-write cycle,
/// so two writes in flight at once could lose one of them.
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

  /// Queues [write] behind any write already running. Any failure is
  /// reported through [saveErrorMessage] and swallowed, so callers can
  /// fire this and forget it without an unhandled error escaping.
  Future<void> guardedWrite(Future<void> Function() write) {
    _inFlight++;
    // setState rather than a bare increment: `busy` drives the enabled
    // state of the controls above.
    if (mounted) setState(() {});
    final done = _queue.then((_) => write()).catchError((Object error) {
      debugPrint('${widget.runtimeType} failed to save: $error');
      if (mounted) showMessage(saveErrorMessage(AppLocalizations.of(context)));
    }).whenComplete(() {
      _inFlight--;
      if (mounted) setState(() {});
    });
    _queue = done;
    return done;
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
        onFocusChange: (hasFocus) {
          if (!hasFocus) onCommit();
        },
        child: child,
      );
}
