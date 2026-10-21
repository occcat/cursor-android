import 'dart:convert';
import 'dart:typed_data';

import 'package:cursor_android/data/api_failure.dart';
import 'package:cursor_android/data/cursor_api.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

const String fixtureCookie = 'session=fixture; csrf-token=old';
const Map<String, List<String>> noHeaders = <String, List<String>>{};
final Uri mockBase = Uri.parse('http://127.0.0.1:8080/');
const String sharedPath = '/api/background-composer/list-environments';
const String personalPath =
    '/api/background-composer/list-personal-environments';

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

  test('both lists are posted with an empty object', () async {
    server.replies.addAll(const <Reply>[Reply('{}'), Reply('{}')]);
    expect(await api.listEnvironments(), isEmpty);
    expect(server.seen, hasLength(2));
    expect(server.seen[0].uri.path, sharedPath);
    expect(server.seen[1].uri.path, personalPath);
    for (final Seen request in server.seen) {
      expect(request.method, 'POST');
      expect(request.body, '{}');
      expect(request.headers['content-type'], contains('application/json'));
      expect(request.headers['x-csrf-token'], 'old');
      expect(request.headers.containsKey('authorization'), isFalse);
    }
  });

  test('shared then personal are merged by publicId, first wins', () async {
    server.replies.addAll(const <Reply>[
      Reply(
        '{"environments":[{"publicId":"env-a","name":"Shared A"},'
        '{"publicId":"env-b","name":"Shared B"}]}',
      ),
      Reply(
        '{"environments":[{"publicId":"env-b","name":"Personal B"},'
        '{"publicId":"env-c","name":"Personal C"}]}',
      ),
    ]);
    expect(await api.listEnvironments(), <Map<String, dynamic>>[
      <String, dynamic>{'publicId': 'env-a', 'name': 'Shared A'},
      <String, dynamic>{'publicId': 'env-b', 'name': 'Shared B'},
      <String, dynamic>{'publicId': 'env-c', 'name': 'Personal C'},
    ]);
  });

  test('items without a usable publicId are skipped', () async {
    server.replies.addAll(const <Reply>[
      Reply(
        '{"environments":["x",1,null,{"publicId":"  "},{"name":"no id"},'
        '{"publicId":7},{"publicId":"env-a"}]}',
      ),
      Reply('{"environments":{"publicId":"env-z"}}'),
    ]);
    expect(await api.listEnvironments(), <Map<String, dynamic>>[
      <String, dynamic>{'publicId': 'env-a'},
    ]);
  });

  test('missing environments yield an empty list', () async {
    for (final List<Reply> pair in <List<Reply>>[
      const <Reply>[Reply('{}'), Reply('')],
      const <Reply>[
        Reply('{"environments":null}'),
        Reply('{"other":[]}'),
      ],
    ]) {
      server.replies.addAll(pair);
      expect(await api.listEnvironments(), isEmpty);
    }
    expect(server.seen, hasLength(4));
  });

  test('a failure never echoes the cookie or a secret', () async {
    server.replies.add(
      const Reply(
        '{"error":{"code":"forbidden"},'
        '"echo":"session=fixture; token=secret-value"}',
        status: 403,
      ),
    );
    final ApiFailure failure = await failureOf(api.listEnvironments());
    expect(failure.status, 403);
    expect(failure.code, 'forbidden');
    expect(failure.toString(), isNot(contains('session=fixture')));
    expect(failure.toString(), isNot(contains('secret-value')));
    expect(failure.toString(), isNot(contains('csrf-token')));
    expect(server.seen.single.uri.path, sharedPath);
  });

  test('an unsafe error code falls back to request_failed', () async {
    server.replies.add(
      const Reply(
        '{"error":{"code":"session=fixture; secret-value"}}',
        status: 500,
      ),
    );
    final ApiFailure failure = await failureOf(api.listEnvironments());
    expect(failure.code, 'request_failed');
    expect(failure.toString(), isNot(contains('secret-value')));
  });

  test('a csrf failure mints a token once and both lists use it', () async {
    server.replies.addAll(<Reply>[
      invalidCsrf,
      freshCsrf,
      const Reply('{}'),
      const Reply('{"environments":[{"publicId":"env-p"}]}'),
    ]);
    expect(await api.listEnvironments(), <Map<String, dynamic>>[
      <String, dynamic>{'publicId': 'env-p'},
    ]);
    expect(server.seen, hasLength(4));
    expect(server.seen[1].uri.path, '/api/csrf-token');
    expect(server.seen[2].uri.path, sharedPath);
    expect(server.seen[2].headers['x-csrf-token'], 'fresh');
    expect(server.seen[3].uri.path, personalPath);
    expect(server.seen[3].headers['x-csrf-token'], 'fresh');
  });
}
