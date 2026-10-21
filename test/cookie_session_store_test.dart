import 'dart:async';

import 'package:cursor_android/data/cookie_session_store.dart';
import 'package:cursor_android/data/credentials.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fake cookie that only lives in memory during these tests.
const String sampleCookie = 'session=test-cookie-0123456789abcdef';

void main() {
  late MemoryCredentials credentials;
  late CookieSessionStore store;

  setUp(() {
    credentials = MemoryCredentials();
    store = CookieSessionStore(credentials);
  });

  test('uses the Kotlin 0.1.5 credential name', () {
    expect(kCookieName, 'cookie');
  });

  test('reads null before a cookie is saved', () async {
    expect(await store.readCookie(), isNull);
  });

  test('save then read round-trips the cookie', () async {
    await store.saveCookie(sampleCookie);
    expect(await store.readCookie(), sampleCookie);
    expect(await credentials.read(kCookieName), sampleCookie);
  });

  test('saving null clears the cookie', () async {
    await store.saveCookie(sampleCookie);
    await store.saveCookie(null);
    expect(await store.readCookie(), isNull);
    expect(await credentials.read(kCookieName), isNull);
  });

  test('saving an empty string clears the cookie', () async {
    await store.saveCookie(sampleCookie);
    await store.saveCookie('');
    expect(await store.readCookie(), isNull);
  });

  test('clear removes only the cookie credential', () async {
    await credentials.write(kApiKeyName, 'other-value');
    await store.saveCookie(sampleCookie);
    await store.clear();
    expect(await store.readCookie(), isNull);
    expect(await credentials.read(kCookieName), isNull);
    expect(await credentials.read(kApiKeyName), 'other-value');
  });

  test('toString never exposes the stored cookie', () async {
    await store.saveCookie(sampleCookie);
    expect(credentials.toString(), isNot(contains(sampleCookie)));
    expect(store.toString(), isNot(contains(sampleCookie)));
  });

  test('save, read and clear never print the cookie', () async {
    final List<String> printed = <String>[];
    await runZoned(
      () async {
        await store.saveCookie(sampleCookie);
        await store.readCookie();
        await store.clear();
      },
      zoneSpecification: ZoneSpecification(
        print: (Zone self, ZoneDelegate parent, Zone zone, String line) {
          printed.add(line);
        },
      ),
    );
    expect(printed.join('\n'), isNot(contains(sampleCookie)));
  });
}
