package app.cursor.android

import app.cursor.android.domain.isCloudflareChallengeHost
import app.cursor.android.domain.isGoogleSignInHost
import app.cursor.android.domain.isTrustedSignInHost
import app.cursor.android.domain.isTrustedSignInUrl
import app.cursor.android.domain.signInContentIsVisible
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class SignInPolicyTest {
    @Test
    fun officialCursorRedirectChainStaysInsideTheSession() {
        listOf(
                "cursor.com",
                "api.workos.com",
                "authenticate.cursor.sh",
                "authenticator.cursor.sh",
                "github.com",
            )
            .forEach { assertTrue(isTrustedSignInHost(it)) }
    }

    @Test
    fun cloudflareChallengeStaysInsideAndABlankInterstitialIsNotTheLoginPage() {
        assertTrue(isCloudflareChallengeHost("challenges.cloudflare.com"))
        assertTrue(isTrustedSignInHost("challenges.cloudflare.com"))
        assertTrue(
            isTrustedSignInUrl("https://challenges.cloudflare.com/cdn-cgi/challenge-platform/")
        )
        assertFalse(isTrustedSignInHost("accounts.google.com"))
        assertFalse(signInContentIsVisible("Just a moment...", ""))
        assertFalse(signInContentIsVisible("Just a moment...", "email GitHub"))
        assertTrue(
            signInContentIsVisible(
                "Sign in",
                "Continue with email code or GitHub",
            )
        )
        assertTrue(signInContentIsVisible("登录", "用邮箱验证码或 GitHub 继续"))
    }

    @Test
    fun googleHostIsRejectedAndGithubStaysInsideTheSession() {
        assertTrue(isGoogleSignInHost("accounts.google.com"))
        assertTrue(isGoogleSignInHost("ACCOUNTS.GOOGLE.COM"))
        assertFalse(isTrustedSignInHost("accounts.google.com"))
        assertFalse(isTrustedSignInUrl("https://accounts.google.com/o/oauth2/v2/auth"))
        assertTrue(isTrustedSignInHost("github.com"))
        assertTrue(isTrustedSignInHost("authenticator.cursor.sh"))
    }

    @Test
    fun lookalikeAndUnrelatedHostsCannotJoinTheTrustedSession() {
        listOf(
                "cursor.com.evil.example",
                "authenticator.cursor.sh.evil.example",
                "other.cursor.sh",
                "evilworkos.com",
                "example.com",
                "",
            )
            .forEach { assertFalse(isTrustedSignInHost(it)) }
    }

    @Test
    fun trustedHostRequiresHttpsAndNoUserInfo() {
        assertTrue(
            isTrustedSignInUrl(
                "https://authenticator.cursor.sh/?redirect_uri=https%3A%2F%2Fcursor.com"
            )
        )
        listOf(
                "http://authenticator.cursor.sh",
                "javascript:alert(1)",
                "https://attacker@cursor.com",
                "https://cursor.com.evil.example",
            )
            .forEach { assertFalse(isTrustedSignInUrl(it)) }
    }
}
