import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/app_settings_provider.dart';
import '../../core/di/sync_providers.dart';
import '../../core/format/date_format.dart';
import '../../core/format/duration_format.dart';
import '../../data/drift/database.dart';
import '../../data/drift/time_entry_extensions.dart';
import '../../l10n/app_localizations.dart';
import '../projects/projects_providers.dart';
import '../timer/timer_providers.dart';
import 'manual_entry_dialog.dart';

/// Reserves space so the shell's floating action button (56px + margin)
/// never overlaps the last entry — caught during design review, when an
/// early mockup had the FAB sitting on top of list content.
const _bottomPaddingForFab = 88.0;

class EntriesList extends ConsumerWidget {
  const EntriesList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final entriesAsync = ref.watch(allEntriesProvider);
    final projectsAsync = ref.watch(activeProjectsProvider);
    final settings = ref.watch(appSettingsProvider).value;
    final dateStyle = settings.dateStyle;
    final timeStyle = settings.timeStyle;

    return entriesAsync.when(
      data: (entries) {
        final finished = entries.where((e) => e.endAt != null).toList();
        if (finished.isEmpty) {
          return Center(child: Text(l10n.entriesEmpty));
        }
        final projectsById = {
          for (final p in projectsAsync.value ?? const <Project>[]) p.id: p,
        };
        return ListView.builder(
          padding: const EdgeInsets.only(bottom: _bottomPaddingForFab),
          itemCount: finished.length,
          itemBuilder: (context, index) {
            final entry = finished[index];
            final project = entry.projectId == null ? null : projectsById[entry.projectId];
            final duration = entry.workedDuration;
            return Dismissible(
              key: ValueKey(entry.id),
              direction: DismissDirection.endToStart,
              background: Container(
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(999),
                ),
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: const Icon(Icons.delete_outline),
              ),
              onDismissed: (_) {
                ref.read(syncedWritesProvider.future).then((w) => w.deleteEntry(entry.id));
              },
              child: Card(
                margin: const EdgeInsets.only(bottom: 8),
                shape: const StadiumBorder(),
                child: ListTile(
                  shape: const StadiumBorder(),
                  leading: CircleAvatar(
                    backgroundColor: project != null
                        ? Color(int.parse(project.colorHex.replaceFirst('#', '0xFF')))
                        : Colors.grey,
                    radius: 8,
                    child: const SizedBox.shrink(),
                  ),
                  title: Text(entry.description?.isNotEmpty == true
                      ? entry.description!
                      : (project?.name ?? l10n.entriesNoDescription)),
                  subtitle: Text(
                    '${project?.name ?? l10n.commonNoProject} · '
                    '${formatDate(entry.startAt, dateStyle, Localizations.localeOf(context).languageCode)} '
                    '${formatTime(entry.startAt, timeStyle)}',
                  ),
                  trailing: Text(formatDuration(duration)),
                  onTap: () => showManualEntryDialog(context, ref, existing: entry),
                ),
              ),
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => Center(child: Text(l10n.entriesError(error.toString()))),
    );
  }
}
