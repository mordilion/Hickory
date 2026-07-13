/// One issue-search result, as returned by Jira's issue picker.
class JiraIssueSuggestion {
  const JiraIssueSuggestion({required this.key, required this.summary});

  final String key;
  final String summary;
}

/// Raised for any non-2xx Jira response, or for a search response Jira
/// couldn't parse. Carries a caller-safe message (no tokens, no full
/// response bodies) suitable for surfacing in the UI.
class JiraApiException implements Exception {
  JiraApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Talks to the Jira REST API for worklog booking. Implementations must
/// throw [JiraApiException] on failure — callers rely on that to decide
/// whether a push succeeded.
abstract class JiraClient {
  /// Returns true if the configured credentials can authenticate against
  /// Jira, false otherwise. Never throws for an auth failure — only for
  /// transport-level errors.
  Future<bool> testConnection();

  /// Creates a worklog on [issueKey] and returns the new worklog's id.
  Future<String> createWorklog({
    required String issueKey,
    required Duration timeSpent,
    required DateTime startedAt,
    String? comment,
  });

  Future<void> updateWorklog({
    required String issueKey,
    required String worklogId,
    required Duration timeSpent,
    required DateTime startedAt,
    String? comment,
  });

  /// Deleting a worklog that's already gone (404) is treated as success —
  /// the end state the caller wants is "no worklog", which already holds.
  Future<void> deleteWorklog({required String issueKey, required String worklogId});

  /// Empty query returns no results without calling the network.
  Future<List<JiraIssueSuggestion>> searchIssues(String query);
}
