import 'dart:convert';
import 'dart:typed_data';

import 'package:cursor_android/app_router.dart';
import 'package:cursor_android/data/api_failure.dart';
import 'package:cursor_android/data/cookie_session_store.dart';
import 'package:cursor_android/data/credentials.dart';
import 'package:cursor_android/data/cursor_api.dart';
import 'package:cursor_android/providers/agent_detail_providers.dart';
import 'package:cursor_android/providers/cursor_api_providers.dart';
import 'package:cursor_android/providers/session_providers.dart';
import 'package:cursor_android/ui/inbox_page.dart' show genericInboxError;
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

const String fakeCookie = 'session=fake-cookie-value-123; csrf-token=old';
final Uri mockBase = Uri.parse('http://127.0.0.1:8080/');
const String agentId = 'bc-1';
const String detailPath = '/api/background-composer/get-detailed-composer';
const Map<String, dynamic> detailBody = <String, dynamic>{
  'bcId': agentId,
  'n': 1,
  'includeTeamWide': true,
};
const String running =
    '{"composers":[{"composer":'
    '{"bcId":"bc-1","name":"Fix login","status":"RUNNING"}}]}';
const String archived =
    '{"composers":[{"composer":'
    '{"bcId":"bc-1","name":"Fix login","status":"ARCHIVED"}}]}';
const String leakyServerError =
    '{"error":{"code":"Authorization: Bearer secret-value"}}';
const String leakyUnauthorized =
    '{"error":{"code":"unauthorized"},'
    '"echo":"Cookie: session=fake-cookie-value-123; '
    'Authorization: Bearer secret-value"}';
const List<String> leaks = <String>[
  'Cookie',
  'Authorization',
  'Bearer',
  'fake-cookie-value-123',
  'csrf-token',
  'secret-value',
];

/// A queued fake response.
class Reply {
  const Reply(this.body, {this.status = 200});

  final String body;
  final int status;
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

/// In-memory server that answers queued replies in order, or fails every
/// request with a connection error that quotes the cookie when
/// [unreachable].
class FakeServer implements HttpClientAdapter {
  final List<Reply> replies = <Reply>[];
  final List<Seen> seen = <Seen>[];
  bool unreachable = false;

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
    if (unreachable) {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
        message: 'Cookie: $fakeCookie',
      );
    }
    final Reply reply = replies.removeAt(0);
    return ResponseBody.fromString(reply.body, reply.status);
  }

  @override
  void close({bool force = false}) {}
}

Future<MemoryCredentials> credentialsWithCookie() async {
  final MemoryCredentials credentials = MemoryCredentials();
  await credentials.write(kCookieName, fakeCookie);
  return credentials;
}

/// A [CursorApi] on [server] that reads the cookie from the shared store.
CursorApi fakeApi(Ref ref, FakeServer server) {
  final CookieSessionStore store = ref.watch(cookieSessionStoreProvider);
  return CursorApi(
    cookie: store.readCookie,
    webBase: mockBase,
    allowConfiguredOrigin: true,
    dio: Dio()..httpClientAdapter = server,
  );
}

/// Opens the app on `/agent/bc-1` with [credentials] and [server].
Future<void> pumpAgent(
  WidgetTester tester,
  Credentials credentials,
  FakeServer server,
) async {
  final GoRouter router = createAppRouter(initialLocation: '/agent/$agentId');
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        credentialsProvider.overrideWithValue(credentials),
        cursorApiProvider.overrideWith((Ref ref) => fakeApi(ref, server)),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

Finder chip(String label) => find.widgetWithText(ActionChip, label);

Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// Taps the [label] chip and confirms the dialog.
Future<void> confirmChip(WidgetTester tester, String label) async {
  await tapVisible(tester, chip(label));
  await tapVisible(tester, find.text('Confirm'));
}

void expectNoLeaks() {
  for (final String leak in leaks) {
    expect(find.textContaining(leak), findsNothing, reason: leak);
  }
}

void main() {
  late FakeServer server;

  setUp(() {
    server = FakeServer();
  });

  group('normalizeComposer', () {
    test('reads the nested composer and keeps its fields', () {
      final Map<String, dynamic> root = <String, dynamic>{
        'composers': <Object?>[
          'skipped',
          <String, dynamic>{
            'bcId': 'bc-outer',
            'composer': <String, dynamic>{
              'bcId': agentId,
              'name': 'Fix login',
              'status': 'RUNNING',
              'repoUrl': 'https://github.com/o/r',
            },
          },
        ],
      };
      final Map<String, dynamic> agent = normalizeComposer(agentId, root);
      expect(agent, <String, dynamic>{
        'bcId': agentId,
        'name': 'Fix login',
        'status': 'RUNNING',
        'repoUrl': 'https://github.com/o/r',
      });
    });

    test('falls back to the entry fields and then to the id', () {
      expect(
        normalizeComposer(agentId, <String, dynamic>{
          'composers': <Object?>[
            <String, dynamic>{
              'name': 'Docs',
              'status': 'FINISHED',
              'composer': <String, dynamic>{'name': ' '},
            },
          ],
        }),
        <String, dynamic>{
          'bcId': agentId,
          'name': 'Docs',
          'status': 'FINISHED',
        },
      );
      expect(
        normalizeComposer(agentId, <String, dynamic>{}),
        <String, dynamic>{'bcId': agentId, 'name': '', 'status': ''},
      );
    });
  });

  group('agentDetailErrorMessage', () {
    test('a 401 or a missing cookie asks to reconnect', () {
      expect(
        agentDetailErrorMessage(const ApiFailure(401, 'unauthorized')),
        agentDetailReconnectError,
      );
      expect(
        agentDetailErrorMessage(const ApiFailure(0, 'connection_required')),
        agentDetailReconnectError,
      );
    });

    test('other failures name the action and stay safe', () {
      expect(
        agentDetailErrorMessage(
          const ApiFailure(500, 'request_failed'),
          action: 'pause the agent',
        ),
        'Could not pause the agent (HTTP 500 · request_failed).',
      );
      expect(
        agentDetailErrorMessage(const CursorNetworkFailure('receiveTimeout')),
        'Could not reach Cursor (receiveTimeout). Check your connection.',
      );
      expect(
        agentDetailErrorMessage(const ApiFailure(403, 'invalid_csrf_token')),
        genericInboxError,
      );
      expect(
        agentDetailErrorMessage(StateError('Cookie: $fakeCookie')),
        genericInboxError,
      );
    });
  });

  group('router Agent detail', () {
    testWidgets('loads the agent with the stored cookie', (
      WidgetTester tester,
    ) async {
      server.replies.add(const Reply(running));
      await pumpAgent(tester, await credentialsWithCookie(), server);
      expect(tester.takeException(), isNull);
      expect(find.text('Fix login'), findsOneWidget);
      expect(find.text('RUNNING'), findsOneWidget);
      expect(find.text('Loading this workspace…'), findsNothing);
      final Seen request = server.seen.single;
      expect(request.method, 'POST');
      expect(request.uri.path, detailPath);
      expect(request.json, detailBody);
      expect(request.headers['cookie'], fakeCookie);
      expect(request.headers.containsKey('authorization'), isFalse);
    });

    testWidgets('a failed load shows a safe error and Retry reloads', (
      WidgetTester tester,
    ) async {
      server.replies.add(const Reply(leakyUnauthorized, status: 401));
      await pumpAgent(tester, await credentialsWithCookie(), server);
      expect(tester.takeException(), isNull);
      expect(find.text(agentDetailReconnectError), findsOneWidget);
      expect(find.text('Loading this workspace…'), findsOneWidget);
      expectNoLeaks();

      server.replies.add(const Reply(running));
      await tapVisible(tester, chip('Retry'));
      expect(find.text('Fix login'), findsOneWidget);
      expect(find.text(agentDetailReconnectError), findsNothing);
      expect(server.seen, hasLength(2));
      expect(server.seen[1].uri.path, detailPath);
    });

    testWidgets('Refresh reloads and keeps the agent on a network error', (
      WidgetTester tester,
    ) async {
      server.replies.add(const Reply(running));
      await pumpAgent(tester, await credentialsWithCookie(), server);
      server.unreachable = true;
      await tapVisible(tester, chip('Refresh'));
      expect(tester.takeException(), isNull);
      expect(find.text('Fix login'), findsOneWidget);
      expect(
        find.text(
          'Could not reach Cursor (connectionError). Check your connection.',
        ),
        findsOneWidget,
      );
      expect(server.seen, hasLength(2));
      expectNoLeaks();
    });

    testWidgets('Send follow-up posts the trimmed text and reloads', (
      WidgetTester tester,
    ) async {
      server.replies.addAll(const <Reply>[
        Reply(running),
        Reply('{}'),
        Reply(running),
      ]);
      await pumpAgent(tester, await credentialsWithCookie(), server);
      await tester.enterText(
        find.byKey(const ValueKey<String>('agent-follow-up')),
        '  Add tests  ',
      );
      await tester.pump();
      await tapVisible(
        tester,
        find.widgetWithText(FilledButton, 'Send follow-up'),
      );
      expect(tester.takeException(), isNull);
      expect(server.seen, hasLength(3));
      final Seen request = server.seen[1];
      expect(request.uri.path, '/api/auth/addAsyncFollowupBackgroundComposer');
      final Map<String, dynamic> body = request.json;
      expect(body['followupId'], matches(RegExp(r'^fu-[0-9a-f]{32}$')));
      expect(body, <String, dynamic>{
        'bcId': agentId,
        'followup': 'Add tests',
        'followupMessage': 'Add tests',
        'followupId': body['followupId'],
        'expectedScope': 'personal',
      });
      expect(request.headers['cookie'], fakeCookie);
      expect(server.seen[2].uri.path, detailPath);
    });

    testWidgets('Pause posts the id and an empty reply reads unavailable', (
      WidgetTester tester,
    ) async {
      server.replies.addAll(const <Reply>[
        Reply(running),
        Reply('{}'),
        Reply(running),
      ]);
      await pumpAgent(tester, await credentialsWithCookie(), server);
      await confirmChip(tester, 'Pause');
      expect(tester.takeException(), isNull);
      expect(server.seen[1].uri.path, '/api/background-composer/pause');
      expect(server.seen[1].json, <String, dynamic>{'bcId': agentId});
      expect(server.seen, hasLength(3));
      expect(chip('Pause unavailable'), findsOneWidget);
      expect(
        find.text('This response cannot pause the agent.'),
        findsOneWidget,
      );
    });

    testWidgets('Archive and Restore post and reload the status', (
      WidgetTester tester,
    ) async {
      server.replies.addAll(const <Reply>[
        Reply(running),
        Reply('{}'),
        Reply(archived),
        Reply('{}'),
        Reply(running),
      ]);
      await pumpAgent(tester, await credentialsWithCookie(), server);
      await confirmChip(tester, 'Archive');
      expect(server.seen[1].uri.path, '/api/auth/archiveBackgroundComposer');
      expect(server.seen[1].json, <String, dynamic>{'bcId': agentId});
      expect(chip('Restore'), findsOneWidget);
      expect(find.text('ARCHIVED'), findsOneWidget);

      await confirmChip(tester, 'Restore');
      expect(tester.takeException(), isNull);
      expect(server.seen[3].uri.path, '/api/auth/archiveBackgroundComposer');
      expect(server.seen[3].json, <String, dynamic>{
        'bcId': agentId,
        'unarchive': true,
      });
      expect(chip('Archive'), findsOneWidget);
      expect(server.seen, hasLength(5));
    });

    testWidgets('a failed action keeps the agent and skips the reload', (
      WidgetTester tester,
    ) async {
      server.replies.addAll(const <Reply>[
        Reply(running),
        Reply(leakyServerError, status: 500),
      ]);
      await pumpAgent(tester, await credentialsWithCookie(), server);
      await confirmChip(tester, 'Archive');
      expect(tester.takeException(), isNull);
      expect(
        find.text('Could not archive the agent (HTTP 500 · request_failed).'),
        findsOneWidget,
      );
      expect(find.text('Fix login'), findsOneWidget);
      expect(chip('Archive'), findsOneWidget);
      expect(server.seen, hasLength(2));
      expectNoLeaks();
    });

    testWidgets('stays on the loading state without a cookie', (
      WidgetTester tester,
    ) async {
      await pumpAgent(tester, MemoryCredentials(), server);
      expect(find.text('Loading this workspace…'), findsOneWidget);
      expect(tester.widget<ActionChip>(chip('Retry')).onPressed, isNull);
      expect(server.seen, isEmpty);
    });
  });
}
