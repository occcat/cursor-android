import 'dart:convert';
import 'dart:typed_data';

import 'package:cursor_android/data/api_failure.dart';
import 'package:cursor_android/data/cursor_api.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

const String fixtureCookie = 'session=fixture; csrf-token=old';
const Map<String, List<String>> noHeaders = <String, List<String>>{};
final Uri mockBase = Uri.parse('http://127.0.0.1:8080/');
const String archivePath = '/api/auth/archiveBackgroundComposer';

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

  test('archive posts the bcId without an unarchive key', () async {
    server.replies.add(const Reply('{"success":true}'));
    final Map<String, dynamic> result = await api.archiveAgent('bc-1');
    expect(result, <String, dynamic>{'success': true});
    final Seen request = server.seen.single;
    expect(request.method, 'POST');
    expect(request.uri.path, archivePath);
    expect(jsonDecode(request.body), <String, dynamic>{'bcId': 'bc-1'});
    expect(request.headers['content-type'], contains('application/json'));
    expect(request.headers['x-csrf-token'], 'old');
    expect(request.headers.containsKey('authorization'), isFalse);
  });

  test('unarchive posts the same path with unarchive true', () async {
    server.replies.add(const Reply('{}'));
    await api.unarchiveAgent('bc-2');
    final Seen request = server.seen.single;
    expect(request.method, 'POST');
    expect(request.uri.path, archivePath);
    expect(jsonDecode(request.body), <String, dynamic>{
      'bcId': 'bc-2',
      'unarchive': true,
    });
  });

  test('archiveBackgroundComposer matches the wrappers', () async {
    server.replies.addAll(const <Reply>[Reply('{}'), Reply('{}')]);
    await api.archiveBackgroundComposer('bc-3');
    await api.archiveBackgroundComposer('bc-3', unarchive: true);
    expect(server.seen[0].body, '{"bcId":"bc-3"}');
    expect(server.seen[1].body, '{"bcId":"bc-3","unarchive":true}');
  });

  test('a blank bcId is rejected before the network', () async {
    for (final String blank in <String>['', '   ']) {
      await expectLater(api.archiveAgent(blank), throwsArgumentError);
      await expectLater(api.unarchiveAgent(blank), throwsArgumentError);
    }
    expect(server.seen, isEmpty);
  });

  test('a csrf failure mints a token and retries the archive once', () async {
    server.replies.addAll(<Reply>[invalidCsrf, freshCsrf, const Reply('{}')]);
    await api.unarchiveAgent('bc-4');
    expect(server.seen, hasLength(3));
    expect(server.seen[0].uri.path, archivePath);
    expect(server.seen[0].headers['x-csrf-token'], 'old');
    expect(server.seen[1].method, 'GET');
    expect(server.seen[1].uri.path, '/api/csrf-token');
    final Seen retry = server.seen[2];
    expect(retry.uri.path, archivePath);
    expect(retry.headers['x-csrf-token'], 'fresh');
    expect(retry.body, '{"bcId":"bc-4","unarchive":true}');
  });

  test('a second csrf failure stops after one retry', () async {
    server.replies.addAll(<Reply>[invalidCsrf, freshCsrf, invalidCsrf]);
    final ApiFailure failure = await failureOf(api.archiveAgent('bc-5'));
    expect(failure.code, 'invalid_csrf_token');
    expect(server.seen, hasLength(3));
  });

  test('a failure never echoes the cookie or a secret', () async {
    server.replies.add(
      const Reply(
        '{"error":{"code":"forbidden"},'
        '"echo":"session=fixture; token=secret-value"}',
        status: 403,
      ),
    );
    final ApiFailure failure = await failureOf(api.archiveAgent('bc-6'));
    expect(failure.status, 403);
    expect(failure.code, 'forbidden');
    expect(failure.toString(), isNot(contains('session=fixture')));
    expect(failure.toString(), isNot(contains('secret-value')));
    expect(failure.toString(), isNot(contains('csrf-token')));
  });

  test('an unsafe error code is replaced by request_failed', () async {
    server.replies.add(
      const Reply('{"error":{"code":"session=fixture; x"}}', status: 400),
    );
    final ApiFailure failure = await failureOf(api.archiveAgent('bc-7'));
    expect(failure.code, 'request_failed');
    expect(failure.toString(), isNot(contains('session=fixture')));
  });
}
