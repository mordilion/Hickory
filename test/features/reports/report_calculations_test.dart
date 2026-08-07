import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/data/drift/database.dart';
import 'package:hickory/features/reports/report_calculations.dart';
import 'package:hickory/features/reports/report_view_state.dart';

Project _project({
  required String id,
  required String name,
  bool billable = true,
  int? hourlyRateCents,
  String currency = 'EUR',
}) {
  final now = DateTime.utc(2026, 7, 1);
  return Project(
    id: id,
    name: name,
    colorHex: '#5B8DEF',
    archived: false,
    billable: billable,
    hourlyRateCents: hourlyRateCents,
    currency: currency,
    createdAt: now,
    updatedAt: now,
  );
}

TimeEntry _entry({
  required String id,
  String? projectId,
  required DateTime startAt,
  required DateTime endAt,
  String? description,
  bool? billableOverride,
}) {
  final now = DateTime.utc(2026, 7, 1);
  return TimeEntry(
    id: id,
    projectId: projectId,
    description: description,
    startAt: startAt,
    endAt: endAt,
    source: 'manual',
    deviceId: 'dev_a',
    createdAt: now,
    updatedAt: now,
    totalPausedSeconds: 0,
    billableOverride: billableOverride,
  );
}

void main() {
  group('totalsByProject', () {
    test('sums duration per project and computes a billable amount', () {
      final billableProject = _project(id: 'p1', name: 'Client X', hourlyRateCents: 10000);
      final entries = [
        _entry(
          id: 'e1',
          projectId: 'p1',
          startAt: DateTime.utc(2026, 7, 7, 9),
          endAt: DateTime.utc(2026, 7, 7, 10), // 1h
        ),
        _entry(
          id: 'e2',
          projectId: 'p1',
          startAt: DateTime.utc(2026, 7, 7, 11),
          endAt: DateTime.utc(2026, 7, 7, 11, 30), // 30min
        ),
      ];

      final totals = totalsByProject(entries, [billableProject]);

      expect(totals, hasLength(1));
      expect(totals.single.duration, const Duration(hours: 1, minutes: 30));
      // 1.5h * 100.00/hr = 150.00 => 15000 cents.
      expect(totals.single.amountCents, 15000);
      expect(totals.single.currency, 'EUR');
    });

    test('entries with no project are grouped under "Kein Projekt" with no amount', () {
      final entries = [
        _entry(
          id: 'e1',
          projectId: null,
          startAt: DateTime.utc(2026, 7, 7, 9),
          endAt: DateTime.utc(2026, 7, 7, 9, 45),
        ),
      ];

      final totals = totalsByProject(entries, const []);

      expect(totals.single.projectId, isNull);
      expect(totals.single.projectName, 'Kein Projekt');
      expect(totals.single.amountCents, isNull);
    });

    test('a non-billable project never gets an amount even with an hourly rate', () {
      final project = _project(
        id: 'p1',
        name: 'Internal',
        billable: false,
        hourlyRateCents: 10000,
      );
      final entries = [
        _entry(
          id: 'e1',
          projectId: 'p1',
          startAt: DateTime.utc(2026, 7, 7, 9),
          endAt: DateTime.utc(2026, 7, 7, 10),
        ),
      ];

      final totals = totalsByProject(entries, [project]);

      expect(totals.single.billable, isFalse);
      expect(totals.single.amountCents, isNull);
    });

    test('a still-running entry (no endAt) is excluded', () {
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

      expect(totalsByProject([running], const []), isEmpty);
    });

    test('paused time is excluded from the summed duration', () {
      final entries = [
        TimeEntry(
          id: 'e1',
          projectId: 'p1',
          startAt: DateTime.utc(2026, 7, 7, 9),
          endAt: DateTime.utc(2026, 7, 7, 11), // 2h wall-clock
          totalPausedSeconds: 20 * 60, // 20 minutes paused
          source: 'manual',
          deviceId: 'dev_a',
          createdAt: DateTime.utc(2026, 7, 1),
          updatedAt: DateTime.utc(2026, 7, 1),
        ),
      ];

      final totals = totalsByProject(entries, [
        _project(id: 'p1', name: 'Client X'),
      ]);

      expect(totals.single.duration, const Duration(hours: 1, minutes: 40));
    });

    test('results are sorted by duration, longest first', () {
      final entries = [
        _entry(
          id: 'short',
          projectId: 'p_short',
          startAt: DateTime.utc(2026, 7, 7, 9),
          endAt: DateTime.utc(2026, 7, 7, 9, 15),
        ),
        _entry(
          id: 'long',
          projectId: 'p_long',
          startAt: DateTime.utc(2026, 7, 7, 10),
          endAt: DateTime.utc(2026, 7, 7, 12),
        ),
      ];

      final totals = totalsByProject(entries, [
        _project(id: 'p_short', name: 'Short'),
        _project(id: 'p_long', name: 'Long'),
      ]);

      expect(totals.map((t) => t.projectName), ['Long', 'Short']);
    });
  });

  group('totalsByDay', () {
    test('sums durations that fall on the same local calendar day', () {
      final sameDayStart1 = DateTime.utc(2026, 7, 7, 9);
      final sameDayStart2 = DateTime.utc(2026, 7, 7, 14);
      final otherDayStart = DateTime.utc(2026, 7, 8, 9);
      final entries = [
        _entry(id: 'e1', startAt: sameDayStart1, endAt: DateTime.utc(2026, 7, 7, 10)),
        _entry(id: 'e2', startAt: sameDayStart2, endAt: DateTime.utc(2026, 7, 7, 14, 30)),
        _entry(id: 'e3', startAt: otherDayStart, endAt: DateTime.utc(2026, 7, 8, 9, 45)),
      ];

      final totals = totalsByDay(entries);

      // Derive the expected keys the same way the implementation does
      // (local calendar day), so this test is robust to the runner's
      // timezone instead of assuming UTC.
      DateTime localDay(DateTime utc) {
        final local = utc.toLocal();
        return DateTime(local.year, local.month, local.day);
      }

      expect(totals.length, 2);
      expect(totals[localDay(sameDayStart1)], const Duration(hours: 1, minutes: 30));
      expect(totals[localDay(otherDayStart)], const Duration(minutes: 45));
    });
  });

  group('filterEntries', () {
    final billableProject = _project(id: 'p1', name: 'Billable Co');
    final nonBillableProject = _project(id: 'p2', name: 'Internal', billable: false);
    final projects = [billableProject, nonBillableProject];

    test('returns entries unchanged when no filters are active', () {
      final entries = [
        _entry(
          id: 'e1',
          projectId: 'p1',
          startAt: DateTime.utc(2026, 7, 7, 9),
          endAt: DateTime.utc(2026, 7, 7, 10),
        ),
      ];
      final result =
          filterEntries(entries, projects, projectIds: {}, billableFilter: BillableFilter.all);
      expect(result, entries);
    });

    test('project filter excludes non-matching and no-project entries', () {
      final entries = [
        _entry(
          id: 'e1',
          projectId: 'p1',
          startAt: DateTime.utc(2026, 7, 7, 9),
          endAt: DateTime.utc(2026, 7, 7, 10),
        ),
        _entry(
          id: 'e2',
          projectId: 'p2',
          startAt: DateTime.utc(2026, 7, 7, 9),
          endAt: DateTime.utc(2026, 7, 7, 10),
        ),
        _entry(
          id: 'e3',
          startAt: DateTime.utc(2026, 7, 7, 9),
          endAt: DateTime.utc(2026, 7, 7, 10),
        ),
      ];
      final result = filterEntries(
        entries,
        projects,
        projectIds: {'p1'},
        billableFilter: BillableFilter.all,
      );
      expect(result.map((e) => e.id), ['e1']);
    });

    test('billableOnly uses the project billable flag when no override is set', () {
      final entries = [
        _entry(
          id: 'e1',
          projectId: 'p1',
          startAt: DateTime.utc(2026, 7, 7, 9),
          endAt: DateTime.utc(2026, 7, 7, 10),
        ),
        _entry(
          id: 'e2',
          projectId: 'p2',
          startAt: DateTime.utc(2026, 7, 7, 9),
          endAt: DateTime.utc(2026, 7, 7, 10),
        ),
      ];
      final result = filterEntries(
        entries,
        projects,
        projectIds: {},
        billableFilter: BillableFilter.billableOnly,
      );
      expect(result.map((e) => e.id), ['e1']);
    });

    test('nonBillableOnly uses the project billable flag when no override is set', () {
      final entries = [
        _entry(
          id: 'e1',
          projectId: 'p1',
          startAt: DateTime.utc(2026, 7, 7, 9),
          endAt: DateTime.utc(2026, 7, 7, 10),
        ),
        _entry(
          id: 'e2',
          projectId: 'p2',
          startAt: DateTime.utc(2026, 7, 7, 9),
          endAt: DateTime.utc(2026, 7, 7, 10),
        ),
      ];
      final result = filterEntries(
        entries,
        projects,
        projectIds: {},
        billableFilter: BillableFilter.nonBillableOnly,
      );
      expect(result.map((e) => e.id), ['e2']);
    });

    test('billableOverride takes precedence over the project billable flag', () {
      final entries = [
        // Billable project, but this entry overrides to non-billable.
        _entry(
          id: 'e1',
          projectId: 'p1',
          startAt: DateTime.utc(2026, 7, 7, 9),
          endAt: DateTime.utc(2026, 7, 7, 10),
          billableOverride: false,
        ),
        // Non-billable project, but this entry overrides to billable.
        _entry(
          id: 'e2',
          projectId: 'p2',
          startAt: DateTime.utc(2026, 7, 7, 9),
          endAt: DateTime.utc(2026, 7, 7, 10),
          billableOverride: true,
        ),
      ];
      final billableOnly = filterEntries(
        entries,
        projects,
        projectIds: {},
        billableFilter: BillableFilter.billableOnly,
      );
      expect(billableOnly.map((e) => e.id), ['e2']);
      final nonBillableOnly = filterEntries(
        entries,
        projects,
        projectIds: {},
        billableFilter: BillableFilter.nonBillableOnly,
      );
      expect(nonBillableOnly.map((e) => e.id), ['e1']);
    });

    test('combines project and billable filters', () {
      final entries = [
        _entry(
          id: 'e1',
          projectId: 'p1',
          startAt: DateTime.utc(2026, 7, 7, 9),
          endAt: DateTime.utc(2026, 7, 7, 10),
        ),
        _entry(
          id: 'e2',
          projectId: 'p1',
          startAt: DateTime.utc(2026, 7, 7, 9),
          endAt: DateTime.utc(2026, 7, 7, 10),
          billableOverride: false,
        ),
      ];
      final result = filterEntries(
        entries,
        projects,
        projectIds: {'p1'},
        billableFilter: BillableFilter.billableOnly,
      );
      expect(result.map((e) => e.id), ['e1']);
    });
  });
}
