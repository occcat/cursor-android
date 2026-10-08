package app.cursor.android.domain

/** Official Cursor login redirects observed from /agents; unrelated origins open externally. */
fun isTrustedSignInHost(host: String): Boolean {
    val normalized = host.lowercase(java.util.Locale.ROOT)
    return normalized == "cursor.com" ||
        normalized.endsWith(".cursor.com") ||
        normalized == "authenticate.cursor.sh" ||
        normalized == "authenticator.cursor.sh" ||
        normalized == "workos.com" ||
        normalized.endsWith(".workos.com") ||
        normalized == "accounts.google.com" ||
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
