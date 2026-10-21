import 'dart:convert';
import 'dart:typed_data';

import 'package:cursor_android/data/api_failure.dart';
import 'package:cursor_android/data/cursor_api.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

const String fixtureCookie = 'session=fixture; csrf-token=old';
const Map<String, List<String>> noHeaders = <String, List<String>>{};
final Uri mockBase = Uri.parse('http://127.0.0.1:8080/');
const String bytesPath = '/api/background-composer/get-artifact-bytes';
const Map<String, dynamic> fileArtifact = <String, dynamic>{'path': 'a.txt'};

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

  test('a request posts the trimmed bcId and every locator field', () async {
    server.replies.add(
      const Reply('{"content":"aGk=","mimeType":"text/plain"}'),
    );
    final Map<String, dynamic> response = await api.getArtifactBytes(
      bcId: '  bc-1  ',
      artifact: <String, dynamic>{
        'name': 'a.txt',
        'size': 3,
        'absolutePath': '/work/out/a.txt',
        'path': 'out/a.txt',
      },
    );
    expect(response, <String, dynamic>{
      'content': 'aGk=',
      'mimeType': 'text/plain',
    });
    final Seen request = server.seen.single;
    expect(request.method, 'POST');
    expect(request.uri.path, bytesPath);
    expect(request.headers['content-type'], contains('application/json'));
    expect(request.headers['x-csrf-token'], 'old');
    expect(request.headers.containsKey('authorization'), isFalse);
    expect(
      request.body,
      '{"bcId":"bc-1","path":"out/a.txt",'
      '"absolutePath":"/work/out/a.txt","name":"a.txt"}',
    );
  });

  test('only non-blank string locator fields are sent', () async {
    server.replies.add(const Reply('{"content":""}'));
    await api.getArtifactBytes(
      bcId: 'bc-1',
      artifact: <String, dynamic>{
        'path': '   ',
        'absolutePath': 42,
        'name': 'b.png',
      },
    );
    expect(server.seen.single.body, '{"bcId":"bc-1","name":"b.png"}');
  });

  test('a blank bcId is rejected before the network', () async {
    for (final String blank in <String>['', '   ', '\n\t']) {
      await expectLater(
        api.getArtifactBytes(bcId: blank, artifact: fileArtifact),
        throwsArgumentError,
      );
    }
    expect(server.seen, isEmpty);
  });

  test('an artifact without a locator is rejected before the network', () async {
    for (final Map<String, dynamic> artifact in <Map<String, dynamic>>[
      <String, dynamic>{},
      <String, dynamic>{'path': '  ', 'absolutePath': null, 'name': 7},
      <String, dynamic>{'size': 1},
    ]) {
      await expectLater(
        api.getArtifactBytes(bcId: 'bc-1', artifact: artifact),
        throwsArgumentError,
      );
    }
    expect(server.seen, isEmpty);
  });

  test('an empty response body yields an empty map', () async {
    server.replies.add(const Reply(''));
    expect(
      await api.getArtifactBytes(bcId: 'bc-1', artifact: fileArtifact),
      isEmpty,
    );
  });

  test('a csrf failure mints a token and retries the same body', () async {
    server.replies.addAll(<Reply>[
      invalidCsrf,
      freshCsrf,
      const Reply('{"content":"aGk="}'),
    ]);
    expect(
      await api.getArtifactBytes(bcId: 'bc-1', artifact: fileArtifact),
      <String, dynamic>{'content': 'aGk='},
    );
    expect(server.seen, hasLength(3));
    expect(server.seen[1].uri.path, '/api/csrf-token');
    final Seen retry = server.seen[2];
    expect(retry.uri.path, bytesPath);
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
    final ApiFailure failure = await failureOf(
      api.getArtifactBytes(bcId: 'bc-1', artifact: fileArtifact),
    );
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
    final ApiFailure failure = await failureOf(
      api.getArtifactBytes(bcId: 'bc-1', artifact: fileArtifact),
    );
    expect(failure.code, 'request_failed');
    expect(failure.toString(), isNot(contains('secret-value')));
  });
}
