import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/core/di/app_settings_provider.dart';
import 'package:hickory/core/di/jira_providers.dart';
import 'package:hickory/data/drift/database.dart';
import 'package:hickory/features/entries/entries_list.dart';
import 'package:hickory/features/projects/projects_providers.dart';
import 'package:hickory/features/timer/timer_providers.dart';
import 'package:hickory/l10n/app_localizations.dart';

TimeEntry _entry({required String id, required DateTime startAt, required DateTime endAt}) {
  final now = DateTime.utc(2026, 1, 1);
  return TimeEntry(
    id: id,
    projectId: null,
    description: 'Entry $id',
    startAt: startAt,
    endAt: endAt,
    pausedAt: null,
    totalPausedSeconds: 0,
    billableOverride: null,
    source: 'manual',
    deviceId: 'device-1',
    jiraTicketKey: null,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  Widget makeApp(List<TimeEntry> entries) => ProviderScope(
        overrides: [
          allEntriesProvider.overrideWith((ref) => Stream.value(entries)),
          activeProjectsProvider.overrideWith((ref) => Stream.value(const [])),
          jiraWorklogsByEntryIdProvider.overrideWith((ref) => Stream.value(const {})),
          appSettingsProvider.overrideWith(
            (ref) => Stream.value(
              AppSettingsRow(
                id: 'default',
                dateFormat: 'iso',
                timeFormat: '24h',
                quickAddDurationsMinutes: '15,30,45,60',
                updatedAt: DateTime.utc(2026, 1, 1),
              ),
            ),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: const Scaffold(body: EntriesList()),
        ),
      );

  testWidgets('groups entries under Today/Yesterday headers with totals', (tester) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day, 9);
    final yesterday = today.subtract(const Duration(days: 1));
    await tester.pumpWidget(
      makeApp([
        _entry(id: '1', startAt: today, endAt: today.add(const Duration(hours: 1))),
        _entry(id: '2', startAt: yesterday, endAt: yesterday.add(const Duration(minutes: 30))),
      ]),
    );
    await tester.pumpAndSettle();

    // Match the full header text ("Today · 01:00:00") rather than just the
    // duration substring: with a single entry per day, the day total equals
    // that entry's own duration, so a substring match on the duration alone
    // would also match the entry row's trailing duration text.
    expect(find.text('Today · 01:00:00'), findsOneWidget);
    expect(find.text('Yesterday · 00:30:00'), findsOneWidget);
  });

  testWidgets('shows the empty state when there are no finished entries', (tester) async {
    await tester.pumpWidget(makeApp(const []));
    await tester.pumpAndSettle();
    expect(find.text('No entries yet.'), findsOneWidget);
  });
}
