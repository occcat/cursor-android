/// Riverpod provider for the cursor.com web API client.
library;

import 'package:cursor_android/data/cookie_session_store.dart';
import 'package:cursor_android/data/cursor_api.dart';
import 'package:cursor_android/providers/session_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The shared [CursorApi], reading the cookie from
/// [cookieSessionStoreProvider] on every request.
///
/// Production talks to `https://cursor.com/` only. Tests override this
/// provider with a client whose `Dio` uses a fake adapter and
/// `allowConfiguredOrigin`. Building the client sends nothing.
final Provider<CursorApi> cursorApiProvider = Provider<CursorApi>((Ref ref) {
  final CookieSessionStore store = ref.watch(cookieSessionStoreProvider);
  return CursorApi(cookie: store.readCookie);
});
