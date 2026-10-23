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
const String offsetKey = 'last_message_activity_at_ms_offset';
const int pageOffset = 1699999999999;

/// The first-page body while Include archived is off, the Inbox default.
const Map<String, dynamic> firstPage = <String, dynamic>{
  'n': 50,
  'include_status': true,
  'include_archived': false,
  'include_pinned_state': true,
};
const Map<String, dynamic> secondPage = <String, dynamic>{
  ...firstPage,
  offsetKey: pageOffset,
};
const String twoAgents =
    '{"composers":[{"bcId":"bc-1","name":"Fix login","status":"FINISHED"},'
    '{"bcId":"bc-2","name":"Docs","status":"ERROR"}],'
    '"hasMore":true,"nextPageOffset":1699999999999}';

/// The last page; it repeats `bc-2` from [twoAgents].
const String pageTwo =
    '{"composers":[{"bcId":"bc-2","name":"Docs","status":"ERROR"},'
    '{"bcId":"bc-3","name":"Ship it","status":"RUNNING"}],'
    '"hasMore":false,"nextPageOffset":1600000000000}';

/// A first page served on refresh: one new agent and no more pages.
const String freshPage =
    '{"composers":[{"bcId":"bc-9","name":"Fresh start","status":"RUNNING"}]}';
const String leakyUnauthorized =
    '{"error":{"code":"unauthorized"},'
    '"echo":"Cookie: session=fake-cookie-value-123; '
    'Authorization: Bearer secret-value"}';
const String leakyServerError =
    '{"error":{"code":"Authorization: Bearer secret-value"}}';
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

/// Loads the first page in [container], then the next one, and returns the
/// resulting state.
Future<InboxAgents> loadTwoPages(ProviderContainer container) async {
  await container.read(inboxAgentsProvider.future);
  await container.read(inboxAgentsProvider.notifier).loadMore();
  return container.read(inboxAgentsProvider).requireValue;
}

/// Refreshes the list in [container] and returns the reloaded state.
Future<InboxAgents> refreshList(ProviderContainer container) {
  container.read(inboxAgentsProvider.notifier).refresh();
  return container.read(inboxAgentsProvider.future);
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

/// Scrolls to and taps the Inbox Load more button.
Future<void> tapLoadMore(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Load more'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Load more'));
  await tester.pumpAndSettle();
}

/// Scrolls to and taps the Inbox Refresh button.
Future<void> tapRefresh(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Refresh'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Refresh'));
  await tester.pumpAndSettle();
}

FilledButton loadMoreButton(WidgetTester tester) =>
    tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Load more'));

FilledButton refreshButton(WidgetTester tester) =>
    tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Refresh'));

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
      expect(result.hasMore, isFalse);
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
      expect(result.hasMore, isFalse);
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
      server.replies.add(const Reply(leakyServerError, status: 500));
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

  group('inbox agents paging', () {
    test('the first page keeps hasMore and nextPageOffset', () async {
      server.replies.add(const Reply(twoAgents));
      final ProviderContainer container = containerFor(
        await credentialsWithCookie(),
        server,
      );
      final InboxAgents result = await container.read(
        inboxAgentsProvider.future,
      );
      expect(result.hasMore, isTrue);
      expect(result.nextPageOffset, pageOffset);
      expect(result.loadingMore, isFalse);
      expect(result.canLoadMore, isTrue);
    });

    test('load more posts the offset and appends without repeats', () async {
      server.replies.addAll(const <Reply>[Reply(twoAgents), Reply(pageTwo)]);
      final ProviderContainer container = containerFor(
        await credentialsWithCookie(),
        server,
      );
      final InboxAgents result = await loadTwoPages(container);
      expect(ids(result.agents), <String>['bc-1', 'bc-2', 'bc-3']);
      expect(result.agents.last.name, 'Ship it');
      expect(result.errorMessage, isNull);
      expect(result.hasMore, isFalse);
      expect(result.nextPageOffset, isNull);
      expect(result.loadingMore, isFalse);
      expect(server.seen, hasLength(2));
      final Seen request = server.seen[1];
      expect(request.method, 'POST');
      expect(request.uri.path, listPath);
      expect(jsonDecode(request.body), secondPage);
      expect(request.headers['cookie'], fakeCookie);
      expect(request.headers.containsKey('authorization'), isFalse);
    });

    test('a string offset passes through unchanged', () async {
      server.replies.addAll(const <Reply>[
        Reply(
          '{"composers":[{"bcId":"bc-1"}],'
          '"hasMore":true,"nextPageOffset":"1699999999999"}',
        ),
        Reply('{"composers":[{"bcId":"bc-2"}]}'),
      ]);
      final ProviderContainer container = containerFor(
        await credentialsWithCookie(),
        server,
      );
      final InboxAgents result = await loadTwoPages(container);
      expect(ids(result.agents), <String>['bc-1', 'bc-2']);
      expect(result.hasMore, isFalse);
      expect(jsonDecode(server.seen[1].body), <String, dynamic>{
        ...firstPage,
        offsetKey: '1699999999999',
      });
    });

    test('the last page sends no more requests', () async {
      server.replies.add(const Reply(pageTwo));
      final ProviderContainer container = containerFor(
        await credentialsWithCookie(),
        server,
      );
      final InboxAgents result = await loadTwoPages(container);
      expect(ids(result.agents), <String>['bc-2', 'bc-3']);
      expect(result.hasMore, isFalse);
      expect(result.nextPageOffset, isNull);
      expect(server.seen, hasLength(1));
    });

    test('hasMore without an offset sends no more requests', () async {
      server.replies.add(
        const Reply('{"composers":[{"bcId":"bc-1"}],"hasMore":true}'),
      );
      final ProviderContainer container = containerFor(
        await credentialsWithCookie(),
        server,
      );
      final InboxAgents result = await loadTwoPages(container);
      expect(ids(result.agents), <String>['bc-1']);
      expect(result.hasMore, isFalse);
      expect(result.canLoadMore, isFalse);
      expect(server.seen, hasLength(1));
    });

    test('overlapping load more calls fetch one page', () async {
      server.replies.addAll(const <Reply>[Reply(twoAgents), Reply(pageTwo)]);
      final ProviderContainer container = containerFor(
        await credentialsWithCookie(),
        server,
      );
      await container.read(inboxAgentsProvider.future);
      final InboxAgentsNotifier notifier = container.read(
        inboxAgentsProvider.notifier,
      );
      await Future.wait(<Future<void>>[
        notifier.loadMore(),
        notifier.loadMore(),
      ]);
      final InboxAgents result = container.read(inboxAgentsProvider).requireValue;
      expect(ids(result.agents), <String>['bc-1', 'bc-2', 'bc-3']);
      expect(server.seen, hasLength(2));
    });

    test('without a cookie load more sends nothing', () async {
      final ProviderContainer container = containerFor(
        MemoryCredentials(),
        server,
      );
      final InboxAgents result = await loadTwoPages(container);
      expect(result.agents, isEmpty);
      expect(result.errorMessage, isNull);
      expect(result.hasMore, isFalse);
      expect(server.seen, isEmpty);
    });

    test('a failed next page keeps the agents and can be retried', () async {
      server.replies.addAll(const <Reply>[
        Reply(twoAgents),
        Reply(leakyUnauthorized, status: 401),
      ]);
      final ProviderContainer container = containerFor(
        await credentialsWithCookie(),
        server,
      );
      final InboxAgents failed = await loadTwoPages(container);
      expect(ids(failed.agents), <String>['bc-1', 'bc-2']);
      expect(failed.errorMessage, inboxReconnectError);
      expect(failed.hasMore, isTrue);
      expect(failed.nextPageOffset, pageOffset);
      expect(failed.canLoadMore, isTrue);
      final AsyncValue<InboxAgents> state = container.read(
        inboxAgentsProvider,
      );
      expect(state.hasError, isFalse);
      for (final String leak in leaks) {
        expect(failed.errorMessage, isNot(contains(leak)), reason: leak);
        expect(state.toString(), isNot(contains(leak)), reason: leak);
      }

      server.replies.add(const Reply(pageTwo));
      await container.read(inboxAgentsProvider.notifier).loadMore();
      final InboxAgents retried = container
          .read(inboxAgentsProvider)
          .requireValue;
      expect(ids(retried.agents), <String>['bc-1', 'bc-2', 'bc-3']);
      expect(retried.errorMessage, isNull);
      expect(retried.hasMore, isFalse);
      expect(server.seen, hasLength(3));
      expect(jsonDecode(server.seen[2].body), secondPage);
    });

    test('a network failure on the next page shows only the kind', () async {
      server.replies.add(const Reply(twoAgents));
      final ProviderContainer container = containerFor(
        await credentialsWithCookie(),
        server,
      );
      await container.read(inboxAgentsProvider.future);
      server.unreachable = true;
      await container.read(inboxAgentsProvider.notifier).loadMore();
      final InboxAgents result = container.read(inboxAgentsProvider).requireValue;
      expect(ids(result.agents), <String>['bc-1', 'bc-2']);
      expect(
        result.errorMessage,
        'Could not reach Cursor (connectionError). Check your connection.',
      );
      for (final String leak in leaks) {
        expect(result.errorMessage, isNot(contains(leak)), reason: leak);
        expect(result.toString(), isNot(contains(leak)), reason: leak);
      }
    });

    test('mergeInboxAgents skips repeated non-blank ids', () {
      const List<AgentSummary> before = <AgentSummary>[
        AgentSummary(bcId: 'bc-1'),
      ];
      const List<AgentSummary> page = <AgentSummary>[
        AgentSummary(bcId: 'bc-1', name: 'again'),
        AgentSummary(name: 'no id'),
        AgentSummary(bcId: ' ', name: 'blank id'),
        AgentSummary(bcId: 'bc-2'),
        AgentSummary(bcId: 'bc-2', name: 'again'),
      ];
      final List<AgentSummary> merged = mergeInboxAgents(before, page);
      expect(ids(merged), <String>['bc-1', '', ' ', 'bc-2']);
      expect(merged.first.name, isEmpty);
      expect(merged.last.name, isEmpty);
    });
  });

  group('inbox agents refresh', () {
    test('reloads the first page with no offset', () async {
      server.replies.addAll(const <Reply>[
        Reply(twoAgents),
        Reply(pageTwo),
        Reply(freshPage),
      ]);
      final ProviderContainer container = containerFor(
        await credentialsWithCookie(),
        server,
      );
      await loadTwoPages(container);
      final InboxAgents result = await refreshList(container);
      expect(ids(result.agents), <String>['bc-9']);
      expect(result.agents.single.name, 'Fresh start');
      expect(result.errorMessage, isNull);
      expect(result.hasMore, isFalse);
      expect(result.nextPageOffset, isNull);
      expect(server.seen, hasLength(3));
      final Seen request = server.seen[2];
      expect(request.method, 'POST');
      expect(request.uri.path, listPath);
      expect(jsonDecode(request.body), firstPage);
      expect(request.headers['cookie'], fakeCookie);
      expect(request.headers.containsKey('authorization'), isFalse);
    });

    test('recovers after a failed first load', () async {
      server.replies.addAll(const <Reply>[
        Reply(leakyUnauthorized, status: 401),
        Reply(twoAgents),
      ]);
      final ProviderContainer container = containerFor(
        await credentialsWithCookie(),
        server,
      );
      final InboxAgents failed = await container.read(
        inboxAgentsProvider.future,
      );
      expect(failed.errorMessage, inboxReconnectError);
      final InboxAgents result = await refreshList(container);
      expect(ids(result.agents), <String>['bc-1', 'bc-2']);
      expect(result.errorMessage, isNull);
      expect(result.hasMore, isTrue);
      expect(result.nextPageOffset, pageOffset);
      expect(server.seen, hasLength(2));
      expect(jsonDecode(server.seen[1].body), firstPage);
    });

    test('a failed refresh shows a safe error and leaks nothing', () async {
      server.replies.add(const Reply(twoAgents));
      final ProviderContainer container = containerFor(
        await credentialsWithCookie(),
        server,
      );
      await container.read(inboxAgentsProvider.future);
      server.unreachable = true;
      final InboxAgents result = await refreshList(container);
      expect(result.agents, isEmpty);
      expect(
        result.errorMessage,
        'Could not reach Cursor (connectionError). Check your connection.',
      );
      final AsyncValue<InboxAgents> state = container.read(
        inboxAgentsProvider,
      );
      expect(state.hasError, isFalse);
      for (final String leak in leaks) {
        expect(result.errorMessage, isNot(contains(leak)), reason: leak);
        expect(state.toString(), isNot(contains(leak)), reason: leak);
      }
      expect(server.seen, hasLength(2));
    });

    test('without a cookie refresh sends nothing', () async {
      final ProviderContainer container = containerFor(
        MemoryCredentials(),
        server,
      );
      await container.read(inboxAgentsProvider.future);
      final InboxAgents result = await refreshList(container);
      expect(result.agents, isEmpty);
      expect(result.errorMessage, isNull);
      expect(result.hasMore, isFalse);
      expect(server.seen, isEmpty);
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
      expect(find.text('Load more'), findsOneWidget);
      expect(loadMoreButton(tester).onPressed, isNotNull);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(server.seen, hasLength(1));
      expect(find.textContaining('fake-cookie-value-123'), findsNothing);
    });

    testWidgets('Load more appends the next page', (
      WidgetTester tester,
    ) async {
      server.replies.addAll(const <Reply>[Reply(twoAgents), Reply(pageTwo)]);
      await pumpInbox(tester, await credentialsWithCookie(), server);
      await tapLoadMore(tester);
      expect(tester.takeException(), isNull);
      expect(find.byType(AgentListTile), findsNWidgets(3));
      expect(find.text('Fix login'), findsOneWidget);
      expect(find.text('Docs'), findsOneWidget);
      expect(find.text('Ship it'), findsOneWidget);
      expect(find.text('Load more'), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(server.seen, hasLength(2));
      expect(jsonDecode(server.seen[1].body), secondPage);
    });

    testWidgets('a failed next page keeps the tiles and a safe error', (
      WidgetTester tester,
    ) async {
      server.replies.addAll(const <Reply>[
        Reply(twoAgents),
        Reply(leakyServerError, status: 500),
      ]);
      await pumpInbox(tester, await credentialsWithCookie(), server);
      await tapLoadMore(tester);
      expect(tester.takeException(), isNull);
      expect(find.byType(AgentListTile), findsNWidgets(2));
      expect(
        find.text('Could not load agents (HTTP 500 · request_failed).'),
        findsOneWidget,
      );
      expect(find.text('Load more'), findsOneWidget);
      expect(loadMoreButton(tester).onPressed, isNotNull);
      expect(server.seen, hasLength(2));
      for (final String leak in leaks) {
        expect(find.textContaining(leak), findsNothing, reason: leak);
      }
    });

    testWidgets('stays on the connect card without a cookie', (
      WidgetTester tester,
    ) async {
      await pumpInbox(tester, MemoryCredentials(), server);
      expect(find.text('Connect your workspace'), findsOneWidget);
      expect(find.byType(AgentListTile), findsNothing);
      expect(find.text('Load more'), findsNothing);
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
      expect(find.text('Load more'), findsNothing);
      for (final String leak in leaks) {
        expect(find.textContaining(leak), findsNothing, reason: leak);
      }
    });

    testWidgets('Refresh replaces the loaded pages with the first page', (
      WidgetTester tester,
    ) async {
      server.replies.addAll(const <Reply>[
        Reply(twoAgents),
        Reply(pageTwo),
        Reply(freshPage),
      ]);
      await pumpInbox(tester, await credentialsWithCookie(), server);
      expect(refreshButton(tester).onPressed, isNotNull);
      await tapLoadMore(tester);
      expect(find.byType(AgentListTile), findsNWidgets(3));
      await tapRefresh(tester);
      expect(tester.takeException(), isNull);
      expect(find.byType(AgentListTile), findsOneWidget);
      expect(find.text('Fresh start'), findsOneWidget);
      expect(find.text('Fix login'), findsNothing);
      expect(find.text('Ship it'), findsNothing);
      expect(find.text('Load more'), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(refreshButton(tester).onPressed, isNotNull);
      expect(server.seen, hasLength(3));
      expect(jsonDecode(server.seen[2].body), firstPage);
    });

    testWidgets('Refresh after a failed load shows the agents', (
      WidgetTester tester,
    ) async {
      server.replies.addAll(const <Reply>[
        Reply(leakyUnauthorized, status: 401),
        Reply(twoAgents),
      ]);
      await pumpInbox(tester, await credentialsWithCookie(), server);
      expect(find.text(inboxReconnectError), findsOneWidget);
      await tapRefresh(tester);
      expect(tester.takeException(), isNull);
      expect(find.text(inboxReconnectError), findsNothing);
      expect(find.byType(AgentListTile), findsNWidgets(2));
      expect(find.text('Fix login'), findsOneWidget);
      expect(server.seen, hasLength(2));
      for (final String leak in leaks) {
        expect(find.textContaining(leak), findsNothing, reason: leak);
      }
    });
  });
}
