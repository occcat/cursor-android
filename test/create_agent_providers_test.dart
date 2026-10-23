import 'dart:convert';
import 'dart:typed_data';

import 'package:cursor_android/app_router.dart';
import 'package:cursor_android/data/api_failure.dart';
import 'package:cursor_android/data/cookie_session_store.dart';
import 'package:cursor_android/data/credentials.dart';
import 'package:cursor_android/data/cursor_api.dart';
import 'package:cursor_android/providers/create_agent_providers.dart';
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
const String startPath = '/api/auth/startBackgroundComposerFromSnapshot';
const String repoUrl = 'https://github.com/occcat/demo';
const String detailPath = '/api/background-composer/get-detailed-composer';

/// The Agent page's first load after a successful start. It has no `bcId`,
/// so the page keeps the id it was opened with.
const String createdDetail =
    '{"composers":[{"composer":'
    '{"name":"Fix the login bug","status":"RUNNING"}}]}';
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

/// Opens the app on `/create` with [credentials] and [server].
Future<GoRouter> pumpCreate(
  WidgetTester tester,
  Credentials credentials,
  FakeServer server,
) async {
  final GoRouter router = createAppRouter(initialLocation: '/create');
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
  return router;
}

Finder startFinder() => find.widgetWithText(FilledButton, 'Start agent →');

FilledButton startButton(WidgetTester tester) =>
    tester.widget<FilledButton>(startFinder());

/// Types a prompt and one repository line into the form.
Future<void> fillForm(WidgetTester tester) async {
  await tester.enterText(
    find.byKey(const ValueKey<String>('create-agent-prompt')),
    '  Fix the login bug  ',
  );
  await tester.enterText(
    find.byKey(const ValueKey<String>('create-agent-repos')),
    '$repoUrl\n',
  );
  await tester.pump();
}

/// Scrolls to and taps `Start agent →`.
Future<void> tapStart(WidgetTester tester) async {
  await tester.ensureVisible(startFinder());
  await tester.pumpAndSettle();
  await tester.tap(startFinder());
  await tester.pumpAndSettle();
}

void main() {
  late FakeServer server;

  setUp(() {
    server = FakeServer();
  });

  group('createAgentErrorMessage', () {
    test('a 401 or a missing cookie asks to reconnect', () {
      expect(
        createAgentErrorMessage(const ApiFailure(401, 'unauthorized')),
        createAgentReconnectError,
      );
      expect(
        createAgentErrorMessage(const ApiFailure(0, 'connection_required')),
        createAgentReconnectError,
      );
    });

    test('other API failures show only the status and code', () {
      expect(
        createAgentErrorMessage(const ApiFailure(429, 'rate_limited')),
        'Could not start the agent (HTTP 429 · rate_limited).',
      );
    });

    test('network failures show only the error kind', () {
      expect(
        createAgentErrorMessage(const CursorNetworkFailure('receiveTimeout')),
        'Could not reach Cursor (receiveTimeout). Check your connection.',
      );
    });

    test('secret-looking or unknown errors become the generic text', () {
      expect(
        createAgentErrorMessage(const ApiFailure(403, 'invalid_csrf_token')),
        genericInboxError,
      );
      expect(
        createAgentErrorMessage(StateError('Cookie: $fakeCookie')),
        genericInboxError,
      );
    });
  });

  group('router New agent', () {
    testWidgets('starts the agent once and opens its page', (
      WidgetTester tester,
    ) async {
      server.replies.addAll(const <Reply>[Reply('{}'), Reply(createdDetail)]);
      final GoRouter router = await pumpCreate(
        tester,
        await credentialsWithCookie(),
        server,
      );
      expect(startButton(tester).onPressed, isNull);
      await fillForm(tester);
      expect(startButton(tester).onPressed, isNotNull);
      await tapStart(tester);
      expect(tester.takeException(), isNull);

      expect(server.seen, hasLength(2));
      final Seen request = server.seen.first;
      expect(request.method, 'POST');
      expect(request.uri.path, startPath);
      expect(request.headers['cookie'], fakeCookie);
      expect(request.headers.containsKey('authorization'), isFalse);
      final Map<String, dynamic> body =
          jsonDecode(request.body) as Map<String, dynamic>;
      final String bcId = body['bcId'] as String;
      expect(bcId, matches(RegExp(r'^bc-[0-9a-f]{32}$')));
      expect(body, <String, dynamic>{
        'bcId': bcId,
        'prompt': 'Fix the login bug',
        'repoUrl': repoUrl,
        'expectedScope': 'personal',
      });

      final Seen detail = server.seen.last;
      expect(detail.method, 'POST');
      expect(detail.uri.path, detailPath);
      expect(jsonDecode(detail.body), <String, dynamic>{
        'bcId': bcId,
        'n': 1,
        'includeTeamWide': true,
      });

      expect(
        router.routerDelegate.currentConfiguration.uri.path,
        '/agent/$bcId',
      );
      expect(find.text('Fix the login bug'), findsOneWidget);
      expect(find.text('Loading this workspace…'), findsNothing);
      expect(find.text('What should we build?'), findsNothing);
    });

    testWidgets('a failed start keeps the form and shows a safe error', (
      WidgetTester tester,
    ) async {
      server.replies.add(const Reply(leakyServerError, status: 500));
      final GoRouter router = await pumpCreate(
        tester,
        await credentialsWithCookie(),
        server,
      );
      await fillForm(tester);
      await tapStart(tester);
      expect(tester.takeException(), isNull);
      expect(
        find.text('Could not start the agent (HTTP 500 · request_failed).'),
        findsOneWidget,
      );
      expect(router.routerDelegate.currentConfiguration.uri.path, '/create');
      expect(find.text('What should we build?'), findsOneWidget);
      expect(startButton(tester).onPressed, isNotNull);
      expect(server.seen, hasLength(1));
      for (final String leak in leaks) {
        expect(find.textContaining(leak), findsNothing, reason: leak);
      }
    });

    testWidgets('a 401 asks to reconnect and leaks nothing', (
      WidgetTester tester,
    ) async {
      server.replies.add(const Reply(leakyUnauthorized, status: 401));
      await pumpCreate(tester, await credentialsWithCookie(), server);
      await fillForm(tester);
      await tapStart(tester);
      expect(tester.takeException(), isNull);
      expect(find.text(createAgentReconnectError), findsOneWidget);
      expect(server.seen, hasLength(1));
      for (final String leak in leaks) {
        expect(find.textContaining(leak), findsNothing, reason: leak);
      }
    });

    testWidgets('a network failure shows only the error kind', (
      WidgetTester tester,
    ) async {
      server.unreachable = true;
      await pumpCreate(tester, await credentialsWithCookie(), server);
      await fillForm(tester);
      await tapStart(tester);
      expect(tester.takeException(), isNull);
      expect(
        find.text(
          'Could not reach Cursor (connectionError). Check your connection.',
        ),
        findsOneWidget,
      );
      expect(server.seen, hasLength(1));
      for (final String leak in leaks) {
        expect(find.textContaining(leak), findsNothing, reason: leak);
      }
    });

    testWidgets('without a cookie Start stays disabled and sends nothing', (
      WidgetTester tester,
    ) async {
      await pumpCreate(tester, MemoryCredentials(), server);
      await fillForm(tester);
      expect(startButton(tester).onPressed, isNull);
      expect(server.seen, isEmpty);
    });
  });
}
