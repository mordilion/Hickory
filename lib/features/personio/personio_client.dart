/// Raised for any non-2xx Personio response, or a response Personio couldn't
/// parse. Carries a caller-safe message (no tokens, no full response bodies)
/// suitable for surfacing in the UI.
class PersonioApiException implements Exception {
  PersonioApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Talks to the Personio v2 API to push attendance periods. Implementations
/// must throw [PersonioApiException] on failure -- callers rely on that to
/// decide whether a push succeeded.
abstract class PersonioClient {
  /// Returns true if the configured credentials can authenticate against
  /// Personio, false otherwise. Never throws for an auth failure -- only for
  /// transport-level errors.
  Future<bool> testConnection();

  /// Creates a WORK attendance period and returns its Personio-assigned id.
  Future<String> createAttendance({
    required DateTime start,
    required DateTime end,
    String? comment,
  });

  Future<void> updateAttendance({
    required String periodId,
    required DateTime start,
    required DateTime end,
    String? comment,
  });

  /// Deleting a period that's already gone (404) is treated as success --
  /// the end state the caller wants is "no period", which already holds.
  Future<void> deleteAttendance({required String periodId});
}
