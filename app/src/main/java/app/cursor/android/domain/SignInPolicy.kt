package app.cursor.android.domain

import java.util.Locale

/** Google rejects embedded WebViews; that host never joins the in-app session. */
fun isGoogleSignInHost(host: String): Boolean =
    host.lowercase(Locale.ROOT) == "accounts.google.com"

/**
 * Cloudflare's challenge frame has to stay inside the sign-in WebView.
 * Otherwise the login form never appears.
 */
fun isCloudflareChallengeHost(host: String): Boolean =
    host.lowercase(Locale.ROOT) == "challenges.cloudflare.com"

/**
 * A blank Cloudflare interstitial is not a login form.
 * Email and GitHub both have to be present before the page counts as shown.
 */
fun signInContentIsVisible(title: String?, body: String): Boolean {
    if (title.equals("Just a moment...", ignoreCase = true)) return false
    if (body.isBlank()) return false
    val lower = body.lowercase(Locale.ROOT)
    val hasEmail = "email" in lower || "邮箱" in body
    return "github" in lower && hasEmail
}

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
        normalized == "github.com" ||
        isCloudflareChallengeHost(normalized)
}

fun isTrustedSignInUrl(url: String): Boolean =
    runCatching {
            val uri = java.net.URI(url)
            uri.scheme == "https" &&
                uri.rawUserInfo == null &&
                uri.host?.let(::isTrustedSignInHost) == true
        }
        .getOrDefault(false)
