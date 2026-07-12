import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/features/jira/http_jira_client.dart';
import 'package:hickory/features/jira/jira_client.dart';
import 'package:hickory/features/jira/jira_credentials_store.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  const credentials = JiraCredentials(
    baseUrl: 'https://example.atlassian.net',
    email: 'me@example.com',
    apiToken: 'token-123',
  );

  test('testConnection returns true on HTTP 200', () async {
    final client = HttpJiraClient(
      credentials: credentials,
      httpClient: MockClient((request) async {
        expect(request.url.path, '/rest/api/2/myself');
        expect(request.headers['Authorization'], startsWith('Basic '));
        return http.Response('{}', 200);
      }),
    );

    expect(await client.testConnection(), isTrue);
  });

  test('testConnection returns false on HTTP 401', () async {
    final client = HttpJiraClient(
      credentials: credentials,
      httpClient: MockClient((request) async => http.Response('{}', 401)),
    );

    expect(await client.testConnection(), isFalse);
  });

  test('createWorklog posts the expected body and returns the new id', () async {
    late Map<String, dynamic> sentBody;
    final client = HttpJiraClient(
      credentials: credentials,
      httpClient: MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/rest/api/2/issue/PROJ-1/worklog');
        sentBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(jsonEncode({'id': '10050'}), 201);
      }),
    );

    final id = await client.createWorklog(
      issueKey: 'PROJ-1',
      timeSpent: const Duration(hours: 1, minutes: 30),
      startedAt: DateTime.utc(2026, 7, 7, 9, 0, 0),
      comment: 'Design review',
    );

    expect(id, '10050');
    expect(sentBody['timeSpentSeconds'], 5400);
    expect(sentBody['started'], '2026-07-07T09:00:00.000+0000');
    expect(sentBody['comment'], 'Design review');
  });

  test('createWorklog throws JiraApiException on a non-2xx response', () async {
    final client = HttpJiraClient(
      credentials: credentials,
      httpClient: MockClient((request) async => http.Response('not found', 404)),
    );

    expect(
      () => client.createWorklog(
        issueKey: 'PROJ-1',
        timeSpent: const Duration(minutes: 30),
        startedAt: DateTime.utc(2026, 7, 7),
      ),
      throwsA(isA<JiraApiException>()),
    );
  });

  test('updateWorklog puts to the worklog id path', () async {
    final client = HttpJiraClient(
      credentials: credentials,
      httpClient: MockClient((request) async {
        expect(request.method, 'PUT');
        expect(request.url.path, '/rest/api/2/issue/PROJ-1/worklog/10050');
        return http.Response('{}', 200);
      }),
    );

    await client.updateWorklog(
      issueKey: 'PROJ-1',
      worklogId: '10050',
      timeSpent: const Duration(hours: 1),
      startedAt: DateTime.utc(2026, 7, 7, 9),
    );
  });

  test('deleteWorklog treats 404 as success', () async {
    final client = HttpJiraClient(
      credentials: credentials,
      httpClient: MockClient((request) async {
        expect(request.method, 'DELETE');
        return http.Response('', 404);
      }),
    );

    await client.deleteWorklog(issueKey: 'PROJ-1', worklogId: '10050');
  });

  test('deleteWorklog throws on other error codes', () async {
    final client = HttpJiraClient(
      credentials: credentials,
      httpClient: MockClient((request) async => http.Response('', 500)),
    );

    expect(
      () => client.deleteWorklog(issueKey: 'PROJ-1', worklogId: '10050'),
      throwsA(isA<JiraApiException>()),
    );
  });

  test('searchIssues returns an empty list for a blank query without a request', () async {
    final client = HttpJiraClient(
      credentials: credentials,
      httpClient: MockClient((request) async => fail('should not be called')),
    );

    expect(await client.searchIssues('  '), isEmpty);
  });

  test('searchIssues parses issues out of every section', () async {
    final client = HttpJiraClient(
      credentials: credentials,
      httpClient: MockClient((request) async {
        expect(request.url.queryParameters['query'], 'PROJ');
        return http.Response(
          jsonEncode({
            'sections': [
              {
                'id': 'cs',
                'issues': [
                  {'key': 'PROJ-1', 'summaryText': 'First issue'},
                  {'key': 'PROJ-2', 'summaryText': 'Second issue'},
                ],
              },
            ],
          }),
          200,
        );
      }),
    );

    final results = await client.searchIssues('PROJ');

    expect(results, hasLength(2));
    expect(results.first.key, 'PROJ-1');
    expect(results.first.summary, 'First issue');
  });
}
