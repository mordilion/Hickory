import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../../../core/format/duration_format.dart';
import '../../../core/theme/hickory_colors.dart';
import '../../../data/drift/database.dart';
import '../../../data/drift/time_entry_extensions.dart';
import '../../../l10n/app_localizations.dart';
import '../../clients/clients_providers.dart';
import '../../projects/projects_providers.dart';
import '../timer_providers.dart';

/// The 320x56 always-on-top timer pill. Shown instead of AppShell while
/// WindowModeController has the window in [WindowMode.pill] (see
/// `lib/core/window/window_mode.dart`); the window itself is reshaped by
/// that controller, this widget only paints into it.
///
/// A pure rendering of four callbacks -- it reads the running entry to
/// display it but never writes: a later task's `PillHost` wraps this widget
/// and supplies the callbacks from the same writes the timer tab uses.
///
/// The whole surface outside the three buttons drags the window
/// (`onPanStart` -> `windowManager.startDragging()`), verified on macOS only
/// -- Windows support for frameless dragging is unconfirmed (see
/// docs/superpowers/specs/2026-09-10-timer-pill-design.md section 8.2).
class PillScreen extends ConsumerWidget {
  const PillScreen({
    super.key,
    required this.onPause,
    required this.onResume,
    required this.onStop,
    required this.onExpand,
  });

  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onStop;
  final VoidCallback onExpand;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final tokens = HickoryColors.of(context);
    // Forces a rebuild every second so the elapsed time counts up; the
    // duration itself is always derived from the entry (see
    // TimeEntryDuration.workedDuration), never accumulated here.
    ref.watch(timerTickProvider);
    final running = ref.watch(runningEntryProvider).value;
    final isPaused = running?.pausedAt != null;

    // No `backgroundColor` here: Colors.transparent is a colour literal this
    // project forbids, and a transparent body on a frameless window can
    // paint black. Omitting it lets the Scaffold take the theme surface;
    // macOS clips the window's corners itself (spike-verified), so the
    // gradient Container below still reads as a pill.
    return Scaffold(
      body: SizedBox.expand(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (_) => windowManager.startDragging(),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: tokens.surfaceGradient,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        formatDuration(running?.workedDuration ?? Duration.zero),
                        style: TextStyle(
                          fontFamily: Theme.of(context).textTheme.displayLarge?.fontFamily,
                          fontWeight: FontWeight.w700,
                          fontSize: 20,
                          height: 1.1,
                          color: isPaused ? tokens.textMuted : tokens.timerNumeral,
                        ),
                      ),
                      _ProjectLine(entry: running, muted: tokens.textMuted),
                    ],
                  ),
                ),
                _PillButton(
                  icon: isPaused ? Icons.play_arrow : Icons.pause,
                  tooltip: isPaused ? l10n.pillResume : l10n.pillPause,
                  onPressed: isPaused ? onResume : onPause,
                ),
                _PillButton(icon: Icons.stop, tooltip: l10n.pillStop, onPressed: onStop),
                _PillButton(
                  icon: Icons.open_in_full,
                  tooltip: l10n.pillExpand,
                  onPressed: onExpand,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "Client · Project" on one ellipsized line; the project alone when it has
/// no client; nothing when the entry has no project at all.
class _ProjectLine extends ConsumerWidget {
  const _ProjectLine({required this.entry, required this.muted});

  final TimeEntry? entry;
  final Color muted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projectId = entry?.projectId;
    if (projectId == null) return const SizedBox.shrink();

    final projects = ref.watch(activeProjectsProvider).value ?? const <Project>[];
    Project? project;
    for (final candidate in projects) {
      if (candidate.id == projectId) project = candidate;
    }
    if (project == null) return const SizedBox.shrink();

    final clientId = project.clientId;
    String? clientName;
    if (clientId != null) {
      final clients = ref.watch(allClientsProvider).value ?? const <Client>[];
      for (final client in clients) {
        if (client.id == clientId) clientName = client.name;
      }
    }

    final label = clientName == null ? project.name : '$clientName · ${project.name}';
    return Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontSize: 11, color: muted),
    );
  }
}

/// Icon-only button sized for the pill's cramped 56px height. `tooltip` does
/// double duty as required by this project's accessibility rules: it drives
/// IconButton's built-in `Tooltip` wrapper (hover text for sighted users)
/// and that same Tooltip also supplies the Semantics tooltip screen readers
/// announce, so one string satisfies both without a second wrapper.
class _PillButton extends StatelessWidget {
  const _PillButton({required this.icon, required this.tooltip, required this.onPressed});

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, size: 20),
      tooltip: tooltip,
      onPressed: onPressed,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 32, height: 32),
    );
  }
}
