package app.cursor.android

import app.cursor.android.data.ApiFailure
import app.cursor.android.data.CursorApi
import app.cursor.android.data.SseEvent
import app.cursor.android.data.SseParser
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
                { "fixture-key" },
                { "session=fixture; csrf-token=old" },
                server.url("/"),
                server.url("/"),
            )
    }

    @After
    fun teardown() {
        server.shutdown()
    }

    @Test
    fun authModesNeverMixAndPathsAreEncoded() = runTest {
        server.enqueue(MockResponse().setBody("{}"))
        api.request("GET", listOf("v1", "agents", "unsafe/id"))
        val official = server.takeRequest()
        assertEquals("Bearer fixture-key", official.getHeader("Authorization"))
        assertNull(official.getHeader("Cookie"))
        assertEquals("/v1/agents/unsafe%2Fid", official.path)
        server.enqueue(MockResponse().setBody("{}"))
        api.request("GET", listOf("api", "usage-summary"), web = true)
        val web = server.takeRequest()
        assertNull(web.getHeader("Authorization"))
        assertTrue(web.getHeader("Cookie")!!.contains("session=fixture"))
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
        assertEquals("/api/csrf-token", server.takeRequest().path)
        val retry = server.takeRequest()
        assertEquals("fresh", retry.getHeader("x-csrf-token"))
        assertEquals("""{"branchPrefix":"mobile/"}""", retry.body.readUtf8())
        assertFalse(retry.body.toString().contains("autoCreatePr"))
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
