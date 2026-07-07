import 'package:flutter/material.dart';

/// Asks whether the idle stretch should be trimmed off the running entry.
/// Returns true if the user wants it trimmed, false to keep the time as-is.
Future<bool> showIdlePromptDialog(BuildContext context, Duration idleDuration) async {
  final minutes = idleDuration.inMinutes;
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      title: const Text('Inaktiv erkannt'),
      content: Text(
        'Du warst seit $minutes Minuten inaktiv. Soll diese Zeit vom '
        'laufenden Eintrag abgezogen werden?',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Zeit behalten'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Inaktive Zeit abziehen'),
        ),
      ],
    ),
  );
  return result ?? false;
}
