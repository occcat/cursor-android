import 'dart:convert';
import 'dart:typed_data';

import 'package:cursor_android/data/api_failure.dart';
import 'package:cursor_android/data/cursor_api.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class Reply {
  const Reply(this.body, {this.status = 200, this.headers = const {}});

  final String body;
  final int status;
  final Map<String, List<String>> headers;
}

class FakeServer implements HttpClientAdapter {
  final List<Reply> replies = <Reply>[];
  final List<RequestOptions> seen = <RequestOptions>[];
  final List<String> bodies = <String>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final List<int> bytes = requestStream == null
        ? <int>[]
        : await requestStream.expand((Uint8List chunk) => chunk).toList();
    seen.add(options);
    bodies.add(utf8.decode(bytes));
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

void main() {
  late FakeServer server;
  late CursorApi api;

  setUp(() {
    server = FakeServer();
    api = CursorApi(
      cookie: () => 'session=fixture; csrf-token=old',
      webBase: Uri.parse('http://127.0.0.1:8080/'),
      allowConfiguredOrigin: true,
      dio: Dio()..httpClientAdapter = server,
    );
  });

  test('posts redact true to the secrets endpoint', () async {
    server.replies.add(const Reply('{"secrets":[]}'));
    expect(await api.listSecrets(), isEmpty);
    expect(server.seen.single.method, 'POST');
    expect(
      server.seen.single.uri.path,
      '/api/background-composer/list-background-composer-secrets',
    );
    expect(server.bodies.single, '{"redact":true}');
    expect(
      server.seen.single.headers.keys.map((String key) => key.toLowerCase()),
      isNot(contains('authorization')),
    );
  });

  test('strips both exact sensitive keys from every map', () async {
    server.replies.add(const Reply(
      '{"secrets":[{"name":"FIRST","id":"s-1","value":"hidden-a",'
      '"secretValue":{"content":"hidden-b"}},'
      '{"name":"SECOND","value":null,"secretValue":"hidden-c"}]}',
    ));
    final List<Map<String, dynamic>> secrets = await api.listSecrets();
    expect(secrets, <Map<String, dynamic>>[
      <String, dynamic>{'name': 'FIRST', 'id': 's-1'},
      <String, dynamic>{'name': 'SECOND'},
    ]);
    expect(jsonEncode(secrets), isNot(contains('hidden-')));
    for (final Map<String, dynamic> secret in secrets) {
      expect(secret.containsKey('value'), isFalse);
      expect(secret.containsKey('secretValue'), isFalse);
    }
  });

  test('copies primitive metadata and suppresses nested payloads', () async {
    server.replies.add(const Reply(
      '{"secrets":[{"name":"KEY","version":2,"redacted":true,'
      '"missing":null,"metadata":{"value":"nested-hidden"},'
      '"items":["nested-hidden"],"Value":"case-sensitive"}]}',
    ));
    expect(await api.listSecrets(), <Map<String, dynamic>>[
      <String, dynamic>{
        'name': 'KEY',
        'version': '2',
        'redacted': 'true',
        'missing': '',
        'metadata': '',
        'items': '',
        'Value': 'case-sensitive',
      },
    ]);
  });

  test('missing null empty and non-list secrets return an empty list', () async {
    for (final String body in <String>[
      '{}',
      '',
      '{"secrets":null}',
      '{"secrets":[]}',
      '{"secrets":{}}',
      '{"secrets":"invalid"}',
    ]) {
      server.replies.add(Reply(body));
      expect(await api.listSecrets(), isEmpty, reason: body);
    }
  });

  test('skips non-map items and keeps empty redacted maps', () async {
    server.replies.add(const Reply(
      '{"secrets":[null,1,true,"x",[],{"name":"KEY"},'
      '{"value":"hidden","secretValue":"hidden"}]}',
    ));
    expect(await api.listSecrets(), <Map<String, dynamic>>[
      <String, dynamic>{'name': 'KEY'},
      <String, dynamic>{},
    ]);
  });

  test('ApiFailure never echoes cookie or response secrets', () async {
    for (final String code in <String>[
      'forbidden',
      'session=fixture; secret-value',
    ]) {
      server.replies.add(Reply(
        jsonEncode(<String, dynamic>{
          'error': <String, dynamic>{'code': code},
          'echo': 'session=fixture; secret-value',
        }),
        status: 403,
      ));
      await expectLater(
        api.listSecrets(),
        throwsA(isA<ApiFailure>()
            .having((ApiFailure e) => e.status, 'status', 403)
            .having(
              (ApiFailure e) => e.code,
              'code',
              code == 'forbidden' ? 'forbidden' : 'request_failed',
            )
            .having(
              (ApiFailure e) => e.toString(),
              'safe message',
              allOf(
                isNot(contains('session=fixture')),
                isNot(contains('secret-value')),
              ),
            )),
      );
    }
  });

  test('CSRF refresh retries the same redacted request once', () async {
    server.replies.addAll(const <Reply>[
      Reply('{"error":{"code":"invalid_csrf_token"}}', status: 403),
      Reply('{}', headers: <String, List<String>>{
        'set-cookie': <String>['csrf-token=fresh; Path=/'],
      }),
      Reply('{"secrets":[{"name":"KEY","value":"hidden"}]}'),
    ]);
    expect(await api.listSecrets(), <Map<String, dynamic>>[
      <String, dynamic>{'name': 'KEY'},
    ]);
    expect(server.seen, hasLength(3));
    expect(server.seen[1].uri.path, '/api/csrf-token');
    expect(server.seen[2].headers['x-csrf-token'], 'fresh');
    expect(server.bodies[2], server.bodies[0]);
    expect(server.seen[2].uri, server.seen[0].uri);
  });
}
