import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hickory/features/personio/http_personio_client.dart';
import 'package:hickory/features/personio/personio_client.dart';
import 'package:hickory/features/personio/personio_credentials_store.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  const credentials = PersonioCredentials(
    clientId: 'client-123',
    clientSecret: 'secret-456',
    employeeId: '789',
  );

  http.Response tokenResponse({int expiresIn = 3600}) => http.Response(
        jsonEncode({'access_token': 'token-abc', 'token_type': 'Bearer', 'expires_in': expiresIn}),
        200,
      );

  test('testConnection returns true when a token can be obtained', () async {
    final client = HttpPersonioClient(
      credentials: credentials,
      httpClient: MockClient((request) async {
        expect(request.url.path, '/v2/auth/token');
        return tokenResponse();
      }),
    );

    expect(await client.testConnection(), isTrue);
  });

  test('testConnection returns false when authentication fails', () async {
    final client = HttpPersonioClient(
      credentials: credentials,
      httpClient: MockClient((request) async => http.Response('{}', 400)),
    );

    expect(await client.testConnection(), isFalse);
  });

  test('createAttendance obtains a token, then posts the expected body', () async {
    late Map<String, dynamic> sentBody;
    var tokenRequests = 0;
    final client = HttpPersonioClient(
      credentials: credentials,
      httpClient: MockClient((request) async {
        if (request.url.path == '/v2/auth/token') {
          tokenRequests++;
          expect(request.headers['Content-Type'], contains('application/x-www-form-urlencoded'));
          return tokenResponse();
        }
        expect(request.method, 'POST');
        expect(request.url.path, '/v2/attendance-periods');
        expect(request.url.queryParameters['skip_approval'], 'true');
        expect(request.headers['Authorization'], 'Bearer token-abc');
        sentBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(jsonEncode({'id': 'period-1'}), 201);
      }),
    );

    final id = await client.createAttendance(
      start: DateTime.utc(2026, 7, 7, 9),
      end: DateTime.utc(2026, 7, 7, 10),
      comment: 'Design review',
    );

    expect(id, 'period-1');
    expect(tokenRequests, 1);
    expect(sentBody['person'], {'id': '789'});
    expect(sentBody['type'], 'WORK');
    expect(sentBody['comment'], 'Design review');
  });

  test('createAttendance throws PersonioApiException on a non-201 response', () async {
    final client = HttpPersonioClient(
      credentials: credentials,
      httpClient: MockClient((request) async {
        if (request.url.path == '/v2/auth/token') return tokenResponse();
        return http.Response('bad request', 400);
      }),
    );

    expect(
      () => client.createAttendance(
        start: DateTime.utc(2026, 7, 7, 9),
        end: DateTime.utc(2026, 7, 7, 10),
      ),
      throwsA(isA<PersonioApiException>()),
    );
  });

  test('a cached token is reused across multiple calls instead of re-authenticating', () async {
    var tokenRequests = 0;
    final client = HttpPersonioClient(
      credentials: credentials,
      httpClient: MockClient((request) async {
        if (request.url.path == '/v2/auth/token') {
          tokenRequests++;
          return tokenResponse();
        }
        return http.Response(jsonEncode({'id': 'period-1'}), 201);
      }),
    );

    await client.createAttendance(start: DateTime.utc(2026, 7, 7, 9), end: DateTime.utc(2026, 7, 7, 10));
    await client.createAttendance(start: DateTime.utc(2026, 7, 8, 9), end: DateTime.utc(2026, 7, 8, 10));

    expect(tokenRequests, 1);
  });

  test('a token whose expiry falls within the safety margin is refreshed', () async {
    var tokenRequests = 0;
    final client = HttpPersonioClient(
      credentials: credentials,
      httpClient: MockClient((request) async {
        if (request.url.path == '/v2/auth/token') {
          tokenRequests++;
          // expiresIn (1s) is smaller than the client's safety margin, so
          // the cached token is already considered unsafe the moment it's
          // stored -- the very next call must re-authenticate.
          return tokenResponse(expiresIn: 1);
        }
        return http.Response(jsonEncode({'id': 'period-1'}), 201);
      }),
    );

    await client.createAttendance(start: DateTime.utc(2026, 7, 7, 9), end: DateTime.utc(2026, 7, 7, 10));
    await client.createAttendance(start: DateTime.utc(2026, 7, 8, 9), end: DateTime.utc(2026, 7, 8, 10));

    expect(tokenRequests, 2);
  });

  test('updateAttendance patches the period id path', () async {
    final client = HttpPersonioClient(
      credentials: credentials,
      httpClient: MockClient((request) async {
        if (request.url.path == '/v2/auth/token') return tokenResponse();
        expect(request.method, 'PATCH');
        expect(request.url.path, '/v2/attendance-periods/period-1');
        return http.Response('{}', 200);
      }),
    );

    await client.updateAttendance(
      periodId: 'period-1',
      start: DateTime.utc(2026, 7, 7, 9),
      end: DateTime.utc(2026, 7, 7, 10),
    );
  });

  test('deleteAttendance treats 404 as success', () async {
    final client = HttpPersonioClient(
      credentials: credentials,
      httpClient: MockClient((request) async {
        if (request.url.path == '/v2/auth/token') return tokenResponse();
        expect(request.method, 'DELETE');
        return http.Response('', 404);
      }),
    );

    await client.deleteAttendance(periodId: 'period-1');
  });

  test('deleteAttendance throws on other error codes', () async {
    final client = HttpPersonioClient(
      credentials: credentials,
      httpClient: MockClient((request) async {
        if (request.url.path == '/v2/auth/token') return tokenResponse();
        return http.Response('', 500);
      }),
    );

    expect(
      () => client.deleteAttendance(periodId: 'period-1'),
      throwsA(isA<PersonioApiException>()),
    );
  });
}
