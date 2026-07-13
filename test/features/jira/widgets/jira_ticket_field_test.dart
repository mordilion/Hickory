import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/core/di/jira_providers.dart';
import 'package:hickory/features/jira/jira_client.dart';
import 'package:hickory/features/jira/widgets/jira_ticket_field.dart';
import 'package:hickory/l10n/app_localizations.dart';

/// Only [searchIssues] is exercised by this test — the other four methods
/// of [JiraClient] are irrelevant to JiraTicketField's autocomplete search
/// and are never called, so they throw if reached rather than being given
/// unused fake behavior.
class _FakeJiraClient implements JiraClient {
  @override
  Future<bool> testConnection() => throw UnimplementedError();

  @override
  Future<String> createWorklog({
    required String issueKey,
    required Duration timeSpent,
    required DateTime startedAt,
    String? comment,
  }) => throw UnimplementedError();

  @override
  Future<void> updateWorklog({
    required String issueKey,
    required String worklogId,
    required Duration timeSpent,
    required DateTime startedAt,
    String? comment,
  }) => throw UnimplementedError();

  @override
  Future<void> deleteWorklog({required String issueKey, required String worklogId}) =>
      throw UnimplementedError();

  @override
  Future<List<JiraIssueSuggestion>> searchIssues(String query) async {
    if (query.trim().isEmpty) return const [];
    return const [JiraIssueSuggestion(key: 'PROJ-1', summary: 'Fix the login flow')];
  }
}

void main() {
  Widget makeApp({required ValueChanged<String?> onChanged}) => ProviderScope(
        overrides: [jiraClientProvider.overrideWith((ref) async => _FakeJiraClient())],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: JiraTicketField(initialValue: null, onChanged: onChanged)),
        ),
      );

  testWidgets(
    'shows Jira search suggestions after typing and selecting one reports the key',
    (tester) async {
      String? selected;
      await tester.pumpWidget(makeApp(onChanged: (value) => selected = value));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'PROJ');
      // Advance past the 300ms debounce so optionsBuilder's Future resolves.
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(find.text('PROJ-1'), findsOneWidget);
      expect(find.text('Fix the login flow'), findsOneWidget);

      await tester.tap(find.text('PROJ-1'));
      await tester.pumpAndSettle();

      expect(selected, 'PROJ-1');
    },
  );
}
