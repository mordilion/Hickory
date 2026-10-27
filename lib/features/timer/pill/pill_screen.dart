import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../../../core/di/sync_providers.dart';
import '../../../core/format/duration_format.dart';
import '../../../core/theme/hickory_colors.dart';
import '../../../core/window/window_mode_provider.dart';
import '../../../data/drift/database.dart';
import '../../../data/drift/time_entry_extensions.dart';
import '../../../data/sync/synced_writes.dart';
import '../../../l10n/app_localizations.dart';
import '../../clients/clients_providers.dart';
import '../../projects/projects_providers.dart';
import '../timer_providers.dart';

/// The 320x56 always-on-top timer pill. Shown instead of AppShell while
/// WindowModeController has the window in [WindowMode.pill] (see
/// `lib/core/window/window_mode.dart`); the window itself is reshaped by
/// that controller, this widget only paints into it.
///
/// A pure rendering of five callbacks plus whether the last [onExpand]
/// attempt failed -- it reads the running entry to display it but never
/// writes, and never touches a platform API itself: `PillHost` wraps this
/// widget, supplies the callbacks from the same writes the timer tab uses,
/// and turns [onDragStart] into `windowManager.startDragging()`. That
/// indirection is deliberate -- `lib/core/window/native_window.dart` exists
/// precisely so `window_manager`, a plugin singleton backed by a platform
/// channel, is never called from a widget a test cannot reach.
///
/// The whole surface outside the three buttons invokes [onDragStart] on
/// pan-start, verified on macOS only -- Windows support for frameless
/// dragging is unconfirmed (see
/// docs/superpowers/specs/2026-09-10-timer-pill-design.md section 8.2).
class PillScreen extends ConsumerWidget {
  const PillScreen({
    super.key,
    required this.onPause,
    required this.onResume,
    required this.onStop,
    required this.onExpand,
    required this.onDragStart,
    this.expandFailed = false,
  });

  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onStop;
  final VoidCallback onExpand;
  final VoidCallback onDragStart;

  /// Set by `PillHost` when the previous [onExpand] threw (spec 8.2's live
  /// Windows risk: `setTitleBarStyle` may not restore there). A SnackBar --
  /// this codebase's house pattern for a failed write elsewhere (see
  /// `lib/features/clients/clients_editor.dart`) -- does not fit here: its
  /// minimum height alone is close to this window's entire 56px, so it would
  /// either get clipped by the fixed, non-resizable frame or blot out the
  /// controls the user would need to retry. Swapping the expand icon for a
  /// warning glyph with an explanatory tooltip stays inside the pill's
  /// existing footprint and keeps the button tappable for a retry.
  final bool expandFailed;

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
    // gradient surface below still reads as a pill.
    return Scaffold(
      body: SizedBox.expand(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (_) => onDragStart(),
          child: Stack(
            children: [
              // Painted as its own layer, separate from the content below,
              // so dimming it for the paused state never also washes out
              // the buttons or text (see _PillSurface).
              Positioned.fill(child: _PillSurface(tokens: tokens, isPaused: isPaused)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // The numeral must never wrap. This window's height
                          // is fixed at 56px, and a second line of it does
                          // not fit -- `formatDuration` leaves the hours
                          // uncapped, so a timer left running over a holiday
                          // reaches four digits and, at this font size, is
                          // wider than the column. Scaling it down keeps
                          // every digit readable where ellipsizing a clock
                          // would not, and changes nothing at ordinary
                          // lengths, since BoxFit.scaleDown never enlarges.
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              formatDuration(running?.workedDuration ?? Duration.zero),
                              style: TextStyle(
                                fontFamily: Theme.of(context).textTheme.displayLarge?.fontFamily,
                                fontWeight: FontWeight.w700,
                                fontSize: 20,
                                height: 1.1,
                                color: isPaused ? tokens.textMuted : tokens.timerNumeral,
                              ),
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
                      icon: expandFailed ? Icons.error_outline : Icons.open_in_full,
                      tooltip: expandFailed ? l10n.pillExpandError : l10n.pillExpand,
                      onPressed: onExpand,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The pill's gradient background. Isolated from the row of text and buttons
/// painted on top of it (see [PillScreen]) so dimming it for the paused
/// state cannot also mute a button's tap affordance or double-dim the
/// numeral, which already gets its own muted colour.
class _PillSurface extends StatelessWidget {
  const _PillSurface({required this.tokens, required this.isPaused});

  final HickoryColors tokens;
  final bool isPaused;

  @override
  Widget build(BuildContext context) {
    final gradient = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: tokens.surfaceGradient,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
    );
    if (!isPaused) return gradient;

    // Scales the rendered RGB down (alpha untouched) instead of blending
    // toward another token colour. A Color.lerp target doesn't work here:
    // the dark palette's muted/text tokens are near-white -- they double as
    // legible foreground colours on a dark surface -- so lerping toward one
    // of them would brighten the paused pill in dark mode instead of
    // dimming it. Multiplying channels is the one approach that reads as
    // dimmer in both palettes without a new colour literal (design spec
    // section 6: "frozen time, dimmed surface, ▶ instead of ⏸").
    return ColorFiltered(
      colorFilter: const ColorFilter.matrix(<double>[
        0.55, 0, 0, 0, 0, //
        0, 0.55, 0, 0, 0, //
        0, 0, 0.55, 0, 0, //
        0, 0, 0, 1, 0,
      ]),
      child: gradient,
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

/// Supplies [PillScreen] with the running entry's controls, using the same
/// writes `TimerScreen` uses, and turns [PillScreen.onDragStart] into the
/// one `window_manager` call it makes. Separate from PillScreen so that
/// widget stays a pure rendering of five callbacks a test can reach without
/// a platform channel (see PillScreen's doc comment).
///
/// Stateful only for [_expandFailed]: expand() is the one control here whose
/// failure would otherwise vanish silently (this project's
/// `.claude/rules/core/general/architecture.md` forbids that) with the pill
/// stuck up and no way for the user to tell a second tap would only fail the
/// same way -- see [PillScreen.expandFailed] for why that surfaces as an
/// icon swap rather than a SnackBar.
class PillHost extends ConsumerStatefulWidget {
  const PillHost({super.key});

  @override
  ConsumerState<PillHost> createState() => _PillHostState();
}

class _PillHostState extends ConsumerState<PillHost> {
  bool _expandFailed = false;

  Future<void> _expand() async {
    try {
      await ref.read(windowModeProvider.notifier).expand();
      if (mounted) setState(() => _expandFailed = false);
    } catch (error) {
      // Best-effort logging, matching this project's other guarded-write
      // call sites (e.g. ClientsEditor._guardedWrite): the real signal for
      // the user is the icon swap below, not this log line.
      debugPrint('Pill failed to expand the window: $error');
      if (mounted) setState(() => _expandFailed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final running = ref.watch(runningEntryProvider).value;

    Future<void> withWrites(Future<void> Function(SyncedWrites writes) action) async {
      final writes = await ref.read(syncedWritesProvider.future);
      await action(writes);
    }

    void ifRunning(Future<void> Function(SyncedWrites writes, TimeEntry entry) action) {
      final entry = running;
      if (entry == null) return;
      withWrites((writes) => action(writes, entry));
    }

    return PillScreen(
      onPause: () => ifRunning((writes, entry) => writes.pauseEntry(entry.id)),
      onResume: () => ifRunning((writes, entry) => writes.resumeEntry(entry.id)),
      onStop: () => ifRunning((writes, entry) => writes.stopEntry(entry.id)),
      onExpand: () => unawaited(_expand()),
      onDragStart: () => windowManager.startDragging(),
      expandFailed: _expandFailed,
    );
  }
}
