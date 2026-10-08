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
                    { credentials.read("api") },
                    { credentials.read("cookie") },
                    server.url("/"),
                    server.url("/"),
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
    fun terminalStreamReleasesFollowUpWithoutManualRefresh() = runBlocking {
        server.enqueue(MockResponse().setBody("""{"id":"a","status":"ACTIVE"}"""))
        server.enqueue(MockResponse().setBody("""{"items":[{"id":"r","status":"RUNNING"}]}"""))
        server.enqueue(
            MockResponse()
                .setBody(
                    "id: end\nevent: result\n" +
                        "data: {\"status\":\"FINISHED\",\"text\":\"Done\"}\n\n" +
                        "id: end\nevent: done\ndata: {}\n\n"
                )
        )
        server.enqueue(MockResponse().setBody("""{"items":[{"id":"r","status":"FINISHED"}]}"""))
        val collection = launch(Dispatchers.Unconfined) { model.uiState.collect {} }
        model.detail("a").join()
        val final =
            withTimeout(5_000) {
                model.uiState.first { it.local.runs.firstOrNull()?.string("status") == "FINISHED" }
            }
        assertEquals("Done", final.local.streamText)
        assertTrue(final.local.runs.none { it.string("status") in listOf("RUNNING", "CREATING") })
        collection.cancelAndJoin()
    }

    @Test
    fun failedEnvironmentSwitchCannotSubmitPreviousEnvironmentConfiguration() = runBlocking {
        val collection = launch(Dispatchers.Unconfined) { model.uiState.collect {} }
        server.enqueue(MockResponse().setBody("""{"id":"a","name":"A","environmentJson":"{}"}"""))
        server.enqueue(MockResponse().setBody("""{"items":[]}"""))
        model.environment("a").join()
        assertEquals(
            "a",
            withTimeout(5_000) { model.uiState.first { it.local.environment?.string("id") == "a" } }
                .local
                .environment!!
                .string("id"),
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
        server.enqueue(MockResponse().setBody("""{"id":"a","name":"A"}"""))
        server.enqueue(MockResponse().setBody("""{"items":[{"name":"TOKEN","id":"version"}]}"""))
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
