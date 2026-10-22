import 'dart:convert';
import 'dart:typed_data';

import 'package:cursor_android/data/api_failure.dart';
import 'package:cursor_android/data/cursor_api.dart';
import 'package:cursor_android/domain/agent_summary.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

const String fixtureCookie = 'session=fixture; csrf-token=old';
const Map<String, List<String>> noHeaders = <String, List<String>>{};
final Uri mockBase = Uri.parse('http://127.0.0.1:8080/');
const String listPath = '/api/background-composer/list';
const String offsetKey = 'last_message_activity_at_ms_offset';
const Map<String, dynamic> firstPage = <String, dynamic>{
  'n': 50,
  'include_status': true,
  'include_archived': true,
  'include_pinned_state': true,
};

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

List<String> ids(List<AgentSummary> agents) =>
    <String>[for (final AgentSummary agent in agents) agent.bcId];

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

  test('the first page posts the Kotlin list body', () async {
    server.replies.add(const Reply('{"composers":[]}'));
    await api.listBackgroundComposers();
    final Seen request = server.seen.single;
    expect(request.method, 'POST');
    expect(request.uri.path, listPath);
    expect(request.uri.query, isEmpty);
    expect(jsonDecode(request.body), firstPage);
    expect(request.headers['content-type'], contains('application/json'));
    expect(request.headers['x-csrf-token'], 'old');
    expect(request.headers.containsKey('authorization'), isFalse);
  });

  test('a null offset sends the first-page body', () async {
    server.replies.add(const Reply('{}'));
    await api.listBackgroundComposers(lastMessageActivityAtMsOffset: null);
    expect(jsonDecode(server.seen.single.body), firstPage);
  });

  test('a more-page passes the offset through unchanged', () async {
    server.replies.addAll(const <Reply>[Reply('{}'), Reply('{}')]);
    await api.listBackgroundComposers(
      lastMessageActivityAtMsOffset: 1700000000000,
    );
    await api.listBackgroundComposers(
      lastMessageActivityAtMsOffset: '1700000000000',
    );
    expect(server.seen, hasLength(2));
    for (final Seen request in server.seen) {
      expect(request.method, 'POST');
      expect(request.uri.path, listPath);
    }
    expect(jsonDecode(server.seen[0].body), <String, dynamic>{
      ...firstPage,
      offsetKey: 1700000000000,
    });
    expect(jsonDecode(server.seen[1].body), <String, dynamic>{
      ...firstPage,
      offsetKey: '1700000000000',
    });
  });

  test('the response is returned as is and composers parse', () async {
    server.replies.add(
      const Reply(
        '{"composers":[{"bcId":"bc-1","name":"Fix login",'
        '"status":"RUNNING","updatedAtMs":"1700000000000"},'
        '{"bcId":"bc-2","name":"Docs","status":"FINISHED"}],'
        '"hasMore":true,"nextPageOffset":1699999999999}',
      ),
    );
    final Map<String, dynamic> root = await api.listBackgroundComposers();
    expect(root['hasMore'], isTrue);
    expect(root['nextPageOffset'], 1699999999999);
    final List<AgentSummary> agents = agentsFromComposers(root);
    expect(ids(agents), <String>['bc-1', 'bc-2']);
    expect(agents.first.name, 'Fix login');
    expect(agents.first.status, 'RUNNING');
    expect(agents.first.updatedAtMs, 1700000000000);
    expect(agents.last.name, 'Docs');
    expect(agents.last.status, 'FINISHED');
  });

  test('empty or malformed composers yield no agents', () async {
    final List<String> bodies = <String>[
      '',
      '{}',
      '{"composers":null}',
      '{"composers":{}}',
      '{"composers":"none"}',
      '{"composers":[]}',
      '{"composers":[1,"x",null,true,[{"bcId":"a"}]]}',
    ];
    server.replies.addAll(<Reply>[for (final String body in bodies) Reply(body)]);
    for (final String body in bodies) {
      final Map<String, dynamic> root = await api.listBackgroundComposers();
      expect(agentsFromComposers(root), isEmpty, reason: body);
    }
    expect(server.seen, hasLength(bodies.length));
  });

  test('a body that is not an object fails with invalid_body', () async {
    server.replies.add(const Reply('[{"bcId":"bc-1"}]'));
    final ApiFailure failure = await failureOf(api.listBackgroundComposers());
    expect(failure.status, 200);
    expect(failure.code, 'invalid_body');
  });

  test('a csrf failure mints a token and retries the same body', () async {
    server.replies.addAll(<Reply>[
      invalidCsrf,
      freshCsrf,
      const Reply('{"composers":[{"bcId":"bc-1"}]}'),
    ]);
    final Map<String, dynamic> root = await api.listBackgroundComposers(
      lastMessageActivityAtMsOffset: 42,
    );
    expect(ids(agentsFromComposers(root)), <String>['bc-1']);
    expect(server.seen, hasLength(3));
    expect(server.seen[0].headers['x-csrf-token'], 'old');
    expect(server.seen[1].method, 'GET');
    expect(server.seen[1].uri.path, '/api/csrf-token');
    final Seen retry = server.seen[2];
    expect(retry.uri.path, listPath);
    expect(retry.headers['x-csrf-token'], 'fresh');
    expect(retry.body, server.seen[0].body);
    expect(jsonDecode(retry.body), <String, dynamic>{
      ...firstPage,
      offsetKey: 42,
    });
  });

  test('a failure never echoes the cookie or authorization', () async {
    server.replies.add(
      const Reply(
        '{"error":{"code":"unauthorized"},'
        '"echo":"Cookie: session=fixture; Authorization: Bearer secret-value"}',
        status: 401,
      ),
    );
    final ApiFailure failure = await failureOf(api.listBackgroundComposers());
    expect(failure.status, 401);
    expect(failure.code, 'unauthorized');
    final String text = failure.toString();
    for (final String leak in <String>[
      'Cookie',
      'Authorization',
      'Bearer',
      'session=fixture',
      'csrf-token',
      'secret-value',
    ]) {
      expect(text, isNot(contains(leak)), reason: leak);
    }
    expect(server.seen.single.headers.containsKey('authorization'), isFalse);
  });

  test('an unsafe error code falls back to request_failed', () async {
    server.replies.add(
      const Reply(
        '{"error":{"code":"Authorization: Bearer secret-value"}}',
        status: 500,
      ),
    );
    final ApiFailure failure = await failureOf(api.listBackgroundComposers());
    expect(failure.status, 500);
    expect(failure.code, 'request_failed');
    expect(failure.toString(), isNot(contains('Authorization')));
    expect(failure.toString(), isNot(contains('secret-value')));
  });
}
