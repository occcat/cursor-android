import 'dart:convert';
import 'dart:typed_data';

import 'package:cursor_android/data/api_failure.dart';
import 'package:cursor_android/data/cursor_api.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

const String fixtureCookie = 'session=fixture; csrf-token=old';
const Map<String, List<String>> noHeaders = <String, List<String>>{};
final Uri mockBase = Uri.parse('http://127.0.0.1:8080/');
const String artifactsPath = '/api/background-composer/list-artifacts';

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

  test('a listing posts the trimmed bcId and parses artifacts', () async {
    server.replies.add(
      const Reply(
        '{"artifacts":[{"path":"out/a.txt","size":3},{"name":"b.png"}],'
        '"other":1}',
      ),
    );
    final List<Map<String, dynamic>> artifacts = await api.listArtifacts(
      '  bc-1  ',
    );
    expect(artifacts, <Map<String, dynamic>>[
      <String, dynamic>{'path': 'out/a.txt', 'size': 3},
      <String, dynamic>{'name': 'b.png'},
    ]);
    final Seen request = server.seen.single;
    expect(request.method, 'POST');
    expect(request.uri.path, artifactsPath);
    expect(request.headers['content-type'], contains('application/json'));
    expect(request.headers['x-csrf-token'], 'old');
    expect(request.headers.containsKey('authorization'), isFalse);
    expect(request.body, '{"bcId":"bc-1"}');
  });

  test('a blank bcId is rejected before the network', () async {
    for (final String blank in <String>['', '   ', '\n\t']) {
      await expectLater(api.listArtifacts(blank), throwsArgumentError);
    }
    expect(server.seen, isEmpty);
  });

  test('missing or malformed artifacts yield an empty list', () async {
    final List<String> bodies = <String>[
      '{}',
      '{"artifacts":null}',
      '{"artifacts":{}}',
      '{"artifacts":"none"}',
      '',
    ];
    server.replies.addAll(<Reply>[for (final String body in bodies) Reply(body)]);
    for (final String body in bodies) {
      expect(await api.listArtifacts('bc-1'), isEmpty, reason: body);
    }
    expect(server.seen, hasLength(bodies.length));
  });

  test('items that are not objects are skipped', () async {
    server.replies.add(
      const Reply(
        '{"artifacts":["x",1,null,{"path":"a"},[{"path":"b"}],true]}',
      ),
    );
    expect(await api.listArtifacts('bc-1'), <Map<String, dynamic>>[
      <String, dynamic>{'path': 'a'},
    ]);
  });

  test('a csrf failure mints a token and retries the same body', () async {
    server.replies.addAll(<Reply>[
      invalidCsrf,
      freshCsrf,
      const Reply('{"artifacts":[{"path":"a"}]}'),
    ]);
    expect(await api.listArtifacts('bc-1'), hasLength(1));
    expect(server.seen, hasLength(3));
    expect(server.seen[1].uri.path, '/api/csrf-token');
    final Seen retry = server.seen[2];
    expect(retry.uri.path, artifactsPath);
    expect(retry.headers['x-csrf-token'], 'fresh');
    expect(retry.body, server.seen[0].body);
  });

  test('a failure never echoes the cookie or a secret', () async {
    server.replies.add(
      const Reply(
        '{"error":{"code":"not_found"},'
        '"echo":"session=fixture; token=secret-value"}',
        status: 404,
      ),
    );
    final ApiFailure failure = await failureOf(api.listArtifacts('bc-1'));
    expect(failure.status, 404);
    expect(failure.code, 'not_found');
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
    final ApiFailure failure = await failureOf(api.listArtifacts('bc-1'));
    expect(failure.code, 'request_failed');
    expect(failure.toString(), isNot(contains('secret-value')));
  });
}
