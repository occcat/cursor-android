import 'dart:convert';
import 'dart:typed_data';

import 'package:cursor_android/app_router.dart';
import 'package:cursor_android/data/api_failure.dart';
import 'package:cursor_android/data/cookie_session_store.dart';
import 'package:cursor_android/data/credentials.dart';
import 'package:cursor_android/data/cursor_api.dart';
import 'package:cursor_android/providers/cursor_api_providers.dart';
import 'package:cursor_android/providers/environment_providers.dart';
import 'package:cursor_android/providers/session_providers.dart';
import 'package:cursor_android/ui/inbox_page.dart' show genericInboxError;
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

const String fakeCookie = 'session=fake-cookie-value-123; csrf-token=old';
final Uri mockBase = Uri.parse('http://127.0.0.1:8080/');
const String envId = 'env-1';
const String apiRoot = '/api/background-composer';
const String getPath = '$apiRoot/get-environment';
const String secretsPath = '$apiRoot/list-background-composer-secrets';
const String savePath = '$apiRoot/set-personal-environment-json';
const String addPath = '$apiRoot/create-background-composer-secret';
const String revokePath = '$apiRoot/revoke-background-composer-secret';
const String environment =
    '{"environment":{"publicId":"env-1","name":"Linux box",'
    '"environmentJson":{"install":"npm ci"}}}';
const String oneSecret =
    '{"secrets":[{"name":"API_KEY","type":"runtime_secret","id":"sec-1",'
    '"value":"hidden-a","secretValue":"hidden-b"}]}';
const String noSecrets = '{"secrets":[]}';
const String newValue = 'n3w-hidden-value';
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
  'hidden-',
  newValue,
];
const ValueKey<String> nameKey = ValueKey<String>('environment-name');
const ValueKey<String> jsonKey = ValueKey<String>('environment-json');
const ValueKey<String> secretNameKey = ValueKey<String>(
  'environment-secret-name',
);
const ValueKey<String> secretValueKey = ValueKey<String>(
  'environment-secret-value',
);
final Finder saveButton = find.widgetWithText(FilledButton, 'Save environment');
final Finder addButton = find.widgetWithText(FilledButton, 'Add secret');
final Finder deleteButtons = find.widgetWithText(TextButton, 'Delete');

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

/// Opens the app on `/environment/env-1` with [credentials] and [server].
Future<void> pumpEnvironment(
  WidgetTester tester,
  Credentials credentials,
  FakeServer server,
) async {
  final GoRouter router = createAppRouter(
    initialLocation: '/environment/$envId',
  );
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

Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

String fieldText(WidgetTester tester, ValueKey<String> key) =>
    tester.widget<TextField>(find.byKey(key)).controller!.text;

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

  group('environmentErrorMessage', () {
    test('a 401 or a missing cookie asks to reconnect', () {
      expect(
        environmentErrorMessage(const ApiFailure(401, 'unauthorized')),
        environmentReconnectError,
      );
      expect(
        environmentErrorMessage(const ApiFailure(0, 'connection_required')),
        environmentReconnectError,
      );
    });

    test('other failures name the action and stay safe', () {
      expect(
        environmentErrorMessage(
          const ApiFailure(500, 'request_failed'),
          action: 'add the runtime value',
        ),
        'Could not add the runtime value (HTTP 500 · request_failed).',
      );
      expect(
        environmentErrorMessage(const CursorNetworkFailure('receiveTimeout')),
        'Could not reach Cursor (receiveTimeout). Check your connection.',
      );
      expect(
        environmentErrorMessage(const ApiFailure(403, 'invalid_csrf_token')),
        genericInboxError,
      );
      expect(
        environmentErrorMessage(StateError('Cookie: $fakeCookie')),
        genericInboxError,
      );
    });
  });

  group('router Cloud environment', () {
    testWidgets('loads the environment and redacted runtime values', (
      WidgetTester tester,
    ) async {
      server.replies.addAll(const <Reply>[
        Reply(environment),
        Reply(oneSecret),
      ]);
      await pumpEnvironment(tester, await credentialsWithCookie(), server);
      expect(tester.takeException(), isNull);
      expect(find.text('Loading this environment…'), findsNothing);
      expect(fieldText(tester, nameKey), 'Linux box');
      expect(fieldText(tester, jsonKey), '{"install":"npm ci"}');
      expect(find.text('API_KEY · runtime_secret'), findsOneWidget);
      expect(server.seen, hasLength(2));
      expect(server.seen[0].uri.path, getPath);
      expect(server.seen[0].json, <String, dynamic>{
        'publicId': envId,
        'includeEnvironmentJson': true,
      });
      expect(server.seen[1].uri.path, secretsPath);
      expect(server.seen[1].json, <String, dynamic>{'redact': true});
      for (final Seen request in server.seen) {
        expect(request.method, 'POST');
        expect(request.headers['cookie'], fakeCookie);
        expect(request.headers.containsKey('authorization'), isFalse);
      }
      expectNoLeaks();
    });

    testWidgets('a failed load shows a safe error and Retry reloads', (
      WidgetTester tester,
    ) async {
      server.replies.add(const Reply(leakyUnauthorized, status: 401));
      await pumpEnvironment(tester, await credentialsWithCookie(), server);
      expect(tester.takeException(), isNull);
      expect(find.text(environmentReconnectError), findsOneWidget);
      expect(find.text('Loading this environment…'), findsOneWidget);
      expect(server.seen, hasLength(1));
      expectNoLeaks();

      server.replies.addAll(const <Reply>[
        Reply(environment),
        Reply(noSecrets),
      ]);
      await tapVisible(tester, find.widgetWithText(ActionChip, 'Retry'));
      expect(fieldText(tester, nameKey), 'Linux box');
      expect(find.text(environmentReconnectError), findsNothing);
      expect(server.seen, hasLength(3));
    });

    testWidgets('a failed list keeps the form and names the step', (
      WidgetTester tester,
    ) async {
      server.replies.addAll(const <Reply>[
        Reply(environment),
        Reply(leakyServerError, status: 500),
      ]);
      await pumpEnvironment(tester, await credentialsWithCookie(), server);
      expect(tester.takeException(), isNull);
      expect(fieldText(tester, nameKey), 'Linux box');
      expect(
        find.text('Could not load runtime values (HTTP 500 · request_failed).'),
        findsOneWidget,
      );
      expect(deleteButtons, findsNothing);
      expectNoLeaks();
    });

    testWidgets('Save posts the decoded JSON object and reloads', (
      WidgetTester tester,
    ) async {
      server.replies.addAll(const <Reply>[
        Reply(environment),
        Reply(noSecrets),
        Reply('{}'),
        Reply(environment),
        Reply(noSecrets),
      ]);
      await pumpEnvironment(tester, await credentialsWithCookie(), server);
      await tester.enterText(find.byKey(jsonKey), ' {"install":"pnpm i"} ');
      await tester.pump();
      await tapVisible(tester, saveButton);
      await tapVisible(tester, find.text('Confirm'));
      expect(tester.takeException(), isNull);
      expect(server.seen, hasLength(5));
      expect(server.seen[2].uri.path, savePath);
      expect(server.seen[2].json, <String, dynamic>{
        'publicId': envId,
        'environmentJson': <String, dynamic>{'install': 'pnpm i'},
      });
      expect(server.seen[3].uri.path, getPath);
      expect(server.seen[4].uri.path, secretsPath);
    });

    testWidgets('invalid JSON sends nothing', (WidgetTester tester) async {
      server.replies.addAll(const <Reply>[
        Reply(environment),
        Reply(noSecrets),
      ]);
      await pumpEnvironment(tester, await credentialsWithCookie(), server);
      await tester.enterText(find.byKey(jsonKey), '[1, 2]');
      await tester.pump();
      await tapVisible(tester, saveButton);
      expect(find.text('Replace configuration?'), findsNothing);
      expect(server.seen, hasLength(2));
    });

    testWidgets('Add secret sends the value once and reloads the list', (
      WidgetTester tester,
    ) async {
      server.replies.addAll(const <Reply>[
        Reply(environment),
        Reply(noSecrets),
        Reply('{}'),
        Reply(environment),
        Reply('{"secrets":[{"name":"NEW_KEY","type":"runtime_secret"}]}'),
      ]);
      await pumpEnvironment(tester, await credentialsWithCookie(), server);
      await tester.enterText(find.byKey(secretNameKey), '  NEW_KEY  ');
      await tester.enterText(find.byKey(secretValueKey), newValue);
      await tester.pump();
      await tapVisible(tester, addButton);
      expect(tester.takeException(), isNull);
      expect(server.seen, hasLength(5));
      expect(server.seen[2].uri.path, addPath);
      expect(server.seen[2].json, <String, dynamic>{
        'name': 'NEW_KEY',
        'value': newValue,
        'redact': true,
      });
      expect(
        server.seen.where((Seen request) => request.body.contains(newValue)),
        hasLength(1),
      );
      expect(find.text('NEW_KEY · runtime_secret'), findsOneWidget);
      expect(fieldText(tester, secretValueKey), isEmpty);
      expectNoLeaks();
    });

    testWidgets('Delete revokes with the id and reloads the list', (
      WidgetTester tester,
    ) async {
      server.replies.addAll(const <Reply>[
        Reply(environment),
        Reply(oneSecret),
        Reply('{}'),
        Reply(environment),
        Reply(noSecrets),
      ]);
      await pumpEnvironment(tester, await credentialsWithCookie(), server);
      await tapVisible(tester, deleteButtons.first);
      expect(find.text('Revoke secret?'), findsOneWidget);
      await tapVisible(tester, find.text('Confirm'));
      expect(tester.takeException(), isNull);
      expect(server.seen[2].uri.path, revokePath);
      expect(server.seen[2].json, <String, dynamic>{
        'name': 'API_KEY',
        'id': 'sec-1',
      });
      expect(find.text('API_KEY · runtime_secret'), findsNothing);
      expect(server.seen, hasLength(5));
    });

    testWidgets('a failed action keeps the page and skips the reload', (
      WidgetTester tester,
    ) async {
      server.replies.addAll(const <Reply>[
        Reply(environment),
        Reply(oneSecret),
        Reply(leakyServerError, status: 500),
      ]);
      await pumpEnvironment(tester, await credentialsWithCookie(), server);
      await tester.enterText(find.byKey(secretNameKey), 'NEW_KEY');
      await tester.enterText(find.byKey(secretValueKey), newValue);
      await tester.pump();
      await tapVisible(tester, addButton);
      expect(tester.takeException(), isNull);
      expect(
        find.text(
          'Could not add the runtime value (HTTP 500 · request_failed).',
        ),
        findsOneWidget,
      );
      expect(find.text('API_KEY · runtime_secret'), findsOneWidget);
      expect(server.seen, hasLength(3));
      expectNoLeaks();
    });

    testWidgets('stays on the loading state without a cookie', (
      WidgetTester tester,
    ) async {
      await pumpEnvironment(tester, MemoryCredentials(), server);
      expect(find.text('Loading this environment…'), findsOneWidget);
      expect(
        tester.widget<ActionChip>(find.widgetWithText(ActionChip, 'Retry'))
            .onPressed,
        isNull,
      );
      expect(server.seen, isEmpty);
    });
  });
}
