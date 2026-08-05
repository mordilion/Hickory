/// Personio API credentials needed to authenticate and identify the user's
/// own employee record.
class PersonioCredentials {
  const PersonioCredentials({
    required this.clientId,
    required this.clientSecret,
    required this.employeeId,
  });

  final String clientId;
  final String clientSecret;
  final String employeeId;
}

/// Reads/writes the Personio connection details this device uses to talk to
/// Personio. Deliberately per-device and never synced -- same reasoning as
/// JiraCredentialsStore: secrets must not enter the synced event log.
abstract class PersonioCredentialsStore {
  Future<PersonioCredentials?> read();
  Future<void> write(PersonioCredentials credentials);
  Future<void> clear();
}
