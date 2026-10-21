import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cursor_android/data/api_failure.dart';
import 'package:cursor_android/data/connect_stream.dart';
import 'package:cursor_android/data/cursor_api.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

const String fixtureCookie = 'session=fixture; csrf-token=old';
final Uri mockBase = Uri.parse('http://127.0.0.1:8080/');
const String streamPath =
    '/api/connect-proxy/aiserver.v1.BackgroundComposerService/'
    'StreamConversation';

/// One request as seen by the fake server, with lower-case header names.
class Seen {
  const Seen(this.method, this.uri, this.headers, this.body);

  final String method;
  final Uri uri;
  final Map<String, String> headers;
  final List<int> body;
}

/// In-memory server that answers queued response factories in order.
class FakeServer implements HttpClientAdapter {
  final List<ResponseBody Function()> replies = <ResponseBody Function()>[];
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
        bytes,
      ),
    );
    return replies.removeAt(0)();
  }

  @override
  void close({bool force = false}) {}
}

/// A response whose body arrives as the given [chunks].
ResponseBody Function() chunked(
  List<List<int>> chunks, {
  int status = 200,
  Map<String, List<String>> headers = const <String, List<String>>{},
}) {
  return () => ResponseBody(
    Stream<Uint8List>.fromIterable(chunks.map(Uint8List.fromList)),
    status,
    headers: headers,
  );
}

Future<T> failureOf<T extends Object>(Future<Object?> future) async {
  try {
    await future;
  } on Object catch (error) {
    if (error is T) {
      return error;
    }
    rethrow;
  }
  fail('Expected $T');
}

void main() {
  late FakeServer server;
  late CursorApi api;
  late List<ConversationUpdate> updates;

  setUp(() {
    server = FakeServer();
    updates = <ConversationUpdate>[];
    api = CursorApi(
      cookie: () => fixtureCookie,
      webBase: mockBase,
      allowConfiguredOrigin: true,
      dio: Dio()..httpClientAdapter = server,
    );
  });

  test('uses Connect frames and carries the offset', () async {
    final List<int> bytes = <int>[
      ...interactionFrame('off-1', 'Hello'),
      ...endFrame(),
    ];
    server.replies.add(
      chunked(<List<int>>[bytes.sublist(0, 3), bytes.sublist(3)]),
    );
    await api.conversation('bc-1', 'previous', updates.add);
    final Seen request = server.seen.single;
    expect(request.method, 'POST');
    expect(request.uri.path, streamPath);
    expect(
      request.headers['content-type'],
      contains('application/connect+proto'),
    );
    expect(request.headers['connect-protocol-version'], '1');
    expect(request.headers['accept'], 'application/connect+proto');
    expect(request.headers.containsKey('authorization'), isFalse);
    expect(request.headers['cookie'], contains('session=fixture'));
    expect(request.body, encodeConversationRequest('bc-1', 'previous'));
    final String payload = utf8.decode(request.body, allowMalformed: true);
    expect(payload, contains('bc-1'));
    expect(payload, contains('previous'));
    expect(payload, isNot(contains('session=fixture')));
    expect(updates.first.text, 'Hello');
    expect(updates.first.offsetKey, 'off-1');
    expect(updates.last.end, isTrue);
  });

  test('an end-frame error is not shown as text', () async {
    server.replies.add(
      chunked(<List<int>>[
        endFrame(
          '{"error":{"code":"usage_limit_exceeded",'
          '"cookie":"session=fixture"}}',
        ),
      ]),
    );
    final ApiFailure failure = await failureOf<ApiFailure>(
      api.conversation('bc', null, updates.add),
    );
    expect(failure.status, 400);
    expect(failure.code, 'usage_limit_exceeded');
    expect(failure.toString(), isNot(contains('session=')));
    expect(updates, isEmpty);
  });

  test('cancelling a visible stream returns promptly', () async {
    final StreamController<Uint8List> body = StreamController<Uint8List>();
    server.replies.add(() => ResponseBody(body.stream, 200));
    final CancelToken token = CancelToken();
    final Completer<void> firstUpdate = Completer<void>();
    final Future<void> stream = api.conversation('a', null, (
      ConversationUpdate update,
    ) {
      if (!firstUpdate.isCompleted) {
        firstUpdate.complete();
      }
    }, cancelToken: token);
    body.add(interactionFrame('off', 'pending'));
    await firstUpdate.future.timeout(const Duration(seconds: 2));
    final Stopwatch watch = Stopwatch()..start();
    token.cancel();
    final CursorNetworkFailure failure = await failureOf<CursorNetworkFailure>(
      stream.timeout(const Duration(seconds: 2)),
    );
    expect(failure.kind, 'cancel');
    expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
    unawaited(body.close());
  });

  test('a csrf failure mints a token and reopens the stream once', () async {
    server.replies.addAll(<ResponseBody Function()>[
      chunked(<List<int>>[
        utf8.encode('{"error":{"code":"invalid_csrf_token"}}'),
      ], status: 403),
      chunked(
        <List<int>>[utf8.encode('{}')],
        headers: <String, List<String>>{
          'set-cookie': <String>['csrf-token=fresh; Path=/'],
        },
      ),
      chunked(<List<int>>[endFrame()]),
    ]);
    await api.conversation('bc', null, updates.add);
    expect(server.seen, hasLength(3));
    expect(server.seen[0].headers['x-csrf-token'], 'old');
    expect(server.seen[1].uri.path, '/api/csrf-token');
    expect(server.seen[2].uri.path, streamPath);
    expect(server.seen[2].headers['x-csrf-token'], 'fresh');
    expect(updates.single.end, isTrue);
  });

  test('origin and blank cookie are rejected before the network', () async {
    final CursorApi blocked = CursorApi(
      cookie: () => fixtureCookie,
      webBase: mockBase,
      dio: Dio()..httpClientAdapter = server,
    );
    final CursorApi signedOut = CursorApi(
      cookie: () => ' ',
      webBase: mockBase,
      allowConfiguredOrigin: true,
      dio: Dio()..httpClientAdapter = server,
    );
    final ApiFailure origin = await failureOf<ApiFailure>(
      blocked.conversation('bc', null, updates.add),
    );
    final ApiFailure blank = await failureOf<ApiFailure>(
      signedOut.conversation('bc', null, updates.add),
    );
    expect(origin.code, 'origin_rejected');
    expect(blank.code, 'connection_required');
    expect(server.seen, isEmpty);
  });

  test('an HTTP failure maps the error body without the cookie', () async {
    server.replies.add(
      chunked(<List<int>>[
        utf8.encode(
          '{"error":{"code":"request_failed"},"echo":"$fixtureCookie"}',
        ),
      ], status: 500),
    );
    final ApiFailure failure = await failureOf<ApiFailure>(
      api.conversation('bc', null, updates.add),
    );
    expect(failure.status, 500);
    expect(failure.toString(), isNot(contains('session=')));
  });

  test('compressed and truncated frames fail without echoing data', () async {
    final Uint8List secret = Uint8List.fromList(utf8.encode('session=x'));
    server.replies.addAll(<ResponseBody Function()>[
      chunked(<List<int>>[envelope(1, secret)]),
      chunked(<List<int>>[envelope(0, secret).sublist(0, 7)]),
    ]);
    final FormatException compressed = await failureOf<FormatException>(
      api.conversation('bc', null, updates.add),
    );
    final FormatException truncated = await failureOf<FormatException>(
      api.conversation('bc', null, updates.add),
    );
    expect(compressed.message, 'Compressed frame');
    expect(truncated.message, 'Truncated frame');
    expect(compressed.toString(), isNot(contains('session')));
    expect(truncated.toString(), isNot(contains('session')));
  });

  group('endErrorCode', () {
    Uint8List trailer(String text) => Uint8List.fromList(utf8.encode(text));

    test('reads error.code and ignores everything else', () {
      expect(endErrorCode(trailer('{"error":{"code":"limit"}}')), 'limit');
      expect(endErrorCode(trailer('{"error":{"code":7}}')), '7');
      expect(endErrorCode(trailer('')), isNull);
      expect(endErrorCode(trailer('  ')), isNull);
      expect(endErrorCode(trailer('{}')), isNull);
      expect(endErrorCode(trailer('{"error":"x"}')), isNull);
      expect(endErrorCode(trailer('[1]')), isNull);
      expect(endErrorCode(trailer('not json')), isNull);
    });
  });
}
