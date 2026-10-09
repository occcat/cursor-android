package app.cursor.android.domain

import java.util.Locale

/** Google rejects embedded WebViews; that host never joins the in-app session. */
fun isGoogleSignInHost(host: String): Boolean =
    host.lowercase(Locale.ROOT) == "accounts.google.com"

/**
 * Official Cursor login redirects observed from /agents.
 * Unrelated origins, including Google, open outside this WebView.
 */
fun isTrustedSignInHost(host: String): Boolean {
    val normalized = host.lowercase(Locale.ROOT)
    if (isGoogleSignInHost(normalized)) return false
    return normalized == "cursor.com" ||
        normalized.endsWith(".cursor.com") ||
        normalized == "authenticate.cursor.sh" ||
        normalized == "authenticator.cursor.sh" ||
        normalized == "workos.com" ||
        normalized.endsWith(".workos.com") ||
        normalized == "github.com"
}

fun isTrustedSignInUrl(url: String): Boolean =
    runCatching {
            val uri = java.net.URI(url)
            uri.scheme == "https" &&
                uri.rawUserInfo == null &&
                uri.host?.let(::isTrustedSignInHost) == true
        }
        .getOrDefault(false)
