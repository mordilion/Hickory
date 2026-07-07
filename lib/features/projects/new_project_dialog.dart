import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/sync_providers.dart';

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
    builder: (dialogContext) => AlertDialog(
      title: const Text('Neues Projekt'),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Name'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Abbrechen'),
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
          child: const Text('Erstellen'),
        ),
      ],
    ),
  );
}
