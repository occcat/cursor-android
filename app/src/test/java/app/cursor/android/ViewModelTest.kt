package app.cursor.android

import app.cursor.android.data.CursorApi
import app.cursor.android.data.CursorRepository
import app.cursor.android.data.Preferences
import app.cursor.android.data.UserPreferences
import app.cursor.android.data.string
import app.cursor.android.ui.CursorViewModel
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.setMain
import kotlinx.coroutines.withTimeout
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

@OptIn(kotlinx.coroutines.ExperimentalCoroutinesApi::class)
class ViewModelTest {
    private lateinit var server: MockWebServer
    private lateinit var model: CursorViewModel

    @Before
    fun setup() {
        Dispatchers.setMain(Dispatchers.Unconfined)
        server = MockWebServer()
        server.start()
        val credentials = FakeCredentials()
        val repository =
            CursorRepository(
                CursorApi(
                    { credentials.read("cookie") },
                    server.url("/"),
                    allowConfiguredOrigin = true,
                ),
                FakeCache(),
                credentials,
            )
        model = CursorViewModel(repository, FakePreferences())
    }

    @After
    fun cleanup() {
        model.stopWatching()
        server.shutdown()
        Dispatchers.resetMain()
    }

    @Test
    fun detailShowsComposerStatusWithoutFakeLiveText() = runBlocking {
        server.enqueue(
            MockResponse()
                .setBody(
                    """{"composers":[{"composer":{"bcId":"a","name":"N","status":"RUNNING"}}]}"""
                )
        )
        val collection = launch(Dispatchers.Unconfined) { model.uiState.collect {} }
        model.detail("a").join()
        val shown =
            withTimeout(5_000) { model.uiState.first { it.local.detail?.string("bcId") == "a" } }
        assertEquals("RUNNING", shown.local.detail!!.string("status"))
        assertEquals("", shown.local.streamText)
        assertTrue(shown.local.runs.isEmpty())
        assertEquals(1, server.requestCount)
        val request = server.takeRequest()
        assertEquals("/api/background-composer/get-detailed-composer", request.path)
        assertTrue(request.body.readUtf8().contains("\"bcId\":\"a\""))
        collection.cancelAndJoin()
    }

    @Test
    fun failedEnvironmentSwitchCannotSubmitPreviousEnvironmentConfiguration() = runBlocking {
        val collection = launch(Dispatchers.Unconfined) { model.uiState.collect {} }
        server.enqueue(
            MockResponse()
                .setBody(
                    """{"environment":{"publicId":"a","name":"A","environmentJson":"{}"}}"""
                )
        )
        server.enqueue(MockResponse().setBody("""{"secrets":[]}"""))
        model.environment("a").join()
        assertEquals(
            "a",
            withTimeout(5_000) {
                    model.uiState.first { it.local.environment?.string("publicId") == "a" }
                }
                .local
                .environment!!
                .string("publicId"),
        )
        server.enqueue(MockResponse().setResponseCode(403))
        model.environment("b").join()
        assertNull(
            withTimeout(5_000) {
                    model.uiState.first { it.local.environment == null && it.local.error != null }
                }
                .local
                .environment
        )
        model.saveEnvironment("b", buildJsonObject { put("name", "A") }).join()
        assertEquals(3, server.requestCount)
        assertTrue(
            withTimeout(5_000) {
                    model.uiState.first { it.local.error?.contains("Reload") == true }
                }
                .local
                .error!!
                .contains("Reload")
        )
        collection.cancelAndJoin()
    }

    @Test
    fun addingExistingSecretDoesNotSilentlyRotateIt() = runBlocking {
        val collection = launch(Dispatchers.Unconfined) { model.uiState.collect {} }
        server.enqueue(MockResponse().setBody("""{"environment":{"publicId":"a","name":"A"}}"""))
        server.enqueue(
            MockResponse()
                .setBody("""{"secrets":[{"name":"TOKEN","id":"version","value":"hidden"}]}""")
        )
        model.environment("a").join()
        model.secret("a", "TOKEN", buildJsonObject { put("value", "replacement") }).join()
        assertEquals(2, server.requestCount)
        assertTrue(
            withTimeout(5_000) {
                    model.uiState.first { it.local.error?.contains("exists") == true }
                }
                .local
                .error!!
                .contains("exists")
        )
        collection.cancelAndJoin()
    }
}

class FakePreferences : UserPreferences {
    override val preferences = MutableStateFlow(Preferences())

    override suspend fun boolean(name: String, value: Boolean) = Unit

    override suspend fun interval(seconds: Int) = Unit

    override suspend fun language(language: String) = Unit
}
