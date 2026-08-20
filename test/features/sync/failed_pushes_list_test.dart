import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/core/format/date_format.dart';
import 'package:hickory/core/theme/app_theme.dart';
import 'package:hickory/data/drift/database.dart';
import 'package:hickory/features/sync/failed_pushes.dart';
import 'package:hickory/features/sync/failed_pushes_list.dart';
import 'package:hickory/l10n/app_localizations.dart';

TimeEntry _entry({
  required String id,
  required DateTime startAt,
  String? description,
}) => TimeEntry(
  id: id,
  projectId: null,
  description: description,
  startAt: startAt,
  endAt: startAt.add(const Duration(hours: 1)),
  pausedAt: null,
  totalPausedSeconds: 0,
  billableOverride: null,
  source: 'manual',
  deviceId: 'device-1',
  jiraTicketKey: null,
  createdAt: DateTime.utc(2026, 1, 1),
  updatedAt: DateTime.utc(2026, 1, 1),
);

void main() {
  Widget makeApp(
    List<FailedPush> failed, {
    void Function(TimeEntry)? onTapEntry,
  }) => MaterialApp(
    theme: AppTheme.light,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en'),
    home: Scaffold(
      body: FailedPushesList(
        failed: failed,
        fallbackError: 'Jira booking failed',
        dateStyle: DateFormatStyle.iso,
        localeName: 'en',
        onTapEntry: onTapEntry ?? (_) {},
      ),
    ),
  );

  testWidgets('names each failed entry, its date and its stored error', (tester) async {
    await tester.pumpWidget(
      makeApp([
        (
          entry: _entry(
            id: '1',
            startAt: DateTime(2026, 8, 20, 9),
            description: 'Refactoring',
          ),
          error: 'Issue does not exist',
        ),
      ]),
    );
    await tester.pumpAndSettle();

    expect(find.text('Refactoring'), findsOneWidget);
    expect(find.textContaining('2026-08-20'), findsOneWidget);
    expect(find.textContaining('Issue does not exist'), findsOneWidget);
  });

  testWidgets('falls back to the generic message when none was stored', (tester) async {
    await tester.pumpWidget(
      makeApp([
        (entry: _entry(id: '1', startAt: DateTime(2026, 8, 20, 9)), error: null),
      ]),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Jira booking failed'), findsOneWidget);
  });

  testWidgets('opens the entry it was tapped on', (tester) async {
    final tapped = <String>[];
    await tester.pumpWidget(
      makeApp(
        [
          (
            entry: _entry(
              id: '1',
              startAt: DateTime(2026, 8, 20, 9),
              description: 'Refactoring',
            ),
            error: 'Boom',
          ),
        ],
        onTapEntry: (entry) => tapped.add(entry.id),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Refactoring'));
    await tester.pumpAndSettle();

    expect(tapped, ['1']);
  });

  testWidgets('renders nothing at all when no push failed', (tester) async {
    await tester.pumpWidget(makeApp(const []));
    await tester.pumpAndSettle();

    // Not an empty-state message: the Sync tab must stay quiet when there is
    // nothing wrong.
    expect(find.byType(ListTile), findsNothing);
    expect(find.byType(SizedBox), findsWidgets);
  });

  testWidgets('describes an entry that has no description', (tester) async {
    await tester.pumpWidget(
      makeApp([
        (entry: _entry(id: '1', startAt: DateTime(2026, 8, 20, 9)), error: 'Boom'),
      ]),
    );
    await tester.pumpAndSettle();

    expect(find.text('No description'), findsOneWidget);
  });
}
