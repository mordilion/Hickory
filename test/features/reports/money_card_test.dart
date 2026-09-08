import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/core/theme/app_theme.dart';
import 'package:hickory/data/drift/database.dart';
import 'package:hickory/features/clients/clients_providers.dart';
import 'package:hickory/features/reports/money_card.dart';
import 'package:hickory/l10n/app_localizations.dart';

TimeEntry _entry({required String? projectId, required int minutes, String id = 'e'}) {
  final start = DateTime(2026, 9, 7, 9).toUtc();
  return TimeEntry(
    id: id,
    projectId: projectId,
    startAt: start,
    endAt: start.add(Duration(minutes: minutes)),
    totalPausedSeconds: 0,
    source: 'manual',
    deviceId: 'd',
    createdAt: DateTime.utc(2026, 1, 1),
    updatedAt: DateTime.utc(2026, 1, 1),
  );
}

Project _project({
  required String id,
  bool billable = true,
  int? rateCents,
  String? currency,
  String? clientId,
}) => Project(
      id: id,
      name: id,
      colorHex: '#000000',
      clientId: clientId,
      archived: false,
      billable: billable,
      hourlyRateCents: rateCents,
      currency: currency,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

void main() {
  Future<void> pumpCard(
    WidgetTester tester, {
    required List<TimeEntry> entries,
    required List<Project> projects,
    List<Client> clients = const [],
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          allClientsProvider.overrideWith((ref) => Stream.value(clients)),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          locale: const Locale('de'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: MoneyCard(entries: entries, projects: projects),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// The lines under one caption. Two blocks can carry the same amount --
  /// revenue and a client's share of it are often the same number -- so an
  /// assertion names the block it means.
  Finder inBlock(String label, Finder matching) => find.descendant(
        of: find.ancestor(of: find.text(label), matching: find.byType(Column)).first,
        matching: matching,
      );

  testWidgets('shows the billable share and the revenue per currency', (tester) async {
    await pumpCard(
      tester,
      entries: [
        _entry(projectId: 'billable-p', minutes: 60, id: 'a'),
        _entry(projectId: 'internal-p', minutes: 180, id: 'b'),
      ],
      projects: [
        _project(id: 'billable-p', rateCents: 10000, currency: 'EUR'),
        _project(id: 'internal-p', billable: false),
      ],
    );

    expect(find.text('25 %'), findsOneWidget);
    expect(inBlock('Umsatz', find.textContaining('100,00')), findsOneWidget);
  });

  testWidgets('names the top clients with what they brought in', (tester) async {
    await pumpCard(
      tester,
      entries: [_entry(projectId: 'p', minutes: 120)],
      projects: [_project(id: 'p', rateCents: 10000, currency: 'EUR', clientId: 'c1')],
      clients: [
        Client(
          id: 'c1',
          name: 'Acme',
          archived: false,
          createdAt: DateTime.utc(2026, 1, 1),
          updatedAt: DateTime.utc(2026, 1, 1),
        ),
      ],
    );

    expect(find.text('Acme'), findsOneWidget);
    expect(inBlock('Top-Kunden', find.textContaining('200,00')), findsOneWidget);
  });

  testWidgets('says there is no revenue rather than showing a bare zero', (tester) async {
    await pumpCard(
      tester,
      entries: [_entry(projectId: 'p', minutes: 60)],
      projects: [_project(id: 'p', billable: false)],
    );

    expect(find.text('Kein Umsatz im Zeitraum.'), findsOneWidget);
    expect(find.text('0 %'), findsOneWidget);
  });
}
