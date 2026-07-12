import 'dart:convert';

import 'package:http/http.dart' as http;

import 'jira_client.dart';
import 'jira_credentials_store.dart';

class HttpJiraClient implements JiraClient {
  HttpJiraClient({required JiraCredentials credentials, http.Client? httpClient})
    : _credentials = credentials,
      _httpClient = httpClient ?? http.Client();

  final JiraCredentials _credentials;
  final http.Client _httpClient;

  @override
  Future<bool> testConnection() async {
    final response = await _httpClient.get(_uri('/myself'), headers: _headers);
    return response.statusCode == 200;
  }

  @override
  Future<String> createWorklog({
    required String issueKey,
    required Duration timeSpent,
    required DateTime startedAt,
    String? comment,
  }) async {
    final response = await _httpClient.post(
      _uri('/issue/$issueKey/worklog'),
      headers: _headers,
      body: jsonEncode(_worklogBody(timeSpent: timeSpent, startedAt: startedAt, comment: comment)),
    );
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw JiraApiException(
        'Failed to create worklog on $issueKey (HTTP ${response.statusCode}).',
      );
    }
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    return decoded['id'] as String;
  }

  @override
  Future<void> updateWorklog({
    required String issueKey,
    required String worklogId,
    required Duration timeSpent,
    required DateTime startedAt,
    String? comment,
  }) async {
    final response = await _httpClient.put(
      _uri('/issue/$issueKey/worklog/$worklogId'),
      headers: _headers,
      body: jsonEncode(_worklogBody(timeSpent: timeSpent, startedAt: startedAt, comment: comment)),
    );
    if (response.statusCode != 200) {
      throw JiraApiException(
        'Failed to update worklog $worklogId on $issueKey (HTTP ${response.statusCode}).',
      );
    }
  }

  @override
  Future<void> deleteWorklog({required String issueKey, required String worklogId}) async {
    final response = await _httpClient.delete(
      _uri('/issue/$issueKey/worklog/$worklogId'),
      headers: _headers,
    );
    if (response.statusCode != 204 && response.statusCode != 404) {
      throw JiraApiException(
        'Failed to delete worklog $worklogId on $issueKey (HTTP ${response.statusCode}).',
      );
    }
  }

  @override
  Future<List<JiraIssueSuggestion>> searchIssues(String query) async {
    if (query.trim().isEmpty) return const [];
    final response = await _httpClient.get(_uri('/issue/picker', {'query': query}), headers: _headers);
    if (response.statusCode != 200) {
      throw JiraApiException('Issue search failed (HTTP ${response.statusCode}).');
    }
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final sections = decoded['sections'] as List<dynamic>? ?? const [];
    return [
      for (final section in sections)
        for (final issue in (section as Map<String, dynamic>)['issues'] as List<dynamic>? ?? const [])
          JiraIssueSuggestion(
            key: (issue as Map<String, dynamic>)['key'] as String,
            summary: (issue['summaryText'] as String?) ?? '',
          ),
    ];
  }

  Uri _uri(String path, [Map<String, String>? query]) {
    final base = _credentials.baseUrl.endsWith('/')
        ? _credentials.baseUrl.substring(0, _credentials.baseUrl.length - 1)
        : _credentials.baseUrl;
    return Uri.parse('$base/rest/api/2$path').replace(queryParameters: query);
  }

  Map<String, String> get _headers {
    final basic = base64Encode(utf8.encode('${_credentials.email}:${_credentials.apiToken}'));
    return {
      'Authorization': 'Basic $basic',
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
  }

  Map<String, dynamic> _worklogBody({
    required Duration timeSpent,
    required DateTime startedAt,
    String? comment,
  }) {
    return {
      'timeSpentSeconds': timeSpent.inSeconds,
      'started': _formatStarted(startedAt),
      if (comment != null && comment.isNotEmpty) 'comment': comment,
    };
  }

  /// Jira's worklog `started` field requires its own bespoke format —
  /// `yyyy-MM-ddTHH:mm:ss.SSSZZZZ` with milliseconds always three digits and
  /// no colon in the offset (`+0000`, not `+00:00`) — incompatible with
  /// [DateTime.toIso8601String], hence built by hand.
  String _formatStarted(DateTime dateTime) {
    final utc = dateTime.toUtc();
    String two(int n) => n.toString().padLeft(2, '0');
    String three(int n) => n.toString().padLeft(3, '0');
    return '${utc.year}-${two(utc.month)}-${two(utc.day)}T${two(utc.hour)}:${two(utc.minute)}:'
        '${two(utc.second)}.${three(utc.millisecond)}+0000';
  }
}
