import 'dart:convert';
import 'dart:typed_data';

import 'package:cursor_android/data/api_failure.dart';
import 'package:cursor_android/data/cursor_api.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

const String fixtureCookie = 'session=fixture; csrf-token=old';
const Map<String, List<String>> noHeaders = <String, List<String>>{};
final Uri mockBase = Uri.parse('http://127.0.0.1:8080/');

/// A queued fake response.
class Reply {
  const Reply(this.body, {this.status = 200, this.headers = noHeaders});

  final String body;
  final int status;
  final Map<String, List<String>> headers;
}

/// One request as seen by the fake server, with lower-case header names.
class Seen {
  const Seen(this.method, this.uri, this.headers, this.body);

  final String method;
  final Uri uri;
  final Map<String, String> headers;
  final String body;
}

/// In-memory server that answers queued replies in order.
class FakeServer implements HttpClientAdapter {
  final List<Reply> replies = <Reply>[];
  final List<Seen> seen = <Seen>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final List<int> bytes = requestStream == null
        ? <int>[]
        : await requestStream.expand((Uint8List chunk) => chunk).toList();
    seen.add(
      Seen(
        options.method,
        options.uri,
        options.headers.map(
          (String name, dynamic value) =>
              MapEntry<String, String>(name.toLowerCase(), '$value'),
        ),
        utf8.decode(bytes),
      ),
    );
    final Reply reply = replies.removeAt(0);
    return ResponseBody.fromString(
      reply.body,
      reply.status,
      headers: reply.headers,
    );
  }

  @override
  void close({bool force = false}) {}
}

Future<ApiFailure> failureOf(Future<Object?> future) async {
  try {
    await future;
  } on ApiFailure catch (failure) {
    return failure;
  }
  fail('Expected an ApiFailure');
}

const Reply invalidCsrf = Reply(
  '{"error":{"code":"invalid_csrf_token"}}',
  status: 403,
);
const Reply freshCsrf = Reply(
  '{}',
  headers: <String, List<String>>{
    'set-cookie': <String>['csrf-token=fresh; Path=/'],
  },
);

void main() {
  late FakeServer server;
  late CursorApi api;

  setUp(() {
    server = FakeServer();
    api = CursorApi(
      cookie: () => fixtureCookie,
      webBase: mockBase,
      allowConfiguredOrigin: true,
      dio: Dio()..httpClientAdapter = server,
    );
  });

  test('sends the cookie, never Authorization, and encodes segments', () async {
    server.replies.addAll(const <Reply>[Reply('{}'), Reply('{}')]);
    await api.request('GET', <String>['api', 'auth', 'me']);
    await api.request('GET', <String>['v1', 'agents', 'unsafe/id']);
    expect(server.seen[0].headers['cookie'], contains('session=fixture'));
    expect(server.seen[0].uri.path, '/api/auth/me');
    expect(server.seen[0].body, isEmpty);
    expect(server.seen[1].uri.path, '/v1/agents/unsafe%2Fid');
    for (final Seen request in server.seen) {
      expect(request.headers.containsKey('authorization'), isFalse);
    }
  });

  test('a foreign origin is rejected before any network call', () async {
    int cookieReads = 0;
    final CursorApi blocked = CursorApi(
      cookie: () {
        cookieReads++;
        return 'session=secret-cookie';
      },
      webBase: mockBase,
      dio: Dio()..httpClientAdapter = server,
    );
    final ApiFailure failure = await failureOf(
      blocked.request('GET', <String>['api', 'auth', 'me']),
    );
    expect(failure.code, 'origin_rejected');
    expect(failure.toString(), isNot(contains('secret-cookie')));
    expect(server.seen, isEmpty);
    expect(cookieReads, 0);
  });

  test('a blank cookie requires a connection', () async {
    final CursorApi signedOut = CursorApi(
      cookie: () async => '  ',
      webBase: mockBase,
      allowConfiguredOrigin: true,
      dio: Dio()..httpClientAdapter = server,
    );
    final ApiFailure failure = await failureOf(
      signedOut.request('GET', <String>['api', 'auth', 'me']),
    );
    expect(failure.status, 401);
    expect(failure.code, 'connection_required');
    expect(server.seen, isEmpty);
  });

  test('a failure body never leaks the cookie', () async {
    server.replies.add(
      const Reply(
        '{"error":{"code":"request_failed"},"echo":"session=fixture"}',
        status: 500,
      ),
    );
    final ApiFailure failure = await failureOf(
      api.request('GET', <String>['api', 'auth', 'me']),
    );
    expect(failure.status, 500);
    expect(failure.toString(), isNot(contains('session=fixture')));
    expect(failure.toString(), isNot(contains('csrf-token')));
  });

  test('an error code that is not a plain token is dropped', () async {
    server.replies.add(
      const Reply('{"error":{"code":"session=fixture; x"}}', status: 400),
    );
    final ApiFailure failure = await failureOf(
      api.request('GET', <String>['api', 'auth', 'me']),
    );
    expect(failure.code, 'request_failed');
  });

  test('redirects are not followed', () async {
    server.replies.add(
      const Reply(
        '',
        status: 302,
        headers: <String, List<String>>{
          'location': <String>['http://127.0.0.1:8080/other'],
        },
      ),
    );
    final ApiFailure failure = await failureOf(
      api.request('GET', <String>['v1', 'me']),
    );
    expect(failure.status, 302);
    expect(server.seen, hasLength(1));
  });

  test('mutation errors keep Retry-After and are not retried', () async {
    server.replies.add(
      const Reply(
        '{"error":{"code":"rate_limited","message":"ignored"}}',
        status: 429,
        headers: <String, List<String>>{
          'retry-after': <String>['17'],
        },
      ),
    );
    final ApiFailure failure = await failureOf(
      api.request('POST', <String>['v1', 'agents']),
    );
    expect(failure.code, 'rate_limited');
    expect(failure.retryAfter, '17');
    expect(server.seen, hasLength(1));
  });

  test('blank bodies become {} and non-objects are invalid', () async {
    server.replies.addAll(const <Reply>[Reply(''), Reply('[1]')]);
    expect(await api.request('GET', <String>['api', 'a']), isEmpty);
    final ApiFailure failure = await failureOf(
      api.request('GET', <String>['api', 'b']),
    );
    expect(failure.code, 'invalid_body');
  });

  test('a csrf failure mints a token and retries once', () async {
    server.replies.addAll(<Reply>[invalidCsrf, freshCsrf, const Reply('{}')]);
    await api.webSettings(<String, dynamic>{'branchPrefix': 'mobile/'});
    expect(server.seen, hasLength(3));
    final Seen first = server.seen[0];
    final Seen refresh = server.seen[1];
    final Seen retry = server.seen[2];
    expect(first.headers['x-csrf-token'], 'old');
    expect(refresh.method, 'GET');
    expect(refresh.uri.path, '/api/csrf-token');
    expect(refresh.headers.containsKey('authorization'), isFalse);
    expect(refresh.headers.containsKey('x-csrf-token'), isFalse);
    expect(
      retry.uri.path,
      '/api/background-composer/update-background-composer-user-settings',
    );
    expect(retry.headers['x-csrf-token'], 'fresh');
    expect(retry.headers['cookie'], 'session=fixture; csrf-token=fresh');
    expect(retry.body, '{"branchPrefix":"mobile/"}');
  });

  test('a second csrf failure stops', () async {
    server.replies.addAll(<Reply>[invalidCsrf, freshCsrf, invalidCsrf]);
    final ApiFailure failure = await failureOf(
      api.webSettings(<String, dynamic>{'branchPrefix': 'x'}),
    );
    expect(failure.code, 'invalid_csrf_token');
    expect(server.seen, hasLength(3));
  });

  test('a refresh without a csrf cookie fails', () async {
    server.replies.addAll(<Reply>[invalidCsrf, const Reply('{}')]);
    final ApiFailure failure = await failureOf(
      api.request('POST', <String>['v1', 'agents']),
    );
    expect(failure.code, 'invalid_csrf_token');
    expect(server.seen, hasLength(2));
  });

  test('resetWebSession forgets the minted token', () async {
    server.replies.addAll(<Reply>[
      invalidCsrf,
      freshCsrf,
      const Reply('{}'),
      const Reply('{}'),
    ]);
    await api.request('POST', <String>['v1', 'agents']);
    api.resetWebSession();
    await api.request('POST', <String>['v1', 'agents']);
    expect(server.seen.last.headers['x-csrf-token'], 'old');
  });
}
