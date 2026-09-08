import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/drift/database.dart';
import '../../l10n/app_localizations.dart';
import '../clients/clients_providers.dart';
import 'money_calculations.dart';

/// The Reports dashboard's money block: how much of the tracked time is
/// billable, what it earned per currency, and which clients it came from.
///
/// Takes the **filtered** entries and projects, unlike the balance block:
/// revenue for one project or one client is a meaningful figure, where
/// "overtime, but only for project X" is not (spec §6).
class MoneyCard extends ConsumerWidget {
  const MoneyCard({super.key, required this.entries, required this.projects});

  final List<TimeEntry> entries;
  final List<Project> projects;

  /// Cents in [currency], in the reader's own locale. Falls back to the
  /// plain code when the currency is not one intl knows a symbol for.
  static String _money(int cents, String currency, String localeName) {
    return NumberFormat.currency(
      locale: localeName,
      name: currency,
      symbol: NumberFormat.simpleCurrency(locale: localeName, name: currency).currencySymbol,
    ).format(cents / 100);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final localeName = Localizations.localeOf(context).toLanguageTag();
    final clients = ref.watch(allClientsProvider).value ?? const <Client>[];
    final figures = moneyFigures(
      entries,
      projects,
      clients,
      noClientLabel: l10n.reportsMoneyNoClient,
    );
    final revenue = figures.revenueCentsByCurrency;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.reportsMoneyTitle, style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            Wrap(
              spacing: 24,
              runSpacing: 16,
              crossAxisAlignment: WrapCrossAlignment.start,
              children: [
                _Figure(
                  label: l10n.reportsMoneyBillableShare,
                  // Rounded to whole percent: a billable share is a
                  // rule-of-thumb figure, and decimals invite reading it as
                  // an invoice line.
                  value: '${(figures.billableShare * 100).round()} %',
                ),
                _Block(
                  label: l10n.reportsMoneyRevenue,
                  children: [
                    if (revenue.isEmpty)
                      Text(l10n.reportsMoneyNoRevenue, style: theme.textTheme.bodyMedium),
                    for (final entry in revenue.entries)
                      Text(
                        _money(entry.value, entry.key, localeName),
                        style: theme.textTheme.titleMedium,
                      ),
                  ],
                ),
                if (figures.topClients.isNotEmpty)
                  _Block(
                    label: l10n.reportsMoneyTopClients,
                    children: [
                      for (final client in figures.topClients)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(client.clientName),
                            const SizedBox(width: 12),
                            Text(
                              _money(client.amountCents, client.currency, localeName),
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Caption above a single figure — the shape the balance block's tiles use.
class _Figure extends StatelessWidget {
  const _Figure({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => _Block(
        label: label,
        children: [Text(value, style: Theme.of(context).textTheme.headlineSmall)],
      );
}

/// Caption above a short list of lines.
class _Block extends StatelessWidget {
  const _Block({required this.label, required this.children});

  final String label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 4),
        ...children,
      ],
    );
  }
}
