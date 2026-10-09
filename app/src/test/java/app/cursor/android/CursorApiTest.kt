package app.cursor.android

import app.cursor.android.data.ApiFailure
import app.cursor.android.data.CursorApi
import app.cursor.android.data.SseEvent
import app.cursor.android.data.SseParser
import app.cursor.android.data.cookieAllowed
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
    fun streamResumesOpaqueIdAndKeepsResultDoneWithSameId() = runTest {
        server.enqueue(
            MockResponse()
                .setHeader("Content-Type", "text/event-stream")
                .setBody(
                    "event: status\ndata: {\"status\":\"RUNNING\"}\n\n" +
                        "id: opaque:1\nevent: result\ndata: {\"text\":\"done\"}\n\n" +
                        "id: opaque:1\nevent: done\ndata: {}\n\n"
                )
        )
        val events = mutableListOf<SseEvent>()
        api.stream("bc-1", "run-1", "previous/opaque") { events += it }
        assertEquals("previous/opaque", server.takeRequest().getHeader("Last-Event-ID"))
        assertEquals(listOf("status", "result", "done"), events.map { it.type })
        assertNull(events[0].id)
        assertTrue(events[1].identity != events[2].identity)
    }

    @Test
    fun streamExpiryIsTypedForRepositoryFallback() = runTest {
        server.enqueue(
            MockResponse().setResponseCode(410).setBody("""{"error":{"code":"stream_expired"}}""")
        )
        val failure = runCatching { api.stream("bc", "run", "cursor") {} }.exceptionOrNull()
        assertEquals(410, (failure as ApiFailure).status)
    }

    @Test
    fun cancellingVisibleStreamClosesSocketPromptly() =
        kotlinx.coroutines.runBlocking {
            server.enqueue(
                MockResponse()
                    .setBody("event: heartbeat\ndata: {}\n\n")
                    .setBodyDelay(2, java.util.concurrent.TimeUnit.SECONDS)
            )
            val stream = launch { api.stream("a", "r", null) {} }
            kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) {
                server.takeRequest(5, java.util.concurrent.TimeUnit.SECONDS)
            }
            kotlinx.coroutines.delay(100)
            val started = System.nanoTime()
            stream.cancel()
            kotlinx.coroutines.withTimeout(2_000) { stream.join() }
            assertTrue((System.nanoTime() - started) / 1_000_000 < 2_000)
        }

    @Test
    fun parserSupportsCommentsMultilineAndEmptyIds() {
        val parser = SseParser()
        assertNull(parser.line(": heartbeat"))
        parser.line("id:")
        parser.line("event: assistant")
        parser.line("data: first")
        parser.line("data: second")
        assertEquals(SseEvent("", "assistant", "first\nsecond"), parser.line(""))
        parser.line("data: next")
        assertNull(parser.line("")!!.id)
    }
}
