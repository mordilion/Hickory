import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'personio_credentials_store.dart';

class SecurePersonioCredentialsStore implements PersonioCredentialsStore {
  SecurePersonioCredentialsStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _clientIdKey = 'personio_client_id';
  static const _clientSecretKey = 'personio_client_secret';
  static const _employeeIdKey = 'personio_employee_id';

  @override
  Future<PersonioCredentials?> read() async {
    final clientId = await _storage.read(key: _clientIdKey);
    final clientSecret = await _storage.read(key: _clientSecretKey);
    final employeeId = await _storage.read(key: _employeeIdKey);
    if (clientId == null || clientSecret == null || employeeId == null) return null;
    return PersonioCredentials(clientId: clientId, clientSecret: clientSecret, employeeId: employeeId);
  }

  @override
  Future<void> write(PersonioCredentials credentials) async {
    await _storage.write(key: _clientIdKey, value: credentials.clientId);
    await _storage.write(key: _clientSecretKey, value: credentials.clientSecret);
    await _storage.write(key: _employeeIdKey, value: credentials.employeeId);
  }

  @override
  Future<void> clear() async {
    await _storage.delete(key: _clientIdKey);
    await _storage.delete(key: _clientSecretKey);
    await _storage.delete(key: _employeeIdKey);
  }
}
