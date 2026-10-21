/// Sign-in navigation rules ported from Kotlin 0.1.5 `SignInPolicy.kt`.
library;

/// Google rejects embedded WebViews; that host never joins the in-app session.
bool isGoogleSignInHost(String host) =>
    host.toLowerCase() == 'accounts.google.com';

/// Cloudflare's challenge frame has to stay inside the sign-in WebView.
///
/// Otherwise the login form never appears.
bool isCloudflareChallengeHost(String host) =>
    host.toLowerCase() == 'challenges.cloudflare.com';

/// A blank Cloudflare interstitial is not a login form.
///
/// Email and GitHub both have to be present before the page counts as shown.
bool signInContentIsVisible(String? title, String body) {
  if (title?.toLowerCase() == 'just a moment...') {
    return false;
  }
  if (body.trim().isEmpty) {
    return false;
  }
  final String lower = body.toLowerCase();
  final bool hasEmail = lower.contains('email') || body.contains('邮箱');
  return lower.contains('github') && hasEmail;
}

/// Official Cursor login redirects observed from /agents.
///
/// Unrelated origins, including Google, open outside this WebView.
bool isTrustedSignInHost(String host) {
  final String normalized = host.toLowerCase();
  if (isGoogleSignInHost(normalized)) {
    return false;
  }
  return normalized == 'cursor.com' ||
      normalized.endsWith('.cursor.com') ||
      normalized == 'authenticate.cursor.sh' ||
      normalized == 'authenticator.cursor.sh' ||
      normalized == 'workos.com' ||
      normalized.endsWith('.workos.com') ||
      normalized == 'github.com' ||
      isCloudflareChallengeHost(normalized);
}

/// Accepts only `https` URLs without user info on a trusted sign-in host.
///
/// Like Kotlin's `java.net.URI` check, the scheme must be exactly `https` and
/// any `@` in the raw authority (even `https://@host`) counts as user info.
/// Unparseable URLs are rejected.
bool isTrustedSignInUrl(String url) {
  const String prefix = 'https://';
  if (!url.startsWith(prefix)) {
    return false;
  }
  final String rest = url.substring(prefix.length);
  final int end = rest.indexOf(RegExp('[/?#]'));
  final String authority = end < 0 ? rest : rest.substring(0, end);
  if (authority.contains('@')) {
    return false;
  }
  final Uri? uri = Uri.tryParse(url);
  return uri != null && isTrustedSignInHost(uri.host);
}
