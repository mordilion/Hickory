import 'package:activity_tracker/activity_tracker.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/device_id_provider.dart';
import '../../core/di/sync_providers.dart';
import '../../core/format/duration_format.dart';
import '../../core/theme/hickory_colors.dart';
import '../../core/widgets/gradient_buttons.dart';
import '../../data/drift/database.dart';
import '../../data/drift/time_entry_extensions.dart';
import '../../l10n/app_localizations.dart';
import '../entries/entries_list.dart';
import '../projects/new_project_dialog.dart';
import '../projects/projects_providers.dart';
import 'idle_prompt_dialog.dart';
import 'idle_tracking.dart';
import 'timer_providers.dart';

/// Idle time is prompted about once it reaches this threshold, on desktop
/// only (see [isDesktopTrackingSupported]).
const _idleThresholdSeconds = 5 * 60;

/// Timer tab content — hosted by the app shell (features/shell/app_shell.dart),
/// which owns the Scaffold, AppBar, bottom nav, and the manual-entry FAB.
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
    if (running == null || running.pausedAt != null) return;

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
    if (running == null || running.pausedAt != null) return;
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

  Future<void> _pause(TimeEntry running) async {
    final writes = await ref.read(syncedWritesProvider.future);
    await writes.pauseEntry(running.id);
  }

  Future<void> _resume(TimeEntry running) async {
    final writes = await ref.read(syncedWritesProvider.future);
    await writes.resumeEntry(running.id);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final runningAsync = ref.watch(runningEntryProvider);
    ref.watch(timerTickProvider);
    ref.watch(syncWatcherProvider);

    ref.listen<AsyncValue<int>>(idleSecondsProvider, (previous, next) {
      final idleSeconds = next.value;
      if (idleSeconds != null) _handleIdleSecondsChanged(idleSeconds);
    });
    ref.listen<AsyncValue<ActivitySample>>(activeWindowChangesProvider, (previous, next) {
      final sample = next.value;
      if (sample != null) _recordActivitySample(sample);
    });

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          runningAsync.when(
            data: (running) => running != null
                ? _RunningCard(
                    running: running,
                    onPause: () => _pause(running),
                    onResume: () => _resume(running),
                    onStop: () => _stop(running),
                  )
                : _StartCard(
                    descriptionController: _descriptionController,
                    selectedProjectId: _selectedProjectId,
                    onProjectChanged: (id) => setState(() => _selectedProjectId = id),
                    onStart: _start,
                  ),
            loading: () => const CircularProgressIndicator(),
            error: (e, _) => Text(l10n.timerError('$e')),
          ),
          const SizedBox(height: 16),
          const Expanded(child: EntriesList()),
        ],
      ),
    );
  }
}

class _RunningCard extends ConsumerWidget {
  const _RunningCard({
    required this.running,
    required this.onPause,
    required this.onResume,
    required this.onStop,
  });

  final TimeEntry running;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final isPaused = running.pausedAt != null;
    final elapsed = running.workedDuration;
    final tokens = HickoryColors.of(context);
    final projectsAsync = ref.watch(activeProjectsProvider);
    final projectsById = {
      for (final p in projectsAsync.value ?? const <Project>[]) p.id: p,
    };
    final project = running.projectId == null ? null : projectsById[running.projectId];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: tokens.surfaceGradient,
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            formatDuration(elapsed),
            style: TextStyle(
              fontFamily: Theme.of(context).textTheme.displayLarge?.fontFamily,
              fontWeight: FontWeight.w700,
              fontSize: 34,
              color: tokens.timerNumeral,
            ),
          ),
          if (running.description?.isNotEmpty ?? false) ...[
            const SizedBox(height: 6),
            Text(running.description!),
          ],
          if (project != null) ...[
            const SizedBox(height: 8),
            Chip(label: Text(project.name)),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: GradientPillButton(
                  label: isPaused ? l10n.timerResume : l10n.timerPause,
                  icon: isPaused ? Icons.play_arrow : Icons.pause,
                  gradient: tokens.primaryGradient,
                  foregroundColor: tokens.onPrimaryGradient,
                  onPressed: isPaused ? onResume : onPause,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onStop,
                  icon: const Icon(Icons.stop),
                  label: Text(l10n.timerStop),
                ),
              ),
            ],
          ),
        ],
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
    final l10n = AppLocalizations.of(context);
    final projectsAsync = ref.watch(activeProjectsProvider);
    final tokens = HickoryColors.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: descriptionController,
              decoration: InputDecoration(labelText: l10n.timerDescriptionLabel),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: projectsAsync.when(
                    data: (projects) => DropdownButtonFormField<String?>(
                      initialValue: selectedProjectId,
                      decoration: InputDecoration(labelText: l10n.timerProjectLabel),
                      items: [
                        DropdownMenuItem<String?>(value: null, child: Text(l10n.commonNoProject)),
                        ...projects.map(
                          (p) => DropdownMenuItem<String?>(value: p.id, child: Text(p.name)),
                        ),
                      ],
                      onChanged: onProjectChanged,
                    ),
                    loading: () => const LinearProgressIndicator(),
                    error: (e, _) => Text(l10n.timerError('$e')),
                  ),
                ),
                IconButton(
                  tooltip: l10n.timerNewProjectTooltip,
                  onPressed: () => showNewProjectDialog(context, ref),
                  icon: const Icon(Icons.add_box_outlined),
                ),
              ],
            ),
            const SizedBox(height: 12),
            GradientPillButton(
              label: l10n.timerStart,
              icon: Icons.play_arrow,
              gradient: tokens.primaryGradient,
              foregroundColor: tokens.onPrimaryGradient,
              onPressed: onStart,
            ),
          ],
        ),
      ),
    );
  }
}
