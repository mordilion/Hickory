import 'dart:convert';

import 'package:http/http.dart' as http;

import 'personio_client.dart';
import 'personio_credentials_store.dart';

/// A cached OAuth2 access token plus the UTC instant it stops being safe to
/// use (see [HttpPersonioClient._safetyMargin] for why the raw expiry isn't
/// used verbatim).
class _CachedToken {
  const _CachedToken({required this.accessToken, required this.safeUntil});

  final String accessToken;
  final DateTime safeUntil;
}

class HttpPersonioClient implements PersonioClient {
  HttpPersonioClient({required this._credentials, http.Client? httpClient})
    : _httpClient = httpClient ?? http.Client();

  static const _baseUrl = 'https://api.personio.de';

  /// Re-authenticate this long before actual token expiry so a token that's
  /// valid when checked doesn't expire mid-request.
  static const _safetyMargin = Duration(seconds: 30);

  final PersonioCredentials _credentials;
  final http.Client _httpClient;
  _CachedToken? _cachedToken;

  @override
  Future<bool> testConnection() async {
    try {
      await _accessToken();
      return true;
    } on PersonioApiException {
      return false;
    }
  }

  @override
  Future<String> createAttendance({
    required DateTime start,
    required DateTime end,
    String? comment,
  }) async {
    final response = await _authorizedRequest(
      (headers) => _httpClient.post(
        Uri.parse('$_baseUrl/v2/attendance-periods?skip_approval=true'),
        headers: headers,
        body: jsonEncode(_attendanceBody(start: start, end: end, comment: comment)),
      ),
    );
    if (response.statusCode != 201) {
      throw PersonioApiException(
        'Failed to create attendance period (HTTP ${response.statusCode}).',
      );
    }
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    return decoded['id'] as String;
  }

  @override
  Future<void> updateAttendance({
    required String periodId,
    required DateTime start,
    required DateTime end,
    String? comment,
  }) async {
    final response = await _authorizedRequest(
      (headers) => _httpClient.patch(
        Uri.parse('$_baseUrl/v2/attendance-periods/$periodId?skip_approval=true'),
        headers: headers,
        body: jsonEncode(_attendanceBody(start: start, end: end, comment: comment)),
      ),
    );
    if (response.statusCode != 200) {
      throw PersonioApiException(
        'Failed to update attendance period $periodId (HTTP ${response.statusCode}).',
      );
    }
  }

  @override
  Future<void> deleteAttendance({required String periodId}) async {
    final response = await _authorizedRequest(
      (headers) => _httpClient.delete(
        Uri.parse('$_baseUrl/v2/attendance-periods/$periodId'),
        headers: headers,
      ),
    );
    if (response.statusCode != 204 && response.statusCode != 404) {
      throw PersonioApiException(
        'Failed to delete attendance period $periodId (HTTP ${response.statusCode}).',
      );
    }
  }

  Future<http.Response> _authorizedRequest(
    Future<http.Response> Function(Map<String, String> headers) send,
  ) async {
    final token = await _accessToken();
    return send({
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    });
  }

  Future<String> _accessToken() async {
    final cached = _cachedToken;
    if (cached != null && DateTime.now().toUtc().isBefore(cached.safeUntil)) {
      return cached.accessToken;
    }
    final response = await _httpClient.post(
      Uri.parse('$_baseUrl/v2/auth/token'),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'grant_type': 'client_credentials',
        'client_id': _credentials.clientId,
        'client_secret': _credentials.clientSecret,
      },
    );
    if (response.statusCode != 200) {
      throw PersonioApiException('Personio authentication failed (HTTP ${response.statusCode}).');
    }
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final accessToken = decoded['access_token'] as String;
    final expiresIn = (decoded['expires_in'] as num).toInt();
    final token = _CachedToken(
      accessToken: accessToken,
      safeUntil: DateTime.now().toUtc().add(Duration(seconds: expiresIn) - _safetyMargin),
    );
    _cachedToken = token;
    return token.accessToken;
  }

  Map<String, dynamic> _attendanceBody({
    required DateTime start,
    required DateTime end,
    String? comment,
  }) {
    return {
      'person': {'id': _credentials.employeeId},
      'type': 'WORK',
      'start': {'date_time': start.toUtc().toIso8601String()},
      'end': {'date_time': end.toUtc().toIso8601String()},
      if (comment != null && comment.isNotEmpty) 'comment': comment,
    };
  }
}
