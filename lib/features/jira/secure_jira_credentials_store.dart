import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'jira_credentials_store.dart';

class SecureJiraCredentialsStore implements JiraCredentialsStore {
  SecureJiraCredentialsStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _baseUrlKey = 'jira_base_url';
  static const _emailKey = 'jira_email';
  static const _apiTokenKey = 'jira_api_token';

  @override
  Future<JiraCredentials?> read() async {
    final baseUrl = await _storage.read(key: _baseUrlKey);
    final email = await _storage.read(key: _emailKey);
    final apiToken = await _storage.read(key: _apiTokenKey);
    if (baseUrl == null || email == null || apiToken == null) return null;
    return JiraCredentials(baseUrl: baseUrl, email: email, apiToken: apiToken);
  }

  @override
  Future<void> write(JiraCredentials credentials) async {
    await _storage.write(key: _baseUrlKey, value: credentials.baseUrl);
    await _storage.write(key: _emailKey, value: credentials.email);
    await _storage.write(key: _apiTokenKey, value: credentials.apiToken);
  }

  @override
  Future<void> clear() async {
    await _storage.delete(key: _baseUrlKey);
    await _storage.delete(key: _emailKey);
    await _storage.delete(key: _apiTokenKey);
  }
}
