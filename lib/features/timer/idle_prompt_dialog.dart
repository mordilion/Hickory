import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// Asks whether the idle stretch should be trimmed off the running entry.
/// Returns true if the user wants it trimmed, false to keep the time as-is.
Future<bool> showIdlePromptDialog(BuildContext context, Duration idleDuration) async {
  final minutes = idleDuration.inMinutes;
  final l10n = AppLocalizations.of(context);
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      title: Text(l10n.timerIdleTitle),
      content: Text(l10n.timerIdleMessage(minutes)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.timerIdleKeepTime),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.timerIdleTrimTime),
        ),
      ],
    ),
  );
  return result ?? false;
}
