import 'dart:convert';

import 'package:cursor_android/app_router.dart';
import 'package:cursor_android/data/credentials.dart';
import 'package:cursor_android/data/preferences_store.dart';
import 'package:cursor_android/domain/preferences.dart';
import 'package:cursor_android/providers/preferences_providers.dart';
import 'package:cursor_android/providers/session_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// [MemoryCredentials] whose preference writes fail while [failWrites].
class FlakyCredentials extends MemoryCredentials {
  bool failWrites = false;

  @override
  Future<void> write(String name, String? value) async {
    if (failWrites && name == kPreferencesName) {
      throw StateError('disk full');
    }
    await super.write(name, value);
  }
}

Future<Map<String, dynamic>> storedJson(Credentials credentials) async =>
    jsonDecode((await credentials.read(kPreferencesName))!)
        as Map<String, dynamic>;

ProviderContainer containerFor(Credentials credentials) {
  final ProviderContainer container = ProviderContainer(
    overrides: [credentialsProvider.overrideWithValue(credentials)],
  );
  addTearDown(container.dispose);
  return container;
}

/// Opens the app at [location] with [credentials], replacing any app that
/// was shown before so its providers start fresh, like a restart.
Future<void> launch(
  WidgetTester tester,
  Credentials credentials, {
  String location = '/',
}) async {
  await tester.pumpWidget(const SizedBox());
  final GoRouter router = createAppRouter(initialLocation: location);
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [credentialsProvider.overrideWithValue(credentials)],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

Finder switchTile(String label) =>
    find.widgetWithText(SwitchListTile, label);

bool switchValue(WidgetTester tester, String label) =>
    tester.widget<SwitchListTile>(switchTile(label)).value;

bool chipSelected(WidgetTester tester, String label) =>
    tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, label)).selected;

Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  group('preferences JSON', () {
    test('uses the Kotlin DataStore key names and round-trips', () {
      const Preferences changed = Preferences(
        remaining: false,
        cursor: false,
        other: true,
        pace: false,
        paused: true,
        notifications: true,
        intervalSeconds: 120,
        language: 'zh-CN',
        widgetTitles: true,
      );
      final Map<String, Object> json = preferencesToJson(changed);
      expect(json, <String, Object>{
        'remaining': false,
        'cursor': false,
        'other': true,
        'pace': false,
        'paused': true,
        'notifications': true,
        'interval': 120,
        'language': 'zh-CN',
        'widgetTitles': true,
      });
      expect(
        preferencesToJson(preferencesFromJson(jsonDecode(jsonEncode(json)))),
        json,
      );
    });

    test('each bad or missing field falls back on its own', () {
      final Preferences read = preferencesFromJson(<String, Object?>{
        'remaining': 'no',
        'paused': true,
        'interval': 45,
        'language': 'fr',
        'widgetTitles': null,
      });
      expect(
        preferencesToJson(read),
        preferencesToJson(const Preferences(paused: true)),
      );
      expect(
        preferencesToJson(preferencesFromJson(<Object>[1, 2])),
        preferencesToJson(const Preferences()),
      );
    });
  });

  group('PreferencesStore', () {
    test('reads defaults when nothing or garbage is stored', () async {
      final MemoryCredentials credentials = MemoryCredentials();
      final PreferencesStore store = PreferencesStore(credentials);
      final Map<String, Object> defaults = preferencesToJson(
        const Preferences(),
      );
      expect(preferencesToJson(await store.read()), defaults);
      await credentials.write(kPreferencesName, '{not json');
      expect(preferencesToJson(await store.read()), defaults);
    });

    test('writes one JSON entry that reads back', () async {
      final MemoryCredentials credentials = MemoryCredentials();
      final PreferencesStore store = PreferencesStore(credentials);
      await store.write(const Preferences(intervalSeconds: 300));
      expect((await storedJson(credentials))['interval'], 300);
      expect((await store.read()).intervalSeconds, 300);
    });
  });

  group('preferencesProvider', () {
    test('loads the stored preferences', () async {
      final MemoryCredentials credentials = MemoryCredentials();
      final PreferencesStore store = PreferencesStore(credentials);
      await store.write(const Preferences(language: 'zh-CN'));
      final ProviderContainer container = containerFor(credentials);
      final Preferences read = await container.read(preferencesProvider.future);
      expect(read.language, 'zh-CN');
    });

    test('save shows the change and stores it', () async {
      final MemoryCredentials credentials = MemoryCredentials();
      final ProviderContainer container = containerFor(credentials);
      final Preferences loaded = await container.read(
        preferencesProvider.future,
      );
      await container
          .read(preferencesProvider.notifier)
          .save(loaded.copyWith(pace: false));
      expect(container.read(preferencesProvider).requireValue.pace, isFalse);
      expect((await storedJson(credentials))['pace'], isFalse);
    });

    test('a failed write brings the stored preferences back', () async {
      final FlakyCredentials credentials = FlakyCredentials();
      final ProviderContainer container = containerFor(credentials);
      final Preferences loaded = await container.read(
        preferencesProvider.future,
      );
      credentials.failWrites = true;
      await container
          .read(preferencesProvider.notifier)
          .save(loaded.copyWith(paused: true));
      expect(container.read(preferencesProvider).requireValue.paused, isFalse);
      expect(await credentials.read(kPreferencesName), isNull);
    });

    test('a failed read yields the defaults', () async {
      final ProviderContainer container = ProviderContainer(
        overrides: [
          preferencesStoreProvider.overrideWithValue(
            PreferencesStore(_ThrowingCredentials()),
          ),
        ],
      );
      addTearDown(container.dispose);
      final Preferences read = await container.read(
        preferencesProvider.future,
      );
      expect(preferencesToJson(read), preferencesToJson(const Preferences()));
    });
  });

  group('router Settings', () {
    testWidgets('a switch change is stored and survives a restart', (
      WidgetTester tester,
    ) async {
      final MemoryCredentials credentials = MemoryCredentials();
      await launch(tester, credentials, location: '/settings');
      expect(switchValue(tester, 'Pause automatic refresh'), isFalse);
      await tapVisible(tester, switchTile('Pause automatic refresh'));
      expect(switchValue(tester, 'Pause automatic refresh'), isTrue);
      expect((await storedJson(credentials))['paused'], isTrue);

      await launch(tester, credentials, location: '/settings');
      expect(switchValue(tester, 'Pause automatic refresh'), isTrue);
    });

    testWidgets('interval and language chips are stored', (
      WidgetTester tester,
    ) async {
      final MemoryCredentials credentials = MemoryCredentials();
      await launch(tester, credentials, location: '/settings');
      expect(chipSelected(tester, '60s'), isTrue);
      await tapVisible(tester, find.widgetWithText(ChoiceChip, '120s'));
      await tapVisible(tester, find.widgetWithText(ChoiceChip, '简体中文'));

      await launch(tester, credentials, location: '/settings');
      expect(chipSelected(tester, '120s'), isTrue);
      expect(chipSelected(tester, '60s'), isFalse);
      expect(chipSelected(tester, '简体中文'), isTrue);
      final Map<String, dynamic> json = await storedJson(credentials);
      expect(json['interval'], 120);
      expect(json['language'], 'zh-CN');
    });

    testWidgets('the Inbox usage capsule follows Settings', (
      WidgetTester tester,
    ) async {
      final MemoryCredentials credentials = MemoryCredentials();
      await launch(tester, credentials);
      expect(find.text('remaining'), findsOneWidget);
      expect(find.text('used'), findsNothing);

      await tapVisible(tester, find.widgetWithText(TextButton, 'Settings'));
      await tapVisible(tester, switchTile('Show remaining allowance'));
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('used'), findsOneWidget);
      expect(find.text('remaining'), findsNothing);

      await launch(tester, credentials);
      expect(find.text('used'), findsOneWidget);
    });
  });
}

/// [Credentials] whose every call fails.
class _ThrowingCredentials implements Credentials {
  @override
  Future<String?> read(String name) => Future<String?>.error(
    StateError('broken storage'),
  );

  @override
  Future<void> write(String name, String? value) =>
      Future<void>.error(StateError('broken storage'));
}
