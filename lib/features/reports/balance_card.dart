import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/di/app_settings_provider.dart';
import '../../l10n/app_localizations.dart';
import 'balance_calculations.dart';
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final settings = ref.watch(appSettingsProvider).value;
    if (settings == null) return const SizedBox.shrink();

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
                return Row(
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
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Text(l10n.reportsError('$e')),
            ),
      ),
    );
  }
}
