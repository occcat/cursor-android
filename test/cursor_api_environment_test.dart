import 'dart:convert';
import 'dart:typed_data';

import 'package:cursor_android/data/api_failure.dart';
import 'package:cursor_android/data/cursor_api.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

const String fixtureCookie = 'session=fixture; csrf-token=old';
const Map<String, List<String>> noHeaders = <String, List<String>>{};
final Uri mockBase = Uri.parse('http://127.0.0.1:8080/');
const String environmentPath = '/api/background-composer/get-environment';

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

  test('a request posts the trimmed id and asks for environment.json', () async {
    server.replies.add(
      const Reply(
        r'{"environment":{"publicId":"env-1","name":"Linux box",'
        r'"environmentJson":"{\"install\":\"npm ci\"}"}}',
      ),
    );
    expect(await api.getEnvironment('  env-1  '), <String, dynamic>{
      'publicId': 'env-1',
      'name': 'Linux box',
      'environmentJson': '{"install":"npm ci"}',
    });
    final Seen request = server.seen.single;
    expect(request.method, 'POST');
    expect(request.uri.path, environmentPath);
    expect(request.headers['content-type'], contains('application/json'));
    expect(request.headers['x-csrf-token'], 'old');
    expect(request.headers.containsKey('authorization'), isFalse);
    expect(request.body, '{"publicId":"env-1","includeEnvironmentJson":true}');
  });

  test('a blank id is rejected before the network', () async {
    for (final String blank in <String>['', '   ', '\n\t']) {
      await expectLater(api.getEnvironment(blank), throwsArgumentError);
    }
    expect(server.seen, isEmpty);
  });

  test('flat responses are read and a blank publicId falls back', () async {
    server.replies.addAll(const <Reply>[
      Reply('{"publicId":"env-2","name":"Flat"}'),
      Reply('{"environment":{"publicId":"  ","name":"Nested"}}'),
      Reply('{"environment":"not an object","name":"Outer"}'),
      Reply(''),
    ]);
    expect(await api.getEnvironment('env-2'), <String, dynamic>{
      'publicId': 'env-2',
      'name': 'Flat',
      'environmentJson': '',
    });
    expect(await api.getEnvironment('env-3'), <String, dynamic>{
      'publicId': 'env-3',
      'name': 'Nested',
      'environmentJson': '',
    });
    expect(await api.getEnvironment('env-4'), <String, dynamic>{
      'publicId': 'env-4',
      'name': 'Outer',
      'environmentJson': '',
    });
    expect(await api.getEnvironment('env-5'), <String, dynamic>{
      'publicId': 'env-5',
      'name': '',
      'environmentJson': '',
    });
  });

  test('environmentJson becomes text like Kotlin environmentJsonText', () async {
    final Map<String, String> cases = <String, String>{
      r'"{\"a\":1}"': '{"a":1}',
      '{"install":"npm ci","ports":[3000]}':
          '{"install":"npm ci","ports":[3000]}',
      '[1,"two"]': '[1,"two"]',
      'null': '',
      '7': '7',
      'true': 'true',
    };
    for (final MapEntry<String, String> entry in cases.entries) {
      server.replies.add(
        Reply(
          '{"environment":{"publicId":"env-1",'
          '"environmentJson":${entry.key}}}',
        ),
      );
      final Map<String, dynamic> environment = await api.getEnvironment(
        'env-1',
      );
      expect(environment['environmentJson'], entry.value, reason: entry.key);
    }
    server.replies.add(const Reply('{"environment":{"publicId":"env-1"}}'));
    expect((await api.getEnvironment('env-1'))['environmentJson'], '');
  });

  test('a failure never echoes the cookie or a secret', () async {
    server.replies.add(
      const Reply(
        '{"error":{"code":"forbidden"},'
        '"echo":"session=fixture; token=secret-value"}',
        status: 403,
      ),
    );
    final ApiFailure failure = await failureOf(api.getEnvironment('env-1'));
    expect(failure.status, 403);
    expect(failure.code, 'forbidden');
    expect(failure.toString(), isNot(contains('session=fixture')));
    expect(failure.toString(), isNot(contains('secret-value')));
    expect(failure.toString(), isNot(contains('csrf-token')));
  });

  test('an unsafe error code falls back to request_failed', () async {
    server.replies.add(
      const Reply(
        '{"error":{"code":"session=fixture; secret-value"}}',
        status: 500,
      ),
    );
    final ApiFailure failure = await failureOf(api.getEnvironment('env-1'));
    expect(failure.code, 'request_failed');
    expect(failure.toString(), isNot(contains('secret-value')));
  });

  test('a csrf failure mints a token and retries the same body', () async {
    server.replies.addAll(<Reply>[
      invalidCsrf,
      freshCsrf,
      const Reply('{"environment":{"publicId":"env-1","name":"Box"}}'),
    ]);
    expect((await api.getEnvironment('env-1'))['name'], 'Box');
    expect(server.seen, hasLength(3));
    expect(server.seen[1].uri.path, '/api/csrf-token');
    final Seen retry = server.seen[2];
    expect(retry.uri.path, environmentPath);
    expect(retry.headers['x-csrf-token'], 'fresh');
    expect(retry.body, server.seen[0].body);
  });
}
