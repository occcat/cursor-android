import 'package:cursor_android/app_router.dart';
import 'package:cursor_android/data/credentials.dart';
import 'package:cursor_android/main.dart';
import 'package:cursor_android/providers/session_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

Future<GoRouter> pumpRouter(WidgetTester tester) async {
  final GoRouter router = createAppRouter();
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [credentialsProvider.overrideWithValue(MemoryCredentials())],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

void main() {
  testWidgets('the app opens on the disconnected Inbox', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [credentialsProvider.overrideWithValue(MemoryCredentials())],
        child: const CursorApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Cursor'), findsOneWidget);
    expect(find.text('Connect your workspace'), findsOneWidget);
    expect(find.text('Get started'), findsOneWidget);
    expect(find.text('+ New agent'), findsNothing);
  });

  testWidgets('Settings opens from the app bar and goes back', (
    WidgetTester tester,
  ) async {
    await pumpRouter(tester);
    await tester.tap(find.widgetWithText(TextButton, 'Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Make it yours.'), findsOneWidget);
    expect(find.textContaining('later update'), findsNothing);
    final FilledButton capsule = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Start floating capsule'),
    );
    expect(capsule.onPressed, isNull);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Connect your workspace'), findsOneWidget);
  });

  testWidgets('/create shows the New agent form', (WidgetTester tester) async {
    final GoRouter router = await pumpRouter(tester);
    router.push('/create');
    await tester.pumpAndSettle();
    expect(find.text('What should we build?'), findsOneWidget);
    final FilledButton start = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Start agent →'),
    );
    expect(start.onPressed, isNull);
  });

  testWidgets('/agent/bc-test shows the loading state', (
    WidgetTester tester,
  ) async {
    final GoRouter router = await pumpRouter(tester);
    router.push('/agent/bc-test');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Agent'), findsOneWidget);
    expect(find.text('Loading this workspace…'), findsOneWidget);
  });

  testWidgets('/environment/env-1 shows Loading and Retry', (
    WidgetTester tester,
  ) async {
    final GoRouter router = await pumpRouter(tester);
    router.push('/environment/env-1');
    await tester.pumpAndSettle();
    expect(find.text('Loading this environment…'), findsOneWidget);
    expect(find.widgetWithText(ActionChip, 'Retry'), findsOneWidget);
  });
}
