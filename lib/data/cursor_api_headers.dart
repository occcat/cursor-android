/// Origin checks and session headers ported from Kotlin 0.1.5 `CursorApi.kt`.
library;

const String _csrfPrefix = 'csrf-token=';
const String _teamPrefix = 'portal-selected-team-id=';

/// Whether the session cookie may be sent to [url].
///
/// Production `https://cursor.com:443` is always allowed. Any other URL needs
/// [allowConfiguredOrigin] and the same scheme, host and port as [origin].
bool cookieAllowed({
  required Uri url,
  required Uri origin,
  required bool allowConfiguredOrigin,
}) {
  if (url.scheme == 'https' && url.host == 'cursor.com' && url.port == 443) {
    return true;
  }
  return allowConfiguredOrigin &&
      url.scheme == origin.scheme &&
      url.host == origin.host &&
      url.port == origin.port;
}

/// Returns the non-blank `portal-selected-team-id` cookie value, if any.
String? teamIdFromCookie(String cookie) {
  final String? value = _cookieValue(cookie, _teamPrefix);
  return (value == null || value.trim().isEmpty) ? null : value;
}

/// Cookie, Origin, team and CSRF headers for one request.
///
/// A [csrfToken] replaces any `csrf-token` entry in [credential]; otherwise
/// the cookie's own `csrf-token` is used. `x-csrf-token` is sent for every
/// method except `GET`. There is never an `Authorization` header. Values with
/// control or non-ASCII characters throw a [FormatException] that names the
/// header but never includes its value.
Map<String, String> sessionHeaders({
  required Uri url,
  required String credential,
  String? csrfToken,
  required String method,
}) {
  final String? token = csrfToken ?? _cookieValue(credential, _csrfPrefix);
  final String cookies = csrfToken == null
      ? credential
      : '${credential.split(';').where(_keepCookiePart).join(';')}'
            '; csrf-token=$csrfToken';
  final Map<String, String> headers = <String, String>{
    'Accept': 'application/json',
    'Cookie': cookies,
    'Origin': '${url.scheme}://${url.host}',
  };
  final String? team = teamIdFromCookie(credential);
  if (team != null) {
    headers['x-cursor-team-id'] = team;
  }
  if (token != null && method != 'GET') {
    headers['x-csrf-token'] = token;
  }
  headers.forEach(_checkHeaderValue);
  return headers;
}

bool _keepCookiePart(String part) => !part.trim().startsWith(_csrfPrefix);

String? _cookieValue(String cookie, String prefix) {
  for (final String part in cookie.split(';')) {
    final String trimmed = part.trim();
    if (trimmed.startsWith(prefix)) {
      return trimmed.substring(trimmed.indexOf('=') + 1);
    }
  }
  return null;
}

/// Mirrors OkHttp's header value check without echoing the value.
void _checkHeaderValue(String name, String value) {
  for (final int unit in value.codeUnits) {
    if ((unit < 0x20 && unit != 0x09) || unit > 0x7e) {
      throw FormatException('Invalid character in $name header');
    }
  }
}
