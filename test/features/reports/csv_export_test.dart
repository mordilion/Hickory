import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/core/format/date_format.dart';
import 'package:hickory/data/drift/database.dart';
import 'package:hickory/features/reports/csv_export.dart';
import 'package:hickory/l10n/app_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  // German localizations everywhere: the default language must keep producing
  // byte-identical CSV output so existing consumers don't break.
  final l10n = lookupAppLocalizations(const Locale('de'));

  setUpAll(() async {
    await initializeDateFormatting('de_DE');
    await initializeDateFormatting('en_US');
  });

  test('entriesToCsv writes one row per finished entry with a header', () {
    final now = DateTime.utc(2026, 7, 1);
    final project = Project(
      id: 'p1',
      name: 'Client X',
      colorHex: '#5B8DEF',
      archived: false,
      billable: true,
      hourlyRateCents: 10000,
      currency: 'EUR',
      createdAt: now,
      updatedAt: now,
    );
    final entry = TimeEntry(
      id: 'e1',
      projectId: 'p1',
      description: 'Design review',
      startAt: DateTime.utc(2026, 7, 7, 9),
      endAt: DateTime.utc(2026, 7, 7, 10, 30),
      source: 'manual',
      deviceId: 'dev_a',
      createdAt: now,
      updatedAt: now,
      totalPausedSeconds: 0,
    );

    final csv = entriesToCsv([entry], [project], l10n: l10n);
    final lines = csv.trim().split('\r\n');

    expect(lines, hasLength(2));
    // Regression guard: the German header row must stay byte-identical to the
    // pre-localization output.
    expect(
      lines[0],
      'Datum,Start,Ende,Dauer (Std),Projekt,Beschreibung,Abrechenbar,Betrag,Währung',
    );
    expect(lines[1], contains('Client X'));
    expect(lines[1], contains('Design review'));
    expect(lines[1], contains('1.50')); // 1h30m
    expect(lines[1], contains('150.00')); // 1.5h * 100.00/hr
  });

  test('a still-running entry (no endAt) is skipped', () {
    final now = DateTime.utc(2026, 7, 1);
    final running = TimeEntry(
      id: 'e1',
      startAt: DateTime.utc(2026, 7, 7, 9),
      source: 'manual',
      deviceId: 'dev_a',
      createdAt: now,
      updatedAt: now,
      totalPausedSeconds: 0,
    );

    final csv = entriesToCsv([running], const [], l10n: l10n);

    expect(csv.trim().split('\r\n'), hasLength(1)); // header only
  });

  test('entriesToCsv excludes paused time from the exported hours', () {
    final now = DateTime.utc(2026, 7, 1);
    final project = Project(
      id: 'p1',
      name: 'Client X',
      colorHex: '#5B8DEF',
      archived: false,
      billable: true,
      hourlyRateCents: 10000,
      currency: 'EUR',
      createdAt: now,
      updatedAt: now,
    );
    final entry = TimeEntry(
      id: 'e1',
      projectId: 'p1',
      description: 'Design review',
      startAt: DateTime.utc(2026, 7, 7, 9),
      endAt: DateTime.utc(2026, 7, 7, 11), // 2h wall-clock
      totalPausedSeconds: 30 * 60, // 30 minutes paused
      source: 'manual',
      deviceId: 'dev_a',
      createdAt: now,
      updatedAt: now,
    );

    final csv = entriesToCsv([entry], [project], l10n: l10n);
    final lines = csv.trim().split('\r\n');

    expect(lines[1], contains('1.50')); // 2h - 30min = 1.5h
  });

  test('entriesToCsv honors the given date/time format styles', () {
    final now = DateTime.utc(2026, 7, 1);
    final entry = TimeEntry(
      id: 'e1',
      startAt: DateTime.utc(2026, 7, 7, 9),
      endAt: DateTime.utc(2026, 7, 7, 10, 30),
      source: 'manual',
      deviceId: 'dev_a',
      createdAt: now,
      updatedAt: now,
      totalPausedSeconds: 0,
    );

    final csv = entriesToCsv(
      [entry],
      const [],
      l10n: l10n,
      dateFormatStyle: DateFormatStyle.de,
      timeFormatStyle: TimeFormatStyle.h12,
    );
    final row = csv.trim().split('\r\n')[1];

    // dd.MM.yyyy shape, not the default yyyy-MM-dd — asserted structurally
    // (not against exact digits) since the entry's local date/time depends
    // on the machine running the test.
    expect(row, matches(RegExp(r'\d{2}\.\d{2}\.\d{4}')));
    // 12h style always appends AM/PM, unlike the default 24h style.
    expect(row, anyOf(contains('AM'), contains('PM')));
  });

  test('entriesToCsv defaults to ISO date / 24h time when no style is given', () {
    final now = DateTime.utc(2026, 7, 1);
    final entry = TimeEntry(
      id: 'e1',
      startAt: DateTime.utc(2026, 7, 7, 9),
      endAt: DateTime.utc(2026, 7, 7, 10, 30),
      source: 'manual',
      deviceId: 'dev_a',
      createdAt: now,
      updatedAt: now,
      totalPausedSeconds: 0,
    );

    final csv = entriesToCsv([entry], const [], l10n: l10n);
    final row = csv.trim().split('\r\n')[1];

    expect(row, matches(RegExp(r'\d{4}-\d{2}-\d{2}')));
    expect(row, isNot(anyOf(contains('AM'), contains('PM'))));
  });
}
