/// Jira Cloud connection details needed to call the REST API.
class JiraCredentials {
  const JiraCredentials({required this.baseUrl, required this.email, required this.apiToken});

  final String baseUrl;
  final String email;
  final String apiToken;
}

/// Reads/writes the Jira connection details this device uses to talk to
/// Jira. Deliberately per-device and never synced — see the design doc for
/// why secrets must not enter the synced event log.
abstract class JiraCredentialsStore {
  Future<JiraCredentials?> read();
  Future<void> write(JiraCredentials credentials);
  Future<void> clear();
}
