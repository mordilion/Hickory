// Money and billability arithmetic for the Reports dashboard. Pure: no
// Riverpod, no Flutter, no database access beyond drift's row types — the
// same shape as report_calculations.dart and balance_calculations.dart.
//
// Amounts are integer cents throughout and are never summed across
// currencies: converting one into another would mean picking an exchange
// rate, which is a decision this app has no basis for making.

import '../../data/drift/database.dart';
import 'report_calculations.dart' show totalsByProject;

/// What one client earned in one currency.
typedef ClientRevenue = ({String clientName, int amountCents, String currency});

/// The money side of a report range.
class MoneyFigures {
  const MoneyFigures({
    required this.billableDuration,
    required this.totalDuration,
    required this.revenueCentsByCurrency,
    required this.topClients,
  });

  /// Time booked to a project marked billable — whether or not that project
  /// carries an hourly rate. Billable says what the time *is*; the rate only
  /// says what it is worth.
  final Duration billableDuration;
  final Duration totalDuration;

  /// Cents per ISO currency code, one entry per currency actually earned in.
  final Map<String, int> revenueCentsByCurrency;

  /// Richest first, capped by the caller's `topClientCount`. A client billed
  /// in two currencies appears once per currency.
  final List<ClientRevenue> topClients;

  /// Billable share of the time tracked in the range, `0` when nothing was
  /// tracked at all — a share of nothing is not 100%.
  double get billableShare => totalDuration == Duration.zero
      ? 0
      : billableDuration.inMinutes / totalDuration.inMinutes;
}

/// Folds [entries] into the money figures for a range.
///
/// Unfinished entries are ignored, as everywhere else. An entry whose
/// project is unknown (no project, or one that was deleted) is not
/// billable and earns nothing: the app cannot invoice what it cannot
/// attribute.
MoneyFigures moneyFigures(
  List<TimeEntry> entries,
  List<Project> projects,
  List<Client> clients, {
  String noClientLabel = '—',
  int topClientCount = 3,
}) {
  final projectsById = {for (final project in projects) project.id: project};
  final clientsById = {for (final client in clients) client.id: client};
  final totals = totalsByProject(entries, projects);

  var billable = Duration.zero;
  var total = Duration.zero;
  final revenueByCurrency = <String, int>{};
  // Keyed by client *and* currency, for the reason given on [ClientRevenue].
  final revenueByClient = <(String, String), int>{};

  for (final projectTotal in totals) {
    total += projectTotal.duration;
    if (projectTotal.billable) billable += projectTotal.duration;

    final amount = projectTotal.amountCents;
    final currency = projectTotal.currency;
    if (amount == null || currency == null) continue;
    revenueByCurrency.update(currency, (sum) => sum + amount, ifAbsent: () => amount);

    final projectId = projectTotal.projectId;
    final clientId = projectId == null ? null : projectsById[projectId]?.clientId;
    final clientName = clientId == null
        ? noClientLabel
        : (clientsById[clientId]?.name ?? noClientLabel);
    revenueByClient.update(
      (clientName, currency),
      (sum) => sum + amount,
      ifAbsent: () => amount,
    );
  }

  final ranked = revenueByClient.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));

  return MoneyFigures(
    billableDuration: billable,
    totalDuration: total,
    revenueCentsByCurrency: revenueByCurrency,
    topClients: [
      for (final entry in ranked.take(topClientCount))
        (clientName: entry.key.$1, amountCents: entry.value, currency: entry.key.$2),
    ],
  );
}
