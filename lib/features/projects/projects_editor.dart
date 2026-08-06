import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/sync_providers.dart';
import '../../data/drift/database.dart';
import '../../data/sync/synced_writes.dart' show ProjectHasTimeEntriesException;
import '../../l10n/app_localizations.dart';
import 'project_form_dialog.dart';
import 'projects_providers.dart';

/// Settings-screen project manager: edit/archive active projects, reactivate
/// archived ones. Lives in the `projects` feature (not `settings/`) since it
/// operates on the cross-cutting Project entity also used by Timer --
/// settings_screen.dart composes it the same way app_shell.dart composes
/// screens from other features. See
/// docs/superpowers/specs/2026-08-04-project-editing-design.md.
class ProjectsEditor extends ConsumerStatefulWidget {
  const ProjectsEditor({super.key});

  @override
  ConsumerState<ProjectsEditor> createState() => _ProjectsEditorState();
}

class _ProjectsEditorState extends ConsumerState<ProjectsEditor> {
  /// True while an archive/reactivate/delete write is in flight -- disables
  /// every action in this editor so a fast double-tap can't fire the write
  /// twice.
  bool _busy = false;

  Future<void> _guardedWrite(Future<void> Function() write) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await write();
    } catch (error) {
      debugPrint('Failed to save project change: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).settingsProjectsSaveError)),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _archive(String id) => _guardedWrite(() async {
        final writes = await ref.read(syncedWritesProvider.future);
        await writes.archiveProject(id);
      });

  Future<void> _unarchive(String id) => _guardedWrite(() async {
        final writes = await ref.read(syncedWritesProvider.future);
        await writes.unarchiveProject(id);
      });

  Future<void> _delete(String id) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.projectsDeleteConfirmTitle),
        content: Text(l10n.projectsDeleteConfirmMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.commonDelete),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _guardedWrite(() async {
      final writes = await ref.read(syncedWritesProvider.future);
      try {
        await writes.deleteProject(id);
      } on ProjectHasTimeEntriesException {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.projectsDeleteHasEntriesError)),
          );
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final activeProjects = ref.watch(activeProjectsProvider).value ?? const <Project>[];
    final archivedProjects = ref.watch(archivedProjectsProvider).value ?? const <Project>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.settingsProjectsTitle, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(l10n.settingsProjectsDescription, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 12),
        for (final project in activeProjects)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(
              backgroundColor: Color(int.parse(project.colorHex.replaceFirst('#', '0xFF'))),
              radius: 8,
              child: const SizedBox.shrink(),
            ),
            title: Text(project.name),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  tooltip: l10n.projectsEditTooltip,
                  onPressed:
                      _busy ? null : () => showProjectFormDialog(context, ref, project: project),
                ),
                IconButton(
                  icon: const Icon(Icons.archive_outlined),
                  tooltip: l10n.projectsArchiveTooltip,
                  onPressed: _busy ? null : () => _archive(project.id),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: l10n.projectsDeleteTooltip,
                  onPressed: _busy ? null : () => _delete(project.id),
                ),
              ],
            ),
          ),
        ActionChip(
          avatar: const Icon(Icons.add, size: 18),
          label: Text(l10n.settingsProjectsAddLabel),
          onPressed: _busy ? null : () => showProjectFormDialog(context, ref),
        ),
        if (archivedProjects.isNotEmpty) ...[
          const SizedBox(height: 12),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text(l10n.settingsProjectsArchivedSection),
            children: [
              for (final project in archivedProjects)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const CircleAvatar(
                    backgroundColor: Colors.grey,
                    radius: 8,
                    child: SizedBox.shrink(),
                  ),
                  title: Text(
                    project.name,
                    style: TextStyle(color: Theme.of(context).disabledColor),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.unarchive_outlined),
                        tooltip: l10n.projectsUnarchiveTooltip,
                        onPressed: _busy ? null : () => _unarchive(project.id),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        tooltip: l10n.projectsDeleteTooltip,
                        onPressed: _busy ? null : () => _delete(project.id),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}
