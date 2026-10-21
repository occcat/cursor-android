import 'dart:convert';
import 'dart:typed_data';

import 'package:cursor_android/data/api_failure.dart';
import 'package:cursor_android/data/cursor_api.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

const String putPath =
    '/api/background-composer/create-background-composer-secret';

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

  test('posts trimmed name, exact value and redact true', () async {
    server.replies.add(const Reply('{}'));
    await api.putSecret('  API_KEY  ', 'secret-value');
    expect(server.seen.single.method, 'POST');
    expect(server.seen.single.uri.path, putPath);
    expect(
      server.bodies.single,
      '{"name":"API_KEY","value":"secret-value","redact":true}',
    );
    expect(
      server.seen.single.headers.keys.map((String key) => key.toLowerCase()),
      isNot(contains('authorization')),
    );
  });

  test('value with surrounding whitespace is sent unchanged', () async {
    const String value = '  padded \t secret-value \n ';
    server.replies.add(const Reply('{}'));
    await api.putSecret('KEY', value);
    final Object? body = jsonDecode(server.bodies.single);
    expect(body, <String, dynamic>{
      'name': 'KEY',
      'value': value,
      'redact': true,
    });
  });

  test('blank name throws ArgumentError without network', () async {
    await expectLater(
      api.putSecret('', 'secret-value'),
      throwsA(isA<ArgumentError>().having(
        (ArgumentError e) => e.toString(),
        'message',
        isNot(contains('secret-value')),
      )),
    );
    expect(server.seen, isEmpty);
  });

  test('whitespace-only name throws ArgumentError without network', () async {
    for (final String name in <String>[' ', '   ', '\t', '\n \t ']) {
      await expectLater(
        api.putSecret(name, 'secret-value'),
        throwsArgumentError,
        reason: jsonEncode(name),
      );
    }
    expect(server.seen, isEmpty);
  });

  test('response body is discarded', () async {
    for (final String body in <String>[
      '',
      '{}',
      '{"ok":true}',
      '{"secret":{"name":"KEY","value":"echoed"}}',
    ]) {
      server.replies.add(Reply(body));
      await expectLater(api.putSecret('KEY', 'secret-value'), completes);
    }
    expect(server.seen, hasLength(4));
  });

  test('ApiFailure never echoes cookie or secret value', () async {
    for (final String code in <String>[
      'forbidden',
      'session=fixture; secret-value',
    ]) {
      server.replies.add(Reply(
        jsonEncode(<String, dynamic>{
          'error': <String, dynamic>{'code': code},
          'echo': 'session=fixture; secret-value',
        }),
        status: 400,
      ));
      await expectLater(
        api.putSecret('KEY', 'secret-value'),
        throwsA(isA<ApiFailure>()
            .having((ApiFailure e) => e.status, 'status', 400)
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

  test('CSRF refresh retries the same body once', () async {
    server.replies.addAll(const <Reply>[
      Reply('{"error":{"code":"invalid_csrf_token"}}', status: 403),
      Reply('{}', headers: <String, List<String>>{
        'set-cookie': <String>['csrf-token=fresh; Path=/'],
      }),
      Reply('{}'),
    ]);
    await api.putSecret(' KEY ', ' secret-value ');
    expect(server.seen, hasLength(3));
    expect(server.seen[1].uri.path, '/api/csrf-token');
    expect(server.seen[2].uri.path, putPath);
    expect(server.seen[2].headers['x-csrf-token'], 'fresh');
    expect(server.bodies[2], server.bodies[0]);
    expect(
      server.bodies[2],
      '{"name":"KEY","value":" secret-value ","redact":true}',
    );
  });
}
