import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/di/app_settings_provider.dart';
import '../../l10n/app_localizations.dart';
import '../../core/format/date_format.dart';
import '../../core/format/duration_format.dart';
import 'balance_calculations.dart';
import 'report_view_controller.dart';
import 'reports_providers.dart';

/// "+1:30" / "-0:45" — the sign is always explicit, because a balance of
/// "1:30" would be ambiguous between a surplus and a deficit. Deliberately
/// not the shared formatDuration, which has no notion of a sign.
String formatSignedDuration(Duration balance) {
  final sign = balance.isNegative ? '-' : '+';
  final absolute = balance.abs();
  final minutes = absolute.inMinutes.remainder(60).toString().padLeft(2, '0');
  return '$sign${absolute.inHours}:$minutes';
}

/// The flex-time balance, as the Reports tab's first tile. Shows an empty
/// state pointing at Settings while no target is configured: with the
/// shipped defaults (every weekday 0) every tracked minute would otherwise
/// read as overtime.
class BalanceCard extends ConsumerWidget {
  const BalanceCard({super.key});

  /// A card shaped like the loaded state (same padding, same min height via
  /// the spinner) so the tile doesn't collapse to nothing or jump size once
  /// data arrives.
  static Widget _loadingCard() => const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Center(child: CircularProgressIndicator()),
        ),
      );

  static Widget _errorCard(AppLocalizations l10n, Object error) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(l10n.reportsError('$error')),
        ),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    // The balance covers every entry, whatever the tab's filters say (see
    // workTimeBalanceProvider): "overtime, but only for project X" is not
    // a meaningful number. With the filter button sitting right above this
    // tile, that has to be said out loud -- an entry list that narrows
    // while the balance stays put otherwise reads as a bug. Via `.value`,
    // so a state that is still loading (or failed to load) simply carries
    // no note: no filter can be active before it arrives.
    final filterActive =
        (ref.watch(reportViewControllerProvider).value?.activeFilterCount ?? 0) > 0;
    // Watched via .when rather than `.value` so a stream error is shown as
    // an error card instead of being read back as null and mistaken for
    // "still loading" (AsyncError's own isLoading/value are not useful
    // signals here — see workTimeBalanceProvider's doc comment).
    return ref.watch(appSettingsProvider).when(
      loading: _loadingCard,
      error: (error, _) => _errorCard(l10n, error),
      data: (settings) {
        if (!hasAnyTarget(settings)) {
          return Card(
            child: ListTile(
              leading: const Icon(Icons.schedule_outlined),
              title: Text(l10n.reportsBalanceNoTargets),
              subtitle: Text(l10n.reportsBalanceConfigure),
            ),
          );
        }

        final cutoff = lastCutoffOnOrBefore(settings, DateTime.now());
        final localeName = Localizations.localeOf(context).toLanguageTag();
        final label = cutoff == null
            ? l10n.reportsBalanceAllTime
            : l10n.reportsBalanceSince(DateFormat.yMd(localeName).format(cutoff));

        final timeStyle = settings.timeStyle;
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: ref.watch(workTimeBalanceProvider).when(
                  data: (balance) {
                    final figures = ref.watch(balanceFiguresProvider).value;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Wrap(
                          spacing: 24,
                          runSpacing: 16,
                          children: [
                            _BalanceTile(label: label, value: balance),
                            _BalanceTile(
                              label: l10n.reportsBalanceInRange,
                              value: figures?.balance,
                            ),
                            _TargetTile(figures: figures, timeStyle: timeStyle, l10n: l10n),
                            _AverageTile(
                              figures: figures,
                              timeStyle: timeStyle,
                              l10n: l10n,
                            ),
                          ],
                        ),
                        if (filterActive) ...[
                          const SizedBox(height: 12),
                          Text(
                            l10n.reportsBalanceIgnoresFilter,
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ],
                    );
                  },
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Text(l10n.reportsError('$e')),
                ),
          ),
        );
      },
    );
  }
}


/// One figure of the balance block: a caption above a single number.
///
/// A signed duration carries its sign as an icon *and* a colour, never a
/// colour alone. A null [value] means the figures have not arrived yet and
/// renders as a dash rather than a zero, which would read as a real
/// measurement.
class _BalanceTile extends StatelessWidget {
  const _BalanceTile({required this.label, required this.value});

  final String label;
  final Duration? value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final balance = value;
    final isDeficit = balance != null && balance.isNegative;
    final color = balance == null
        ? theme.colorScheme.onSurfaceVariant
        : (isDeficit ? theme.colorScheme.error : theme.colorScheme.primary);
    return _TileFrame(
      label: label,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (balance != null) ...[
            Icon(
              isDeficit ? Icons.trending_down : Icons.trending_up,
              color: color,
              size: 20,
            ),
            const SizedBox(width: 8),
          ],
          Text(
            balance == null
                ? AppLocalizations.of(context).reportsBalanceNoFigure
                : formatSignedDuration(balance),
            style: theme.textTheme.headlineSmall?.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}

/// Target against what was actually credited, with a progress bar. The bar
/// is clamped at one so a surplus fills it rather than overflowing, while
/// the figures beside it still say by how much.
class _TargetTile extends StatelessWidget {
  const _TargetTile({
    required this.figures,
    required this.timeStyle,
    required this.l10n,
  });

  final RangeFigures? figures;
  final TimeFormatStyle timeStyle;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final range = figures;
    return _TileFrame(
      label: l10n.reportsBalanceTargetVsActual,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            range == null
                ? l10n.reportsBalanceNoFigure
                : '${formatDuration(range.target, timeStyle)} / '
                      '${formatDuration(range.worked + range.absenceCredit, timeStyle)}',
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: 160,
            child: LinearProgressIndicator(
              value: range == null ? 0 : range.completion.clamp(0, 1).toDouble(),
            ),
          ),
        ],
      ),
    );
  }
}

/// What a work day in the range carried on average, or a dash when the
/// range holds no work day at all — an average over nothing is not a
/// number.
class _AverageTile extends StatelessWidget {
  const _AverageTile({
    required this.figures,
    required this.timeStyle,
    required this.l10n,
  });

  final RangeFigures? figures;
  final TimeFormatStyle timeStyle;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final range = figures;
    final hasWorkDays = range != null && range.workDays > 0;
    return _TileFrame(
      label: l10n.reportsBalanceAveragePerDay,
      child: Text(
        hasWorkDays
            ? formatDuration(range.averagePerWorkDay, timeStyle)
            : l10n.reportsBalanceNoFigure,
        style: Theme.of(context).textTheme.headlineSmall,
      ),
    );
  }
}

/// Caption above value, the shape every tile in the block shares.
class _TileFrame extends StatelessWidget {
  const _TileFrame({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 4),
        child,
      ],
    );
  }
}
