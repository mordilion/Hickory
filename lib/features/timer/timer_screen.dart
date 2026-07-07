import 'package:activity_tracker/activity_tracker.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/device_id_provider.dart';
import '../../core/di/sync_providers.dart';
import '../../core/format/duration_format.dart';
import '../../data/drift/database.dart';
import '../entries/entries_list.dart';
import '../entries/manual_entry_dialog.dart';
import '../projects/new_project_dialog.dart';
import '../projects/projects_providers.dart';
import '../sync/sync_settings_dialog.dart';
import 'idle_prompt_dialog.dart';
import 'idle_tracking.dart';
import 'timer_providers.dart';

/// Idle time is prompted about once it reaches this threshold, on desktop
/// only (see [isDesktopTrackingSupported]).
const _idleThresholdSeconds = 5 * 60;

class TimerScreen extends ConsumerStatefulWidget {
  const TimerScreen({super.key});

  @override
  ConsumerState<TimerScreen> createState() => _TimerScreenState();
}

class _TimerScreenState extends ConsumerState<TimerScreen> {
  final _descriptionController = TextEditingController();
  String? _selectedProjectId;
  bool _idlePromptShowing = false;

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _handleIdleSecondsChanged(int idleSeconds) async {
    if (idleSeconds < _idleThresholdSeconds) {
      _idlePromptShowing = false;
      return;
    }
    if (_idlePromptShowing) return;
    final running = ref.read(runningEntryProvider).value;
    if (running == null) return;

    _idlePromptShowing = true;
    final idleDuration = Duration(seconds: idleSeconds);
    final shouldTrim = await showIdlePromptDialog(context, idleDuration);
    if (!mounted) return;
    if (shouldTrim) {
      final writes = await ref.read(syncedWritesProvider.future);
      final idleStart = DateTime.now().subtract(idleDuration);
      await writes.updateEntry(running.id, endAt: Value(idleStart.toUtc()));
    }
    _idlePromptShowing = false;
  }

  Future<void> _recordActivitySample(ActivitySample sample) async {
    final running = ref.read(runningEntryProvider).value;
    if (running == null) return;
    final deviceId = await ref.read(deviceIdProvider.future);
    final writes = await ref.read(syncedWritesProvider.future);
    await writes.recordActivitySample(
      deviceId: deviceId,
      appName: sample.appName,
      windowTitle: sample.windowTitle,
      observedAt: sample.observedAt,
    );
  }

  Future<void> _start() async {
    final deviceId = await ref.read(deviceIdProvider.future);
    final writes = await ref.read(syncedWritesProvider.future);
    await writes.startEntry(
      deviceId: deviceId,
      projectId: _selectedProjectId,
      description: _descriptionController.text.trim().isEmpty
          ? null
          : _descriptionController.text.trim(),
    );
    _descriptionController.clear();
  }

  Future<void> _stop(TimeEntry running) async {
    final writes = await ref.read(syncedWritesProvider.future);
    await writes.stopEntry(running.id);
  }

  @override
  Widget build(BuildContext context) {
    final runningAsync = ref.watch(runningEntryProvider);
    ref.watch(timerTickProvider);
    // Watching this activates the initial-sync + folder-watcher for the
    // app's lifetime; the sync settings dialog re-reads its dependencies
    // directly rather than relying on this AsyncValue.
    ref.watch(syncWatcherProvider);

    // Desktop-only auto-tracking: idle-time prompt on the running timer,
    // and a record of which app/window was active while it ran. Both
    // no-op (never fire) on platforms activity_tracker doesn't support.
    ref.listen<AsyncValue<int>>(idleSecondsProvider, (previous, next) {
      final idleSeconds = next.value;
      if (idleSeconds != null) _handleIdleSecondsChanged(idleSeconds);
    });
    ref.listen<AsyncValue<ActivitySample>>(activeWindowChangesProvider, (previous, next) {
      final sample = next.value;
      if (sample != null) _recordActivitySample(sample);
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Hickory'),
        actions: [
          IconButton(
            tooltip: 'Sync-Einstellungen',
            onPressed: () => showSyncSettingsDialog(context),
            icon: const Icon(Icons.sync),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: runningAsync.when(
              data: (running) => running != null
                  ? _RunningCard(running: running, onStop: () => _stop(running))
                  : _StartCard(
                      descriptionController: _descriptionController,
                      selectedProjectId: _selectedProjectId,
                      onProjectChanged: (id) => setState(() => _selectedProjectId = id),
                      onStart: _start,
                    ),
              loading: () => const CircularProgressIndicator(),
              error: (e, _) => Text('Fehler: $e'),
            ),
          ),
          const Divider(height: 1),
          Expanded(child: EntriesList()),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => showManualEntryDialog(context, ref),
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _RunningCard extends StatelessWidget {
  const _RunningCard({required this.running, required this.onStop});

  final TimeEntry running;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final elapsed = DateTime.now().toUtc().difference(running.startAt);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    formatDuration(elapsed),
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  if (running.description != null) Text(running.description!),
                ],
              ),
            ),
            FilledButton.tonalIcon(
              onPressed: onStop,
              icon: const Icon(Icons.stop),
              label: const Text('Stop'),
            ),
          ],
        ),
      ),
    );
  }
}

class _StartCard extends ConsumerWidget {
  const _StartCard({
    required this.descriptionController,
    required this.selectedProjectId,
    required this.onProjectChanged,
    required this.onStart,
  });

  final TextEditingController descriptionController;
  final String? selectedProjectId;
  final ValueChanged<String?> onProjectChanged;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projectsAsync = ref.watch(activeProjectsProvider);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: descriptionController,
              decoration: const InputDecoration(labelText: 'Was arbeitest du gerade?'),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: projectsAsync.when(
                    data: (projects) => DropdownButtonFormField<String?>(
                      initialValue: selectedProjectId,
                      decoration: const InputDecoration(labelText: 'Projekt'),
                      items: [
                        const DropdownMenuItem<String?>(value: null, child: Text('Kein Projekt')),
                        ...projects.map(
                          (p) => DropdownMenuItem<String?>(value: p.id, child: Text(p.name)),
                        ),
                      ],
                      onChanged: onProjectChanged,
                    ),
                    loading: () => const LinearProgressIndicator(),
                    error: (e, _) => Text('Fehler: $e'),
                  ),
                ),
                IconButton(
                  tooltip: 'Neues Projekt',
                  onPressed: () => showNewProjectDialog(context, ref),
                  icon: const Icon(Icons.add_box_outlined),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onStart,
                icon: const Icon(Icons.play_arrow),
                label: const Text('Start'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
