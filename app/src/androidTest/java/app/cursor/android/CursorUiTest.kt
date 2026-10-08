package app.cursor.android

import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.platform.app.InstrumentationRegistry
import app.cursor.android.data.CredentialStore
import app.cursor.android.data.Preferences
import app.cursor.android.data.WebSessionStore
import app.cursor.android.domain.UsageSnapshot
import app.cursor.android.ui.UsageCapsule
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Rule
import org.junit.Test

class CursorUiTest {
    @get:Rule val compose = createComposeRule()

    @Test
    fun capsuleUpdatesBothPoolsAndHidesWhenDisabled() {
        val preferences = mutableStateOf(Preferences())
        compose.setContent {
            MaterialTheme {
                UsageCapsule(
                    UsageSnapshot(cursorUsed = 32.0, otherUsed = 61.0),
                    preferences.value,
                ) {
                    preferences.value = preferences.value.copy(remaining = false)
                }
            }
        }
        compose.onNodeWithContentDescription("Cursor Model 68% remaining").assertExists()
        compose.onNodeWithContentDescription("Other Model 39% remaining").assertExists()
        compose.onNodeWithContentDescription("Cursor Model 68% remaining").performClick()
        compose.onNodeWithContentDescription("Cursor Model 32% used").assertExists()
        compose.onNodeWithContentDescription("Other Model 61% used").assertExists()
        compose.runOnIdle { preferences.value = Preferences(cursor = false, other = false) }
        compose.onNodeWithText("remaining").assertDoesNotExist()
        compose.onNodeWithContentDescription("Cursor Model 68% remaining").assertDoesNotExist()
    }

    @Test
    fun keystoreRoundTripDoesNotPersistPlaintext() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val credentials = CredentialStore(context)
        credentials.write("test", "fixture-secret-only")
        assertEquals("fixture-secret-only", credentials.read("test"))
        val raw = context.getSharedPreferences("credentials", 0).getString("test", "")!!
        assertFalse(raw.contains("fixture-secret-only"))
        credentials.write("test", null)
        assertNull(credentials.read("test"))
    }

    @Test
    fun logoutClearsWebCookiesBeforeCompleting() = runBlocking {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        instrumentation.runOnMainSync {
            android.webkit.CookieManager.getInstance()
                .setCookie("https://cursor.com", "test=fixture")
            android.webkit.CookieManager.getInstance().flush()
        }
        WebSessionStore.clear()
        assertNull(android.webkit.CookieManager.getInstance().getCookie("https://cursor.com"))
    }
}
