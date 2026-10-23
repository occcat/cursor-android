import 'dart:convert';
import 'dart:typed_data';

import 'package:cursor_android/app_router.dart';
import 'package:cursor_android/data/api_failure.dart';
import 'package:cursor_android/data/cookie_session_store.dart';
import 'package:cursor_android/data/credentials.dart';
import 'package:cursor_android/data/cursor_api.dart';
import 'package:cursor_android/domain/agent_summary.dart';
import 'package:cursor_android/domain/preferences.dart';
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
const String archivePath = '/api/auth/archiveBackgroundComposer';
const String active =
    '{"composers":[{"bcId":"bc-1","name":"Fix login","status":"RUNNING"},'
    '{"bcId":"bc-3","name":"Docs","status":"FINISHED"}]}';
const String activeAfterArchive =
    '{"composers":[{"bcId":"bc-3","name":"Docs","status":"FINISHED"}]}';
const String withArchived =
    '{"composers":[{"bcId":"bc-1","name":"Fix login","status":"RUNNING"},'
    '{"bcId":"bc-2","name":"Old login page","status":"ARCHIVED"}]}';
const String withRestored =
    '{"composers":[{"bcId":"bc-1","name":"Fix login","status":"RUNNING"},'
    '{"bcId":"bc-2","name":"Old login page","status":"FINISHED"}]}';
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

Future<void> pumpInbox(WidgetTester tester, FakeServer server) async {
  final GoRouter router = createAppRouter();
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        credentialsProvider.overrideWithValue(await credentialsWithCookie()),
        cursorApiProvider.overrideWith((Ref ref) => fakeApi(ref, server)),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// The text button labelled [label] on the card titled [title].
Finder cardButton(String title, String label) => find.descendant(
  of: find.widgetWithText(AgentListTile, title),
  matching: find.widgetWithText(TextButton, label),
);

Future<void> toggleArchived(WidgetTester tester) =>
    tapVisible(tester, find.widgetWithText(FilterChip, 'Include archived'));

bool includeArchivedSent(Seen request) =>
    request.json['include_archived'] as bool;

void main() {
  late FakeServer server;

  setUp(() {
    server = FakeServer();
  });

  group('listInboxPage', () {
    test('sends include_archived from the choice and the offset', () async {
      server.replies.addAll(const <Reply>[Reply('{}'), Reply('{}')]);
      final CursorApi api = CursorApi(
        cookie: () => fakeCookie,
        webBase: mockBase,
        allowConfiguredOrigin: true,
        dio: Dio()..httpClientAdapter = server,
      );
      await listInboxPage(api, includeArchived: false);
      await listInboxPage(api, includeArchived: true, offset: 42);
      expect(server.seen[0].uri.path, listPath);
      expect(server.seen[0].json, <String, dynamic>{
        'n': 50,
        'include_status': true,
        'include_archived': false,
        'include_pinned_state': true,
      });
      expect(server.seen[1].json, <String, dynamic>{
        'n': 50,
        'include_status': true,
        'include_archived': true,
        'include_pinned_state': true,
        'last_message_activity_at_ms_offset': 42,
      });
    });
  });

  group('inboxActionErrorMessage', () {
    test('names the action and stays safe', () {
      expect(
        inboxActionErrorMessage(
          const ApiFailure(500, 'request_failed'),
          action: 'archive the agent',
        ),
        'Could not archive the agent (HTTP 500 · request_failed).',
      );
      expect(
        inboxActionErrorMessage(
          const ApiFailure(401, 'unauthorized'),
          action: 'restore the agent',
        ),
        inboxReconnectError,
      );
      expect(
        inboxActionErrorMessage(
          StateError('Cookie: $fakeCookie'),
          action: 'archive the agent',
        ),
        genericInboxError,
      );
    });
  });

  group('router Include archived', () {
    testWidgets('the first load asks the server without archived agents', (
      WidgetTester tester,
    ) async {
      server.replies.add(const Reply(active));
      await pumpInbox(tester, server);
      expect(server.seen.single.uri.path, listPath);
      expect(includeArchivedSent(server.seen.single), isFalse);
      expect(find.text('Fix login'), findsOneWidget);
    });

    testWidgets('turning it on and off reloads from the server', (
      WidgetTester tester,
    ) async {
      server.replies.addAll(const <Reply>[
        Reply(active),
        Reply(withArchived),
        Reply(active),
      ]);
      await pumpInbox(tester, server);
      expect(find.text('Old login page'), findsNothing);

      await toggleArchived(tester);
      expect(tester.takeException(), isNull);
      expect(server.seen, hasLength(2));
      expect(includeArchivedSent(server.seen[1]), isTrue);
      expect(find.text('Old login page'), findsOneWidget);
      expect(
        tester
            .widget<FilterChip>(
              find.widgetWithText(FilterChip, 'Include archived'),
            )
            .selected,
        isTrue,
      );

      await toggleArchived(tester);
      expect(server.seen, hasLength(3));
      expect(includeArchivedSent(server.seen[2]), isFalse);
      expect(find.text('Old login page'), findsNothing);
      expect(find.text('Docs'), findsOneWidget);
    });
  });

  group('router card archive', () {
    testWidgets('Archive posts the id, then reloads without the agent', (
      WidgetTester tester,
    ) async {
      server.replies.addAll(const <Reply>[
        Reply(active),
        Reply('{}'),
        Reply(activeAfterArchive),
      ]);
      await pumpInbox(tester, server);
      await tapVisible(tester, cardButton('Fix login', 'Archive'));
      expect(find.text('Archive this agent?'), findsOneWidget);
      await tapVisible(tester, find.text('Confirm'));
      expect(tester.takeException(), isNull);
      expect(server.seen, hasLength(3));
      expect(server.seen[1].method, 'POST');
      expect(server.seen[1].uri.path, archivePath);
      expect(server.seen[1].json, <String, dynamic>{'bcId': 'bc-1'});
      expect(server.seen[1].headers['cookie'], fakeCookie);
      expect(server.seen[1].headers.containsKey('authorization'), isFalse);
      expect(server.seen[2].uri.path, listPath);
      expect(includeArchivedSent(server.seen[2]), isFalse);
      expect(find.text('Fix login'), findsNothing);
      expect(find.text('Docs'), findsOneWidget);
    });

    testWidgets('Keep sends nothing', (WidgetTester tester) async {
      server.replies.add(const Reply(active));
      await pumpInbox(tester, server);
      await tapVisible(tester, cardButton('Fix login', 'Archive'));
      await tapVisible(tester, find.text('Keep'));
      expect(server.seen, hasLength(1));
      expect(find.text('Fix login'), findsOneWidget);
    });

    testWidgets('Restore posts unarchive and the card offers Archive again', (
      WidgetTester tester,
    ) async {
      server.replies.addAll(const <Reply>[
        Reply(active),
        Reply(withArchived),
        Reply('{}'),
        Reply(withRestored),
      ]);
      await pumpInbox(tester, server);
      await toggleArchived(tester);
      expect(cardButton('Old login page', 'Restore'), findsOneWidget);
      await tapVisible(tester, cardButton('Old login page', 'Restore'));
      expect(find.text('Restore this agent?'), findsOneWidget);
      await tapVisible(tester, find.text('Confirm'));
      expect(tester.takeException(), isNull);
      expect(server.seen, hasLength(4));
      expect(server.seen[2].uri.path, archivePath);
      expect(server.seen[2].json, <String, dynamic>{
        'bcId': 'bc-2',
        'unarchive': true,
      });
      expect(includeArchivedSent(server.seen[3]), isTrue);
      expect(cardButton('Old login page', 'Archive'), findsOneWidget);
      expect(cardButton('Old login page', 'Restore'), findsNothing);
    });

    testWidgets('a failed archive keeps the card and skips the reload', (
      WidgetTester tester,
    ) async {
      server.replies.addAll(const <Reply>[
        Reply(active),
        Reply(leakyServerError, status: 500),
      ]);
      await pumpInbox(tester, server);
      await tapVisible(tester, cardButton('Fix login', 'Archive'));
      await tapVisible(tester, find.text('Confirm'));
      expect(tester.takeException(), isNull);
      expect(
        find.text('Could not archive the agent (HTTP 500 · request_failed).'),
        findsOneWidget,
      );
      expect(find.text('Fix login'), findsOneWidget);
      expect(cardButton('Fix login', 'Archive'), findsOneWidget);
      expect(server.seen, hasLength(2));
      for (final String leak in leaks) {
        expect(find.textContaining(leak), findsNothing, reason: leak);
      }
    });
  });

  group('InboxPage archive inputs', () {
    final List<AgentSummary> agents = agentsFromComposers(
      jsonDecode(withArchived) as Map<String, dynamic>,
    );

    Future<void> pumpPage(
      WidgetTester tester, {
      bool includeArchived = false,
      ValueChanged<bool>? onIncludeArchivedChanged,
      ValueChanged<String>? onArchive,
      ValueChanged<String>? onRestore,
      String? archivingBcId,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InboxPage(
              webConnected: true,
              preferences: const Preferences(),
              agents: agents,
              includeArchived: includeArchived,
              archivingBcId: archivingBcId,
              onIncludeArchivedChanged: onIncludeArchivedChanged,
              onArchive: onArchive,
              onRestore: onRestore,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('a controlled chip reports the choice and follows input', (
      WidgetTester tester,
    ) async {
      final List<bool> chosen = <bool>[];
      await pumpPage(tester, onIncludeArchivedChanged: chosen.add);
      await toggleArchived(tester);
      expect(chosen, <bool>[true]);
      expect(find.text('Old login page'), findsNothing);
      await pumpPage(
        tester,
        includeArchived: true,
        onIncludeArchivedChanged: chosen.add,
      );
      expect(find.text('Old login page'), findsOneWidget);
    });

    testWidgets('no archive callbacks means no card buttons', (
      WidgetTester tester,
    ) async {
      await pumpPage(
        tester,
        includeArchived: true,
        onIncludeArchivedChanged: (_) {},
      );
      expect(find.byType(TextButton), findsNothing);
    });

    testWidgets('a running action labels its card and disables the rest', (
      WidgetTester tester,
    ) async {
      await pumpPage(
        tester,
        includeArchived: true,
        onIncludeArchivedChanged: (_) {},
        onArchive: (_) {},
        onRestore: (_) {},
        archivingBcId: 'bc-1',
      );
      final TextButton running = tester.widget<TextButton>(
        cardButton('Fix login', 'Archiving…'),
      );
      expect(running.onPressed, isNull);
      final TextButton other = tester.widget<TextButton>(
        cardButton('Old login page', 'Restore'),
      );
      expect(other.onPressed, isNull);
    });
  });
}
