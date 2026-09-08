import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/data/drift/database.dart';
import 'package:hickory/features/reports/money_calculations.dart';

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
  String? name,
}) => Project(
      id: id,
      name: name ?? id,
      colorHex: '#000000',
      clientId: clientId,
      archived: false,
      billable: billable,
      hourlyRateCents: rateCents,
      currency: currency,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

Client _client(String id, String name) => Client(
      id: id,
      name: name,
      archived: false,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

void main() {
  test('the billable share is of tracked time, not of the range', () {
    final figures = moneyFigures(
      [
        _entry(projectId: 'billable-p', minutes: 60, id: 'a'),
        _entry(projectId: 'internal-p', minutes: 180, id: 'b'),
      ],
      [
        _project(id: 'billable-p', rateCents: 10000, currency: 'EUR'),
        _project(id: 'internal-p', billable: false),
      ],
      const [],
    );

    expect(figures.billableShare, 0.25);
    expect(figures.revenueCentsByCurrency, {'EUR': 10000});
  });

  test('currencies are kept apart rather than added up', () {
    final figures = moneyFigures(
      [
        _entry(projectId: 'eur', minutes: 60, id: 'a'),
        _entry(projectId: 'usd', minutes: 60, id: 'b'),
      ],
      [
        _project(id: 'eur', rateCents: 10000, currency: 'EUR'),
        _project(id: 'usd', rateCents: 20000, currency: 'USD'),
      ],
      const [],
    );

    expect(figures.revenueCentsByCurrency, {'EUR': 10000, 'USD': 20000});
  });

  test('a billable project without a rate earns nothing but still counts as billable', () {
    final figures = moneyFigures(
      [_entry(projectId: 'p', minutes: 60)],
      [_project(id: 'p')],
      const [],
    );

    expect(figures.billableShare, 1.0);
    expect(figures.revenueCentsByCurrency, isEmpty);
  });

  test('an entry without a project is not billable', () {
    final figures = moneyFigures(
      [_entry(projectId: null, minutes: 60)],
      const [],
      const [],
    );

    expect(figures.billableShare, 0);
  });

  test('nothing tracked is a share of zero, not a division by zero', () {
    expect(moneyFigures(const [], const [], const []).billableShare, 0);
  });

  test('top clients are ordered by revenue and capped at the asked-for count', () {
    final figures = moneyFigures(
      [
        _entry(projectId: 'big', minutes: 600, id: 'a'),
        _entry(projectId: 'medium', minutes: 300, id: 'b'),
        _entry(projectId: 'small', minutes: 60, id: 'c'),
      ],
      [
        _project(id: 'big', rateCents: 10000, currency: 'EUR', clientId: 'c1'),
        _project(id: 'medium', rateCents: 10000, currency: 'EUR', clientId: 'c2'),
        _project(id: 'small', rateCents: 10000, currency: 'EUR', clientId: 'c3'),
      ],
      [_client('c1', 'Big'), _client('c2', 'Medium'), _client('c3', 'Small')],
      topClientCount: 2,
    );

    expect(figures.topClients.map((client) => client.clientName), ['Big', 'Medium']);
    expect(figures.topClients.first.amountCents, 100000);
  });

  test('revenue from projects without a client is gathered under one label', () {
    final figures = moneyFigures(
      [_entry(projectId: 'p', minutes: 60)],
      [_project(id: 'p', rateCents: 10000, currency: 'EUR')],
      const [],
      noClientLabel: 'Ohne Kunde',
    );

    expect(figures.topClients.single.clientName, 'Ohne Kunde');
  });

  test('a client billed in two currencies is one row per currency', () {
    // Summing them would invent an exchange rate the app has no business
    // choosing.
    final figures = moneyFigures(
      [
        _entry(projectId: 'eur', minutes: 60, id: 'a'),
        _entry(projectId: 'usd', minutes: 60, id: 'b'),
      ],
      [
        _project(id: 'eur', rateCents: 10000, currency: 'EUR', clientId: 'c1'),
        _project(id: 'usd', rateCents: 5000, currency: 'USD', clientId: 'c1'),
      ],
      [_client('c1', 'Acme')],
    );

    expect(figures.topClients, hasLength(2));
    expect(figures.topClients.map((client) => client.currency), ['EUR', 'USD']);
  });
}
