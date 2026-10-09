package app.cursor.android

import app.cursor.android.data.ApiFailure
import app.cursor.android.data.ConversationUpdate
import app.cursor.android.data.CursorApi
import app.cursor.android.data.cookieAllowed
import app.cursor.android.data.endFrame
import app.cursor.android.data.interactionFrame
import app.cursor.android.data.sessionHeaders
import okhttp3.HttpUrl.Companion.toHttpUrl
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

class CursorApiTest {
    private lateinit var server: MockWebServer
    private lateinit var api: CursorApi

    @Before
    fun setup() {
        server = MockWebServer()
        server.start()
        api =
            CursorApi(
                { "session=fixture; csrf-token=old" },
                server.url("/"),
                allowConfiguredOrigin = true,
            )
    }

    @After
    fun teardown() {
        server.shutdown()
    }

    @Test
    fun sessionCookieNeverAddsAuthorizationAndPathsAreEncoded() = runTest {
        server.enqueue(MockResponse().setBody("{}"))
        api.request("GET", listOf("api", "auth", "me"))
        val web = server.takeRequest()
        assertNull(web.getHeader("Authorization"))
        assertTrue(web.getHeader("Cookie")!!.contains("session=fixture"))
        assertEquals("/api/auth/me", web.path)
        server.enqueue(MockResponse().setBody("{}"))
        api.request("GET", listOf("v1", "agents", "unsafe/id"))
        val encoded = server.takeRequest()
        assertNull(encoded.getHeader("Authorization"))
        assertEquals("/v1/agents/unsafe%2Fid", encoded.path)
    }

    @Test
    fun foreignHostGetsNoCookieAndNoAuthorization() = runTest {
        val blocked =
            CursorApi({ "session=secret-cookie" }, server.url("/"), allowConfiguredOrigin = false)
        val error =
            runCatching { blocked.request("GET", listOf("api", "auth", "me")) }.exceptionOrNull()
        assertTrue(error is ApiFailure)
        assertEquals("origin_rejected", (error as ApiFailure).code)
        assertFalse(error.message!!.contains("secret-cookie"))
        assertEquals(0, server.requestCount)
        assertFalse(
            cookieAllowed(server.url("/api/auth/me"), "https://cursor.com/".toHttpUrl(), false)
        )
        val allowed =
            sessionHeaders(
                "https://cursor.com/api/auth/me".toHttpUrl(),
                "session=secret-cookie",
                null,
                "GET",
            )
        assertNull(allowed["Authorization"])
        assertTrue(allowed["Cookie"]!!.contains("session=secret-cookie"))
    }

    @Test
    fun failureBodyDoesNotEchoTheCookie() = runTest {
        server.enqueue(
            MockResponse()
                .setResponseCode(500)
                .setBody("""{"error":{"code":"request_failed"},"echo":"session=fixture"}""")
        )
        val failure =
            runCatching { api.request("GET", listOf("api", "auth", "me")) }.exceptionOrNull()
                as ApiFailure
        assertFalse(failure.message!!.contains("session=fixture"))
        assertFalse(failure.toString().contains("csrf-token"))
    }

    @Test
    fun redirectsAreNotFollowedWithCredentials() = runTest {
        server.enqueue(
            MockResponse().setResponseCode(302).addHeader("Location", server.url("/other"))
        )
        val error = runCatching { api.request("GET", listOf("v1", "me")) }.exceptionOrNull()
        assertTrue(error is ApiFailure)
        assertEquals(1, server.requestCount)
    }

    @Test
    fun mutationErrorsAreNotAutomaticallyRetriedAndPreserveRetryAfter() = runTest {
        server.enqueue(
            MockResponse()
                .setResponseCode(429)
                .addHeader("Retry-After", "17")
                .setBody("""{"error":{"code":"rate_limited","message":"ignored"}}""")
        )
        val failure =
            runCatching { api.request("POST", listOf("v1", "agents")) }.exceptionOrNull()
                as ApiFailure
        assertEquals("rate_limited", failure.code)
        assertEquals("17", failure.retryAfter)
        assertEquals(1, server.requestCount)
    }

    @Test
    fun csrfFailureMintsTokenAndRetriesPatchOnlyOnce() = runTest {
        server.enqueue(
            MockResponse()
                .setResponseCode(403)
                .setBody("""{"error":{"code":"invalid_csrf_token"}}""")
        )
        server.enqueue(
            MockResponse().addHeader("Set-Cookie", "csrf-token=fresh; Path=/").setBody("{}")
        )
        server.enqueue(MockResponse().setBody("{}"))
        api.webSettings(buildJsonObject { put("branchPrefix", "mobile/") })
        assertEquals(3, server.requestCount)
        assertEquals("old", server.takeRequest().getHeader("x-csrf-token"))
        val refresh = server.takeRequest()
        assertEquals("/api/csrf-token", refresh.path)
        assertNull(refresh.getHeader("Authorization"))
        val retry = server.takeRequest()
        assertEquals("fresh", retry.getHeader("x-csrf-token"))
        assertEquals("""{"branchPrefix":"mobile/"}""", retry.body.readUtf8())
        assertFalse(retry.body.toString().contains("autoCreatePr"))
    }

    @Test
    fun secondCsrfFailureStops() = runTest {
        server.enqueue(
            MockResponse()
                .setResponseCode(403)
                .setBody("""{"error":{"code":"invalid_csrf_token"}}""")
        )
        server.enqueue(
            MockResponse().addHeader("Set-Cookie", "csrf-token=fresh; Path=/").setBody("{}")
        )
        server.enqueue(
            MockResponse()
                .setResponseCode(403)
                .setBody("""{"error":{"code":"invalid_csrf_token"}}""")
        )
        val failure =
            runCatching { api.webSettings(buildJsonObject { put("branchPrefix", "x") }) }
                .exceptionOrNull() as ApiFailure
        assertEquals("invalid_csrf_token", failure.code)
        assertEquals(3, server.requestCount)
    }

    @Test
    fun conversationUsesConnectFramesAndCarriesOffset() = runTest {
        val bytes = interactionFrame("off-1", "Hello") + endFrame()
        server.enqueue(MockResponse().setBody(okio.Buffer().write(bytes)))
        val updates = mutableListOf<ConversationUpdate>()
        api.conversation("bc-1", "previous") { updates += it }
        val request = server.takeRequest()
        assertEquals(
            "/api/connect-proxy/aiserver.v1.BackgroundComposerService/StreamConversation",
            request.path,
        )
        assertEquals("application/connect+proto", request.getHeader("Content-Type"))
        assertEquals("1", request.getHeader("Connect-Protocol-Version"))
        assertNull(request.getHeader("Authorization"))
        val payload = request.body.readByteArray().toString(Charsets.UTF_8)
        assertTrue(payload.contains("bc-1"))
        assertTrue(payload.contains("previous"))
        assertFalse(payload.contains("session=fixture"))
        assertEquals("Hello", updates.first { it.text.isNotBlank() }.text)
        assertEquals("off-1", updates.first { it.offsetKey != null }.offsetKey)
        assertTrue(updates.last().end)
    }

    @Test
    fun conversationEndErrorIsNotShownAsText() = runTest {
        val bytes =
            endFrame(
                """{"error":{"code":"usage_limit_exceeded","cookie":"session=fixture"}}"""
            )
        server.enqueue(MockResponse().setBody(okio.Buffer().write(bytes)))
        val failure =
            runCatching { api.conversation("bc", null) {} }.exceptionOrNull() as ApiFailure
        assertEquals("usage_limit_exceeded", failure.code)
        assertFalse(failure.message!!.contains("session=fixture"))
    }

    @Test
    fun cancellingVisibleStreamClosesSocketPromptly() =
        kotlinx.coroutines.runBlocking {
            val bytes = interactionFrame("off", "pending") + endFrame()
            server.enqueue(
                MockResponse()
                    .setBody(okio.Buffer().write(bytes))
                    .setBodyDelay(2, java.util.concurrent.TimeUnit.SECONDS)
            )
            val stream = launch { api.conversation("a", null) {} }
            kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) {
                server.takeRequest(5, java.util.concurrent.TimeUnit.SECONDS)
            }
            kotlinx.coroutines.delay(100)
            val started = System.nanoTime()
            stream.cancel()
            kotlinx.coroutines.withTimeout(2_000) { stream.join() }
            assertTrue((System.nanoTime() - started) / 1_000_000 < 2_000)
        }
}
