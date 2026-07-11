import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/sync_providers.dart';
import '../../l10n/app_localizations.dart';

const projectColorPalette = [
  '#5B8DEF',
  '#EF5B5B',
  '#5BEF8D',
  '#EFC75B',
  '#B85BEF',
  '#5BD3EF',
];

Future<void> showNewProjectDialog(BuildContext context, WidgetRef ref) {
  final controller = TextEditingController();
  return showDialog<void>(
    context: context,
    builder: (dialogContext) {
      final l10n = AppLocalizations.of(dialogContext);
      return AlertDialog(
        title: Text(l10n.projectsNewProjectTitle),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: l10n.projectsNameLabel),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isEmpty) return;
              final colorHex = projectColorPalette[name.hashCode % projectColorPalette.length];
              final writes = await ref.read(syncedWritesProvider.future);
              await writes.createProject(name: name, colorHex: colorHex);
              if (dialogContext.mounted) Navigator.of(dialogContext).pop();
            },
            child: Text(l10n.projectsCreateButton),
          ),
        ],
      );
    },
  );
}
