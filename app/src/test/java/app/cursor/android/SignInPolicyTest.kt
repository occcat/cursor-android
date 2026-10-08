package app.cursor.android

import app.cursor.android.domain.isTrustedSignInHost
import app.cursor.android.domain.isTrustedSignInUrl
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
                "ACCOUNTS.GOOGLE.COM",
            )
            .forEach { assertTrue(isTrustedSignInHost(it)) }
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
