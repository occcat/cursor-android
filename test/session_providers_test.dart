import 'package:cursor_android/app_router.dart';
import 'package:cursor_android/data/cookie_session_store.dart';
import 'package:cursor_android/data/credentials.dart';
import 'package:cursor_android/providers/session_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

const String fakeCookie = 'session=fake-cookie-value-123';

/// Fails every read with a message that quotes [fakeCookie].
class FailingCredentials implements Credentials {
  @override
  Future<String?> read(String name) async =>
      throw StateError('read failed: $fakeCookie');

  @override
  Future<void> write(String name, String? value) async {}
}

Future<MemoryCredentials> credentialsWithCookie() async {
  final MemoryCredentials credentials = MemoryCredentials();
  await credentials.write(kCookieName, fakeCookie);
  return credentials;
}

ProviderContainer containerFor(Credentials credentials) {
  final ProviderContainer container = ProviderContainer(
    overrides: [credentialsProvider.overrideWithValue(credentials)],
  );
  addTearDown(container.dispose);
  return container;
}

Future<void> pumpApp(
  WidgetTester tester,
  Credentials credentials, {
  String initialLocation = '/',
}) async {
  final GoRouter router = createAppRouter(initialLocation: initialLocation);
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [credentialsProvider.overrideWithValue(credentials)],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('webConnectedProvider', () {
    test('is false without a cookie', () async {
      final ProviderContainer container = containerFor(MemoryCredentials());
      expect(await container.read(webConnectedProvider.future), isFalse);
    });

    test('is false for an empty stored cookie', () async {
      final MemoryCredentials credentials = MemoryCredentials();
      await credentials.write(kCookieName, '');
      final ProviderContainer container = containerFor(credentials);
      expect(await container.read(webConnectedProvider.future), isFalse);
    });

    test('is true for a stored cookie', () async {
      final ProviderContainer container = containerFor(
        await credentialsWithCookie(),
      );
      expect(await container.read(webConnectedProvider.future), isTrue);
    });

    test('is false when the read fails and keeps the cookie out', () async {
      final ProviderContainer container = containerFor(FailingCredentials());
      expect(await container.read(webConnectedProvider.future), isFalse);
      final AsyncValue<bool> state = container.read(webConnectedProvider);
      expect(state.hasError, isFalse);
      expect(state.toString(), isNot(contains(fakeCookie)));
    });

    test('the cookie store uses the shared credentials', () async {
      final MemoryCredentials credentials = MemoryCredentials();
      final ProviderContainer container = containerFor(credentials);
      final CookieSessionStore store = container.read(
        cookieSessionStoreProvider,
      );
      await store.saveCookie(fakeCookie);
      expect(await credentials.read(kCookieName), fakeCookie);
      container.invalidate(webConnectedProvider);
      expect(await container.read(webConnectedProvider.future), isTrue);
      expect(store.toString(), isNot(contains(fakeCookie)));
      expect(credentials.toString(), isNot(contains(fakeCookie)));
      expect(
        container.read(webConnectedProvider).toString(),
        isNot(contains(fakeCookie)),
      );
    });
  });

  group('router webConnected', () {
    testWidgets('Inbox shows the connect card without a cookie', (
      WidgetTester tester,
    ) async {
      await pumpApp(tester, MemoryCredentials());
      expect(find.text('Connect your workspace'), findsOneWidget);
      expect(find.text('Get started'), findsOneWidget);
      expect(find.text('+ New agent'), findsNothing);
    });

    testWidgets('Inbox shows the connected empty state with a cookie', (
      WidgetTester tester,
    ) async {
      await pumpApp(tester, await credentialsWithCookie());
      expect(find.text('Connect your workspace'), findsNothing);
      expect(find.text('+ New agent'), findsOneWidget);
      expect(find.text('No agents here yet. Start with a task.'), findsOneWidget);
      expect(find.textContaining(fakeCookie), findsNothing);
    });

    testWidgets('Inbox stays disconnected and quiet when the read fails', (
      WidgetTester tester,
    ) async {
      await pumpApp(tester, FailingCredentials());
      expect(tester.takeException(), isNull);
      expect(find.text('Connect your workspace'), findsOneWidget);
      expect(find.textContaining(fakeCookie), findsNothing);
      expect(find.textContaining('read failed'), findsNothing);
    });

    testWidgets('Settings offers Connect without a cookie', (
      WidgetTester tester,
    ) async {
      await pumpApp(tester, MemoryCredentials(), initialLocation: '/settings');
      expect(find.text('Connect web session'), findsOneWidget);
      expect(find.text('Disconnect & clear local data'), findsNothing);
      expect(find.text('Load environments'), findsNothing);
    });

    testWidgets('Settings shows the connected session with a cookie', (
      WidgetTester tester,
    ) async {
      await pumpApp(
        tester,
        await credentialsWithCookie(),
        initialLocation: '/settings',
      );
      expect(find.text('Reconnect web session'), findsOneWidget);
      expect(find.text('Disconnect & clear local data'), findsOneWidget);
      expect(find.text('Load environments'), findsOneWidget);
      expect(find.textContaining(fakeCookie), findsNothing);
    });
  });
}
