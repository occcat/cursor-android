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
const String followupPath = '/api/auth/addAsyncFollowupBackgroundComposer';
final RegExp generatedId = RegExp(r'^fu-[0-9a-f]{32}$');

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

  test('a follow-up posts the Kotlin body with a trimmed prompt', () async {
    server.replies.add(const Reply('{"ok":true}'));
    expect(
      await api.addAsyncFollowupBackgroundComposer(
        bcId: '  bc-1  ',
        prompt: '  Also add tests  ',
        followupId: 'fu-fixed',
      ),
      <String, dynamic>{'ok': true},
    );
    final Seen request = server.seen.single;
    expect(request.method, 'POST');
    expect(request.uri.path, followupPath);
    expect(request.headers['content-type'], contains('application/json'));
    expect(request.headers['x-csrf-token'], 'old');
    expect(request.headers.containsKey('authorization'), isFalse);
    expect(
      request.body,
      '{"bcId":"bc-1","followup":"Also add tests",'
      '"followupMessage":"Also add tests","followupId":"fu-fixed",'
      '"expectedScope":"personal"}',
    );
    expect(request.json['followup'], request.json['followupMessage']);
  });

  test('a blank bcId is rejected before the network', () async {
    for (final String blank in <String>['', '   ', '\n\t']) {
      await expectLater(
        api.addAsyncFollowupBackgroundComposer(bcId: blank, prompt: 'Task'),
        throwsArgumentError,
      );
    }
    expect(server.seen, isEmpty);
  });

  test('a blank prompt is rejected before the network', () async {
    for (final String blank in <String>['', '   ', '\n\t']) {
      await expectLater(
        api.addAsyncFollowupBackgroundComposer(bcId: 'bc-1', prompt: blank),
        throwsArgumentError,
      );
    }
    expect(server.seen, isEmpty);
  });

  test('an omitted or blank followupId is generated', () async {
    server.replies.addAll(const <Reply>[Reply('{}'), Reply('{}')]);
    await api.addAsyncFollowupBackgroundComposer(bcId: 'bc-1', prompt: 'One');
    await api.addAsyncFollowupBackgroundComposer(
      bcId: 'bc-1',
      prompt: 'Two',
      followupId: '  ',
    );
    final Object? first = server.seen[0].json['followupId'];
    final Object? second = server.seen[1].json['followupId'];
    expect(first, startsWith('fu-'));
    expect(first, matches(generatedId));
    expect(second, matches(generatedId));
    expect(first, isNot(second));
  });

  test('newFollowupId uses 16 random bytes as hex', () {
    final String id = CursorApi.newFollowupId(Random(7));
    expect(id, matches(generatedId));
    expect(id, CursorApi.newFollowupId(Random(7)));
    expect(
      CursorApi.newBackgroundComposerId(Random(7)).substring(3),
      id.substring(3),
    );
  });

  test('a csrf failure mints a token and retries the same body', () async {
    server.replies.addAll(<Reply>[invalidCsrf, freshCsrf, const Reply('{}')]);
    await api.addAsyncFollowupBackgroundComposer(
      bcId: 'bc-1',
      prompt: 'Task',
      followupId: 'fu-retry',
    );
    expect(server.seen, hasLength(3));
    expect(server.seen[1].uri.path, '/api/csrf-token');
    final Seen retry = server.seen[2];
    expect(retry.uri.path, followupPath);
    expect(retry.headers['x-csrf-token'], 'fresh');
    expect(retry.body, server.seen[0].body);
  });

  test('a failure never echoes the cookie or a secret', () async {
    server.replies.add(
      const Reply(
        '{"error":{"code":"agent_not_running"},'
        '"echo":"session=fixture; token=secret-value"}',
        status: 409,
      ),
    );
    final ApiFailure failure = await failureOf(
      api.addAsyncFollowupBackgroundComposer(bcId: 'bc-1', prompt: 'Task'),
    );
    expect(failure.status, 409);
    expect(failure.code, 'agent_not_running');
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
      api.addAsyncFollowupBackgroundComposer(bcId: 'bc-1', prompt: 'Task'),
    );
    expect(failure.code, 'request_failed');
    expect(failure.toString(), isNot(contains('secret-value')));
  });
}
