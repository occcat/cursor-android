import 'dart:convert';
import 'dart:typed_data';

import 'package:cursor_android/app_router.dart';
import 'package:cursor_android/data/api_failure.dart';
import 'package:cursor_android/data/cookie_session_store.dart';
import 'package:cursor_android/data/credentials.dart';
import 'package:cursor_android/data/cursor_api.dart';
import 'package:cursor_android/domain/agent_summary.dart';
import 'package:cursor_android/providers/cursor_api_providers.dart';
import 'package:cursor_android/providers/inbox_agents_providers.dart';
import 'package:cursor_android/providers/session_providers.dart';
import 'package:cursor_android/ui/agent_list_tile.dart';
import 'package:cursor_android/ui/inbox_page.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

const String fakeCookie = 'session=fake-cookie-value-123; csrf-token=old';
final Uri mockBase = Uri.parse('http://127.0.0.1:8080/');
const String listPath = '/api/background-composer/list';
const Map<String, dynamic> firstPage = <String, dynamic>{
  'n': 50,
  'include_status': true,
  'include_archived': true,
  'include_pinned_state': true,
};
const String twoAgents =
    '{"composers":[{"bcId":"bc-1","name":"Fix login","status":"FINISHED"},'
    '{"bcId":"bc-2","name":"Docs","status":"ERROR"}],'
    '"hasMore":true,"nextPageOffset":1699999999999}';
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

ProviderContainer containerFor(Credentials credentials, FakeServer server) {
  final ProviderContainer container = ProviderContainer(
    overrides: [
      credentialsProvider.overrideWithValue(credentials),
      cursorApiProvider.overrideWith((Ref ref) => fakeApi(ref, server)),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Future<void> pumpInbox(
  WidgetTester tester,
  Credentials credentials,
  FakeServer server,
) async {
  final GoRouter router = createAppRouter();
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

List<String> ids(List<AgentSummary> agents) =>
    <String>[for (final AgentSummary agent in agents) agent.bcId];

void main() {
  late FakeServer server;

  setUp(() {
    server = FakeServer();
  });

  group('cursorApiProvider', () {
    test('targets production and reads the stored cookie', () async {
      final ProviderContainer container = ProviderContainer(
        overrides: [
          credentialsProvider.overrideWithValue(await credentialsWithCookie()),
        ],
      );
      addTearDown(container.dispose);
      final CursorApi api = container.read(cursorApiProvider);
      expect(api.webBase, Uri.parse('https://cursor.com/'));
      expect(api.allowConfiguredOrigin, isFalse);
      expect(await api.cookie(), fakeCookie);
      expect(api.toString(), isNot(contains('fake-cookie-value-123')));
    });
  });

  group('inboxAgentsProvider', () {
    test('loads the first page with the stored cookie', () async {
      server.replies.add(const Reply(twoAgents));
      final ProviderContainer container = containerFor(
        await credentialsWithCookie(),
        server,
      );
      final InboxAgents result = await container.read(
        inboxAgentsProvider.future,
      );
      expect(result.errorMessage, isNull);
      expect(ids(result.agents), <String>['bc-1', 'bc-2']);
      expect(result.agents.first.name, 'Fix login');
      final Seen request = server.seen.single;
      expect(request.method, 'POST');
      expect(request.uri.path, listPath);
      expect(jsonDecode(request.body), firstPage);
      expect(request.headers['cookie'], fakeCookie);
      expect(request.headers.containsKey('authorization'), isFalse);
    });

    test('is empty and quiet without a cookie and sends nothing', () async {
      final ProviderContainer container = containerFor(
        MemoryCredentials(),
        server,
      );
      final InboxAgents result = await container.read(
        inboxAgentsProvider.future,
      );
      expect(result.agents, isEmpty);
      expect(result.errorMessage, isNull);
      expect(server.seen, isEmpty);
    });

    test('a 401 asks to reconnect and leaks nothing', () async {
      server.replies.add(const Reply(leakyUnauthorized, status: 401));
      final ProviderContainer container = containerFor(
        await credentialsWithCookie(),
        server,
      );
      final InboxAgents result = await container.read(
        inboxAgentsProvider.future,
      );
      expect(result.agents, isEmpty);
      expect(result.errorMessage, inboxReconnectError);
      final AsyncValue<InboxAgents> state = container.read(
        inboxAgentsProvider,
      );
      expect(state.hasError, isFalse);
      for (final String leak in leaks) {
        expect(result.errorMessage, isNot(contains(leak)), reason: leak);
        expect(state.toString(), isNot(contains(leak)), reason: leak);
      }
    });

    test('other API failures show only the status and safe code', () async {
      server.replies.add(
        const Reply(
          '{"error":{"code":"Authorization: Bearer secret-value"}}',
          status: 500,
        ),
      );
      final ProviderContainer container = containerFor(
        await credentialsWithCookie(),
        server,
      );
      final InboxAgents result = await container.read(
        inboxAgentsProvider.future,
      );
      expect(
        result.errorMessage,
        'Could not load agents (HTTP 500 · request_failed).',
      );
    });

    test('a body that is not an object shows invalid_body', () async {
      server.replies.add(const Reply('[{"bcId":"bc-1"}]'));
      final ProviderContainer container = containerFor(
        await credentialsWithCookie(),
        server,
      );
      final InboxAgents result = await container.read(
        inboxAgentsProvider.future,
      );
      expect(result.agents, isEmpty);
      expect(
        result.errorMessage,
        'Could not load agents (HTTP 200 · invalid_body).',
      );
    });

    test('a network failure shows only the error kind', () async {
      server.unreachable = true;
      final ProviderContainer container = containerFor(
        await credentialsWithCookie(),
        server,
      );
      final InboxAgents result = await container.read(
        inboxAgentsProvider.future,
      );
      expect(
        result.errorMessage,
        'Could not reach Cursor (connectionError). Check your connection.',
      );
      for (final String leak in leaks) {
        expect(result.errorMessage, isNot(contains(leak)), reason: leak);
      }
    });
  });

  group('inboxAgentsErrorMessage', () {
    test('a missing cookie asks to reconnect', () {
      expect(
        inboxAgentsErrorMessage(const ApiFailure(401, 'connection_required')),
        inboxReconnectError,
      );
      expect(
        inboxAgentsErrorMessage(const ApiFailure(0, 'connection_required')),
        inboxReconnectError,
      );
    });

    test('secret-looking or unknown errors become the generic text', () {
      expect(
        inboxAgentsErrorMessage(const ApiFailure(403, 'invalid_csrf_token')),
        genericInboxError,
      );
      expect(
        inboxAgentsErrorMessage(StateError('Cookie: $fakeCookie')),
        genericInboxError,
      );
    });
  });

  group('router Inbox agents', () {
    testWidgets('shows the first page as agent tiles', (
      WidgetTester tester,
    ) async {
      server.replies.add(const Reply(twoAgents));
      await pumpInbox(tester, await credentialsWithCookie(), server);
      expect(find.byType(AgentListTile), findsNWidgets(2));
      expect(find.text('Fix login'), findsOneWidget);
      expect(find.text('Docs'), findsOneWidget);
      expect(find.text('No agents here yet. Start with a task.'), findsNothing);
      expect(find.text('Load more'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(server.seen, hasLength(1));
      expect(find.textContaining('fake-cookie-value-123'), findsNothing);
    });

    testWidgets('stays on the connect card without a cookie', (
      WidgetTester tester,
    ) async {
      await pumpInbox(tester, MemoryCredentials(), server);
      expect(find.text('Connect your workspace'), findsOneWidget);
      expect(find.byType(AgentListTile), findsNothing);
      expect(server.seen, isEmpty);
    });

    testWidgets('shows a safe error for a failed load', (
      WidgetTester tester,
    ) async {
      server.replies.add(const Reply(leakyUnauthorized, status: 401));
      await pumpInbox(tester, await credentialsWithCookie(), server);
      expect(tester.takeException(), isNull);
      expect(find.text(inboxReconnectError), findsOneWidget);
      expect(find.byType(AgentListTile), findsNothing);
      for (final String leak in leaks) {
        expect(find.textContaining(leak), findsNothing, reason: leak);
      }
    });
  });
}
