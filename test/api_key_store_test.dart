import 'dart:async';

import 'package:cursor_android/data/api_key_store.dart';
import 'package:cursor_android/data/credentials.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fake key that only lives in memory during these tests.
const String sampleKey = 'test-key-0123456789abcdef';

void main() {
  late MemoryCredentials credentials;
  late ApiKeyStore store;

  setUp(() {
    credentials = MemoryCredentials();
    store = ApiKeyStore(credentials);
  });

  test('uses the Kotlin 0.1.5 credential name', () {
    expect(kApiKeyName, 'api');
  });

  test('reads null before a key is saved', () async {
    expect(await store.readApiKey(), isNull);
  });

  test('save then read round-trips the key', () async {
    await store.saveApiKey(sampleKey);
    expect(await store.readApiKey(), sampleKey);
    expect(await credentials.read(kApiKeyName), sampleKey);
  });

  test('saving null clears the key', () async {
    await store.saveApiKey(sampleKey);
    await store.saveApiKey(null);
    expect(await store.readApiKey(), isNull);
    expect(await credentials.read(kApiKeyName), isNull);
  });

  test('saving an empty string clears the key', () async {
    await store.saveApiKey(sampleKey);
    await store.saveApiKey('');
    expect(await store.readApiKey(), isNull);
    expect(await credentials.read(kApiKeyName), isNull);
  });

  test('toString never exposes the stored key', () async {
    await store.saveApiKey(sampleKey);
    expect(credentials.toString(), isNot(contains(sampleKey)));
    expect(store.toString(), isNot(contains(sampleKey)));
  });

  test('save, read and clear never print the key', () async {
    final List<String> printed = <String>[];
    await runZoned(
      () async {
        await store.saveApiKey(sampleKey);
        await store.readApiKey();
        await store.saveApiKey(null);
      },
      zoneSpecification: ZoneSpecification(
        print: (Zone self, ZoneDelegate parent, Zone zone, String line) {
          printed.add(line);
        },
      ),
    );
    expect(printed.join('\n'), isNot(contains(sampleKey)));
  });
}
