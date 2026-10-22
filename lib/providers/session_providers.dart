/// Riverpod providers for the stored cursor.com web session. They only read
/// local credentials; nothing here calls the network.
library;

import 'package:cursor_android/data/cookie_session_store.dart';
import 'package:cursor_android/data/credentials.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The shared [Credentials] store.
///
/// Production uses [SecureCredentials]; tests override this provider with
/// [MemoryCredentials].
final Provider<Credentials> credentialsProvider = Provider<Credentials>(
  (Ref ref) => SecureCredentials(),
);

/// The [CookieSessionStore] backed by [credentialsProvider].
final Provider<CookieSessionStore> cookieSessionStoreProvider =
    Provider<CookieSessionStore>(
      (Ref ref) => CookieSessionStore(ref.watch(credentialsProvider)),
    );

/// Whether a non-empty web session cookie is stored on this device.
///
/// A failed read resolves to `false` instead of an error, so storage
/// contents quoted in an exception never reach the UI and the provider is
/// not retried.
final FutureProvider<bool> webConnectedProvider = FutureProvider<bool>((
  Ref ref,
) async {
  final CookieSessionStore store = ref.watch(cookieSessionStoreProvider);
  try {
    final String? cookie = await store.readCookie();
    return cookie != null && cookie.isNotEmpty;
  } on Object {
    return false;
  }
});

/// [webConnectedProvider] as a plain flag: `false` until the cookie read
/// completes with a stored cookie.
bool watchWebConnected(WidgetRef ref) {
  return switch (ref.watch(webConnectedProvider)) {
    AsyncData<bool>(value: true) => true,
    _ => false,
  };
}
