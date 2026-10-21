import 'package:cursor_android/data/credentials.dart';

/// Credential name for the cursor.com web session cookie.
///
/// Matches the `"cookie"` entry used by the Kotlin 0.1.5 `Credentials` store.
const String kCookieName = 'cookie';

/// Persists the web session cookie through [Credentials].
///
/// The cookie is never logged or included in [toString].
class CookieSessionStore {
  const CookieSessionStore(this.credentials);

  final Credentials credentials;

  /// Returns the saved cookie, or `null` when none is stored.
  Future<String?> readCookie() async {
    final String? cookie = await credentials.read(kCookieName);
    return (cookie == null || cookie.isEmpty) ? null : cookie;
  }

  /// Saves [cookie]. A `null` or empty [cookie] clears the stored value.
  Future<void> saveCookie(String? cookie) {
    final String? value =
        (cookie == null || cookie.isEmpty) ? null : cookie;
    return credentials.write(kCookieName, value);
  }

  /// Clears the cookie credential only.
  ///
  /// WebView cookies are cleared separately in a later WebView round.
  Future<void> clear() => credentials.write(kCookieName, null);

  @override
  String toString() => 'CookieSessionStore()';
}
