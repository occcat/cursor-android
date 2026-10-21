import 'dart:convert';
import 'dart:math' show Random;
import 'dart:typed_data';

import 'package:cursor_android/data/api_failure.dart';
import 'package:cursor_android/data/cursor_api.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

const String fixtureCookie = 'session=fixture; csrf-token=old';
const Map<String, List<String>> noHeaders = <String, List<String>>{};
final Uri mockBase = Uri.parse('http://127.0.0.1:8080/');
const String createPath = '/api/auth/startBackgroundComposerFromSnapshot';
final RegExp generatedId = RegExp(r'^bc-[0-9a-f]{32}$');

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

  Map<String, dynamic> get json => jsonDecode(body) as Map<String, dynamic>;
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

  test('a prompt-only agent posts the minimal Kotlin body', () async {
    server.replies.add(const Reply('{}'));
    final String id = await api.startBackgroundComposerFromSnapshot(
      prompt: '  Fix the login bug  ',
      bcId: 'bc-fixed',
    );
    expect(id, 'bc-fixed');
    final Seen request = server.seen.single;
    expect(request.method, 'POST');
    expect(request.uri.path, createPath);
    expect(request.headers['content-type'], contains('application/json'));
    expect(request.headers['x-csrf-token'], 'old');
    expect(request.headers.containsKey('authorization'), isFalse);
    expect(request.json, <String, dynamic>{
      'bcId': 'bc-fixed',
      'prompt': 'Fix the login bug',
      'expectedScope': 'personal',
    });
  });

  test('a model adds requestedModels', () async {
    server.replies.add(const Reply('{}'));
    await api.startBackgroundComposerFromSnapshot(
      prompt: 'Task',
      model: 'gpt-5',
      bcId: 'bc-model',
    );
    expect(server.seen.single.json, <String, dynamic>{
      'bcId': 'bc-model',
      'prompt': 'Task',
      'requestedModels': <Object?>[
        <String, dynamic>{'modelId': 'gpt-5'},
      ],
      'expectedScope': 'personal',
    });
  });

  test('an environment wins over repositories', () async {
    server.replies.add(const Reply('{}'));
    await api.startBackgroundComposerFromSnapshot(
      prompt: 'Task',
      environment: 'env-1',
      repos: <String>['https://github.com/a/b'],
      bcId: 'bc-env',
    );
    final Map<String, dynamic> body = server.seen.single.json;
    expect(body['environment'], <String, dynamic>{'publicId': 'env-1'});
    expect(body.containsKey('repoUrl'), isFalse);
    expect(body.containsKey('requestedModels'), isFalse);
  });

  test('without an environment the first repository becomes repoUrl', () async {
    server.replies.add(const Reply('{}'));
    await api.startBackgroundComposerFromSnapshot(
      prompt: 'Task',
      repos: <String>['https://github.com/a/first', 'https://github.com/a/2'],
      model: '  ',
      environment: ' ',
      bcId: 'bc-repo',
    );
    expect(server.seen.single.json, <String, dynamic>{
      'bcId': 'bc-repo',
      'prompt': 'Task',
      'repoUrl': 'https://github.com/a/first',
      'expectedScope': 'personal',
    });
  });

  test('the JSON keys keep the Kotlin order', () async {
    server.replies.add(const Reply('{}'));
    await api.startBackgroundComposerFromSnapshot(
      prompt: 'Task',
      model: 'm',
      repos: <String>['r'],
      bcId: 'bc-order',
    );
    expect(
      server.seen.single.body,
      '{"bcId":"bc-order","prompt":"Task",'
      '"requestedModels":[{"modelId":"m"}],"repoUrl":"r",'
      '"expectedScope":"personal"}',
    );
  });

  test('a blank prompt is rejected before the network', () async {
    for (final String blank in <String>['', '   ', '\n\t']) {
      await expectLater(
        api.startBackgroundComposerFromSnapshot(prompt: blank),
        throwsArgumentError,
      );
    }
    expect(server.seen, isEmpty);
  });

  test('an omitted or blank bcId is generated and returned', () async {
    server.replies.addAll(const <Reply>[Reply('{}'), Reply('{}')]);
    final String first = await api.startBackgroundComposerFromSnapshot(
      prompt: 'One',
    );
    final String second = await api.startBackgroundComposerFromSnapshot(
      prompt: 'Two',
      bcId: '  ',
    );
    expect(first, matches(generatedId));
    expect(second, matches(generatedId));
    expect(first, isNot(second));
    expect(server.seen[0].json['bcId'], first);
    expect(server.seen[1].json['bcId'], second);
  });

  test('newBackgroundComposerId uses 16 random bytes as hex', () {
    final String id = CursorApi.newBackgroundComposerId(Random(7));
    expect(id, matches(generatedId));
    expect(id, CursorApi.newBackgroundComposerId(Random(7)));
  });

  test('a csrf failure mints a token and retries the same body', () async {
    server.replies.addAll(<Reply>[invalidCsrf, freshCsrf, const Reply('{}')]);
    final String id = await api.startBackgroundComposerFromSnapshot(
      prompt: 'Task',
      bcId: 'bc-retry',
    );
    expect(id, 'bc-retry');
    expect(server.seen, hasLength(3));
    expect(server.seen[1].uri.path, '/api/csrf-token');
    final Seen retry = server.seen[2];
    expect(retry.uri.path, createPath);
    expect(retry.headers['x-csrf-token'], 'fresh');
    expect(retry.body, server.seen[0].body);
  });

  test('a failure never echoes the cookie or a secret', () async {
    server.replies.add(
      const Reply(
        '{"error":{"code":"usage_limit_exceeded"},'
        '"echo":"session=fixture; token=secret-value"}',
        status: 402,
      ),
    );
    final ApiFailure failure = await failureOf(
      api.startBackgroundComposerFromSnapshot(prompt: 'Task'),
    );
    expect(failure.status, 402);
    expect(failure.code, 'usage_limit_exceeded');
    expect(failure.toString(), isNot(contains('session=fixture')));
    expect(failure.toString(), isNot(contains('secret-value')));
    expect(failure.toString(), isNot(contains('csrf-token')));
  });
}
