import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/di/app_settings_provider.dart';
import '../../l10n/app_localizations.dart';
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

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: ref.watch(workTimeBalanceProvider).when(
                  data: (balance) {
                    // Icon and colour together, never colour alone.
                    final isDeficit = balance.isNegative;
                    final color = isDeficit ? theme.colorScheme.error : theme.colorScheme.primary;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Icon(
                              isDeficit ? Icons.trending_down : Icons.trending_up,
                              color: color,
                            ),
                            const SizedBox(width: 12),
                            Expanded(child: Text(label, style: theme.textTheme.titleMedium)),
                            Text(
                              formatSignedDuration(balance),
                              style: theme.textTheme.headlineSmall?.copyWith(color: color),
                            ),
                          ],
                        ),
                        if (filterActive) ...[
                          const SizedBox(height: 8),
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
