import 'package:cursor_android/data/api_failure.dart';
import 'package:cursor_android/data/cursor_api_headers.dart';
import 'package:cursor_android/data/cursor_api_url.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fake session secret that must never appear in errors.
const String secret = 'session=top-secret-0123456789';

void main() {
  final Uri production = Uri.parse('https://cursor.com/');
  final Uri mock = Uri.parse('http://127.0.0.1:8080/');

  group('cookieAllowed', () {
    test('always allows https://cursor.com on port 443', () {
      for (final String url in <String>[
        'https://cursor.com/api/auth/me',
        'https://cursor.com:443/api',
      ]) {
        expect(
          cookieAllowed(
            url: Uri.parse(url),
            origin: mock,
            allowConfiguredOrigin: false,
          ),
          isTrue,
          reason: url,
        );
      }
    });

    test('allows the configured origin only when opted in', () {
      final Uri url = Uri.parse('http://127.0.0.1:8080/api');
      bool allowed(bool optIn) => cookieAllowed(
        url: url,
        origin: mock,
        allowConfiguredOrigin: optIn,
      );
      expect(allowed(false), isFalse);
      expect(allowed(true), isTrue);
    });

    test('rejects other origins, ports and http', () {
      for (final String url in <String>[
        'https://evil.example/',
        'http://cursor.com/',
        'https://cursor.com:8443/',
        'http://127.0.0.1:9090/',
      ]) {
        expect(
          cookieAllowed(
            url: Uri.parse(url),
            origin: mock,
            allowConfiguredOrigin: true,
          ),
          isFalse,
          reason: url,
        );
      }
    });
  });

  group('teamIdFromCookie', () {
    test('reads a non-blank team id', () {
      expect(teamIdFromCookie('a=b; portal-selected-team-id=42'), '42');
      expect(teamIdFromCookie('portal-selected-team-id= '), isNull);
      expect(teamIdFromCookie(secret), isNull);
    });
  });

  group('sessionHeaders', () {
    final Uri url = Uri.parse('https://cursor.com/api/auth/me');

    test('sends Cookie and Origin but never Authorization', () {
      final Map<String, String> headers = sessionHeaders(
        url: url,
        credential: secret,
        method: 'GET',
      );
      expect(headers['Cookie'], secret);
      expect(headers['Origin'], 'https://cursor.com');
      expect(headers['Accept'], 'application/json');
      final Iterable<String> names = headers.keys.map((k) => k.toLowerCase());
      expect(names, isNot(contains('authorization')));
      expect(headers.containsKey('x-csrf-token'), isFalse);
      expect(headers.containsKey('x-cursor-team-id'), isFalse);
    });

    test('adds the team id header when the cookie has one', () {
      final Map<String, String> headers = sessionHeaders(
        url: url,
        credential: '$secret; portal-selected-team-id=7',
        method: 'GET',
      );
      expect(headers['x-cursor-team-id'], '7');
    });

    test('sends the cookie csrf token on POST but not on GET', () {
      const String credential = '$secret; csrf-token=abc';
      Map<String, String> headers(String method) =>
          sessionHeaders(url: url, credential: credential, method: method);
      expect(headers('POST')['x-csrf-token'], 'abc');
      expect(headers('POST')['Cookie'], credential);
      expect(headers('GET').containsKey('x-csrf-token'), isFalse);
    });

    test('a fresh csrf token replaces the cookie entry', () {
      final Map<String, String> headers = sessionHeaders(
        url: url,
        credential: '$secret; csrf-token=old',
        csrfToken: 'new',
        method: 'POST',
      );
      expect(headers['Cookie'], '$secret; csrf-token=new');
      expect(headers['x-csrf-token'], 'new');
    });

    test('rejects control characters without echoing the secret', () {
      expect(
        () => sessionHeaders(
          url: url,
          credential: '$secret\r\nX-Injected: 1',
          method: 'GET',
        ),
        throwsA(
          isA<FormatException>().having(
            (FormatException e) => e.toString(),
            'message',
            isNot(contains('top-secret')),
          ),
        ),
      );
    });
  });

  group('buildApiUrl', () {
    test('encodes a slash inside one segment', () {
      final Uri built = buildApiUrl(
        webBase: production,
        segments: <String>['api', 'background-composer', 'unsafe/id'],
      );
      expect(
        built.toString(),
        'https://cursor.com/api/background-composer/unsafe%2Fid',
      );
      expect(built.pathSegments.last, 'unsafe/id');
    });

    test('keeps a base path and encodes query values', () {
      final Uri built = buildApiUrl(
        webBase: Uri.parse('http://127.0.0.1:8080/base/'),
        segments: <String>['api', 'usage-summary'],
        query: <String, String>{'q': 'a b', 'n': '1+1'},
      );
      expect(
        built.toString(),
        'http://127.0.0.1:8080/base/api/usage-summary?q=a%20b&n=1%2B1',
      );
    });

    test('resolves dot segments like OkHttp', () {
      final Uri built = buildApiUrl(
        webBase: production,
        segments: <String>['api', '.', '..', 'x'],
      );
      expect(built.toString(), 'https://cursor.com/x');
    });
  });

  test('ApiFailure toString carries no cookie material', () {
    const ApiFailure failure = ApiFailure(401, 'connection_required', '5');
    expect(failure.toString(), 'HTTP 401 · connection_required');
    expect(failure.toString(), isNot(contains('top-secret')));
    expect(failure.retryAfter, '5');
  });
}
