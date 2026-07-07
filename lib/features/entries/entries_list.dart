import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/sync_providers.dart';
import '../../core/format/duration_format.dart';
import '../../data/drift/database.dart';
import '../projects/projects_providers.dart';
import '../timer/timer_providers.dart';
import 'manual_entry_dialog.dart';

class EntriesList extends ConsumerWidget {
  const EntriesList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entriesAsync = ref.watch(allEntriesProvider);
    final projectsAsync = ref.watch(activeProjectsProvider);

    return entriesAsync.when(
      data: (entries) {
        final finished = entries.where((e) => e.endAt != null).toList();
        if (finished.isEmpty) {
          return const Center(child: Text('Noch keine Einträge.'));
        }
        final projectsById = {
          for (final p in projectsAsync.value ?? const <Project>[]) p.id: p,
        };
        return ListView.builder(
          itemCount: finished.length,
          itemBuilder: (context, index) {
            final entry = finished[index];
            final project = entry.projectId == null ? null : projectsById[entry.projectId];
            final duration = entry.endAt!.difference(entry.startAt);
            return Dismissible(
              key: ValueKey(entry.id),
              direction: DismissDirection.endToStart,
              background: Container(
                color: Theme.of(context).colorScheme.errorContainer,
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: const Icon(Icons.delete_outline),
              ),
              onDismissed: (_) {
                ref.read(syncedWritesProvider.future).then((w) => w.deleteEntry(entry.id));
              },
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: project != null
                      ? Color(int.parse(project.colorHex.replaceFirst('#', '0xFF')))
                      : Colors.grey,
                  radius: 8,
                  child: const SizedBox.shrink(),
                ),
                title: Text(entry.description?.isNotEmpty == true
                    ? entry.description!
                    : (project?.name ?? 'Ohne Beschreibung')),
                subtitle: Text(
                  '${project?.name ?? 'Kein Projekt'} · ${entry.startAt.toLocal()}',
                ),
                trailing: Text(formatDuration(duration)),
                onTap: () => showManualEntryDialog(context, ref, existing: entry),
              ),
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => Center(child: Text('Fehler: $error')),
    );
  }
}
