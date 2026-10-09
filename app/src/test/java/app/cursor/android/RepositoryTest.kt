package app.cursor.android

import app.cursor.android.data.CacheDao
import app.cursor.android.data.CacheEntry
import app.cursor.android.data.Credentials
import app.cursor.android.data.CursorApi
import app.cursor.android.data.CursorRepository
import app.cursor.android.data.MemoryMigration
import app.cursor.android.data.array
import app.cursor.android.data.normalizeComposer
import app.cursor.android.data.string
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.mockwebserver.SocketPolicy
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

class RepositoryTest {
    private lateinit var server: MockWebServer
    private lateinit var cache: FakeCache
    private lateinit var repository: CursorRepository
    private lateinit var credentials: FakeCredentials

    @Before
    fun setup() {
        server = MockWebServer()
        server.start()
        cache = FakeCache()
        credentials = FakeCredentials()
        repository =
            CursorRepository(
                CursorApi(
                    { credentials.read("cookie") },
                    server.url("/"),
                    allowConfiguredOrigin = true,
                ),
                cache,
                credentials,
            )
    }

    @After
    fun cleanup() {
        server.shutdown()
    }

    @Test
    fun lateAgentResponseCannotRestorePrivateDataAfterDisconnect() = runTest {
        server.enqueue(
            MockResponse()
                .setBody("{\"items\":[{\"id\":\"old-account\"}]}")
                .setBodyDelay(200, java.util.concurrent.TimeUnit.MILLISECONDS)
        )
        val refresh = async(Dispatchers.IO) { repository.refreshAgents() }
        org.junit.Assert.assertNotNull(server.takeRequest(5, java.util.concurrent.TimeUnit.SECONDS))
        repository.disconnect()
        refresh.await()
        assertNull(repository.agentSnapshot.first())
        assertEquals(false, repository.connections.first().web)
    }

    @Test
    fun timestampedAgentSnapshotUsesPersistedFetchTimeAndClearsOnLogout() = runTest {
        cache.put(CacheEntry("agents", "{\"items\":[{\"id\":\"a\"}]}", 1234))
        assertEquals(1234, repository.agentSnapshot.first()!!.updatedAt)
        repository.disconnect()
        assertNull(repository.agentSnapshot.first())
        assertEquals(false, repository.connections.first().web)
    }

    @Test
    fun expiredSessionClearsCookieAndCachedAgents() = runTest {
        cache.put(CacheEntry("agents", "{\"items\":[{\"id\":\"a\"}]}", 1234))
        server.enqueue(MockResponse().setResponseCode(401))
        runCatching { repository.refreshAgents() }
        assertNull(repository.agentSnapshot.first())
        assertNull(credentials.read("api"))
        assertNull(credentials.read("cookie"))
        assertEquals(false, repository.connections.first().web)
    }

    @Test
    fun me401DeletesCookieAnd403DoesNot() = runTest {
        val migration = MemoryMigration()
        val local = signedInRepository(migration)
        server.enqueue(MockResponse().setResponseCode(401))
        local.restore()
        assertNull(credentials.read("cookie"))
        assertEquals(false, local.connections.first().web)
        credentials.write("cookie", "session=fixture")
        server.enqueue(
            MockResponse().setResponseCode(403).setBody("""{"error":{"code":"forbidden"}}""")
        )
        local.restore()
        assertEquals("session=fixture", credentials.read("cookie"))
        assertEquals(true, local.connections.first().web)
    }

    @Test
    fun upgradeDropsApiKeyClearsRemoteCacheAndSignsInOnlyAfterMe() = runTest {
        val migration = MemoryMigration()
        val local = signedInRepository(migration)
        credentials.write("api", "crsr_secret")
        credentials.write("cookie", null)
        cache.put(CacheEntry("agents", "{\"items\":[{\"id\":\"old\"}]}", 1))
        cache.put(CacheEntry("usage", "{\"cursorUsed\":32.0}", 1))
        local.restore()
        assertNull(credentials.read("api"))
        assertNull(cache.get("agents"))
        assertEquals("{\"cursorUsed\":32.0}", cache.get("usage")!!.json)
        assertEquals(false, local.webConnected)
        assertEquals(0, server.requestCount)

        credentials.write("api", "crsr_secret")
        credentials.write("cookie", "session=live")
        cache.put(CacheEntry("agents", "{\"items\":[{\"id\":\"old\"}]}", 2))
        migration.let {
            val again = MemoryMigration()
            val second = signedInRepository(again)
            server.enqueue(
                MockResponse().setBody("""{"email":"a@example.com","name":"A","id":"user-1"}""")
            )
            second.restore()
            assertNull(credentials.read("api"))
            assertEquals("session=live", credentials.read("cookie"))
            assertNull(cache.get("agents"))
            assertEquals(true, second.webConnected)
            val me = server.takeRequest()
            assertEquals("/api/auth/me", me.path)
            assertNull(me.getHeader("Authorization"))
            assertTrue(me.getHeader("Cookie")!!.contains("session=live"))
            assertFalse(me.getHeader("Cookie")!!.contains("crsr_secret"))
        }
    }

    @Test
    fun paginationFollowsWebOffsetAndDeduplicatesBcIds() = runTest {
        server.enqueue(
            MockResponse()
                .setBody(
                    """{"composers":[{"bcId":"a","name":"A"}],"hasMore":true,"nextPageOffset":20}"""
                )
        )
        server.enqueue(
            MockResponse()
                .setBody("""{"composers":[{"bcId":"a"},{"bcId":"b","name":"B"}],"hasMore":false}""")
        )
        repository.refreshAgents()
        repository.refreshAgents(true)
        val composers = repository.agents.first()!!.array("composers")
        assertEquals(listOf("a", "b"), composers.map { it.string("bcId") })
        assertEquals("POST", server.takeRequest().method)
        val page = server.takeRequest()
        assertEquals("/api/background-composer/list", page.path)
        val body = page.body.readUtf8()
        assertTrue(body.contains("last_message_activity_at_ms_offset"))
        assertFalse(body.contains("nextCursor"))
        assertFalse(body.contains("\"items\""))
    }

    @Test
    fun writesUseWebFieldsAndDoNotRetryAfterTimeout() = runTest {
        server.enqueue(MockResponse().setBody("{}"))
        server.enqueue(MockResponse().setBody("""{"composers":[]}"""))
        repository.create("build it", listOf("https://github.com/a/b"), "gpt", "")
        val created = server.takeRequest()
        assertEquals("POST", created.method)
        assertEquals("/api/auth/startBackgroundComposerFromSnapshot", created.path)
        val body = created.body.readUtf8()
        assertTrue(body.contains("\"bcId\""))
        assertTrue(body.contains("\"prompt\":\"build it\""))
        assertTrue(body.contains("\"repoUrl\":\"https://github.com/a/b\""))
        assertTrue(body.contains("\"modelId\":\"gpt\""))
        assertTrue(body.contains("expectedScope"))
        assertFalse(body.contains("\"text\""))
        assertFalse(body.contains("autoCreatePR"))
        assertFalse(body.contains("\"env\""))
        assertFalse(body.contains("\"mode\""))
        assertNull(created.getHeader("Authorization"))
        server.takeRequest()

        val beforeFollowUp = server.requestCount
        server.enqueue(MockResponse().setSocketPolicy(SocketPolicy.DISCONNECT_AFTER_REQUEST))
        server.enqueue(MockResponse().setBody("""{"composers":[{"bcId":"bc"}]}"""))
        val error = runCatching { repository.followUp("bc", "next step") }.exceptionOrNull()
        assertTrue(error is java.io.IOException)
        assertTrue(error !is app.cursor.android.data.ApiFailure)
        assertEquals(beforeFollowUp + 2, server.requestCount)
        assertEquals(
            "/api/auth/addAsyncFollowupBackgroundComposer",
            server.takeRequest().path,
        )
        assertEquals("/api/background-composer/get-detailed-composer", server.takeRequest().path)

        server.enqueue(MockResponse().setBody("{}"))
        server.enqueue(MockResponse().setBody("""{"composers":[]}"""))
        assertFalse(repository.action("bc", "pause"))
        val pause = server.takeRequest()
        assertEquals("/api/background-composer/pause", pause.path)
        val pauseBody = pause.body.readUtf8()
        assertTrue(pauseBody.contains("\"bcId\":\"bc\""))
        assertFalse(pauseBody.contains("cancel"))
        server.takeRequest()

        server.enqueue(MockResponse().setBody("""{"bcId":"bc"}"""))
        server.enqueue(MockResponse().setBody("""{"composers":[]}"""))
        assertTrue(repository.action("bc", "unarchive"))
        val restore = server.takeRequest()
        assertEquals("/api/auth/archiveBackgroundComposer", restore.path)
        assertTrue(restore.body.readUtf8().contains("\"unarchive\":true"))
    }

    @Test
    fun secretMetadataDropsValuesAndEmptyArtifactsStayEmpty() = runTest {
        server.enqueue(
            MockResponse().setBody("""{"secrets":[{"name":"TOKEN","value":"hidden"}]}""")
        )
        val secrets = repository.secrets("env")
        assertEquals("TOKEN", secrets.array("secrets").single().string("name"))
        assertFalse(cache.get("secrets/env")!!.json.contains("hidden"))
        server.enqueue(MockResponse().setBody("{}"))
        assertTrue(repository.artifacts("bc").array("artifacts").isEmpty())
    }

    @Test
    fun webListAndDetailTolerateMissingFields() = runTest {
        server.enqueue(MockResponse().setBody("""{"composers":[{"name":"only"}]}"""))
        repository.refreshAgents()
        val row = repository.agents.first()!!.array("composers").single()
        assertEquals("", row.string("bcId"))
        assertEquals("only", row.string("name"))
        val detail =
            normalizeComposer("bc-1", Json.parseToJsonElement("""{"composers":[{}]}""").jsonObject)
        assertEquals("bc-1", detail.string("bcId"))
        assertEquals("", detail.string("status"))
        val usage =
            app.cursor.android.domain.UsageSnapshot.fromJson(
                Json.parseToJsonElement("""{"individualUsage":{"plan":{}}}""").jsonObject,
                1,
            )
        assertNull(usage.cursorUsed)
        assertNull(usage.otherUsed)
    }

    @Test
    fun usage401ClearsPrivateSnapshotAndStopsSession() = runTest {
        cache.put(CacheEntry("usage", "{\"cursorUsed\":32.0}", 1))
        server.enqueue(MockResponse().setResponseCode(401))
        runCatching { repository.refreshUsage() }
        assertNull(repository.usage.first())
        assertNull(credentials.read("cookie"))
    }

    @Test
    fun logoutClearsCredentialsAndEveryCachedSurface() = runTest {
        cache.put(CacheEntry("agents", "{\"items\":[]}", 1))
        repository.disconnect()
        assertNull(credentials.read("api"))
        assertNull(credentials.read("cookie"))
        assertNull(repository.agents.first())
    }

    @Test
    fun stream410FetchesFinalRunWithoutReplayingOldStream() = runTest {
        server.enqueue(
            MockResponse().setResponseCode(410).setBody("""{"error":{"code":"stream_expired"}}""")
        )
        server.enqueue(
            MockResponse().setBody("""{"id":"r","status":"FINISHED","result":"Final"}""")
        )
        val values = repository.stream("a", "r").toList()
        assertEquals("Final", values.last().string("text"))
        assertEquals(2, server.requestCount)
        server.takeRequest()
        assertEquals("/v1/agents/a/runs/r", server.takeRequest().path)
    }

    @Test
    fun streamDuplicateEventsDoNotDuplicateTextAndCursorPersistsAfterProcessing() = runTest {
        server.enqueue(
            MockResponse()
                .setBody(
                    "id: one\nevent: assistant\ndata: {\"text\":\"Hello\"}\n\n" +
                        "id: one\nevent: assistant\ndata: {\"text\":\"Hello\"}\n\n" +
                        "id: end\nevent: result\ndata: {\"text\":\"Hello\"}\n\n" +
                        "id: end\nevent: done\ndata: {}\n\n"
                )
        )
        assertEquals("Hello", repository.stream("a", "r").toList().last().string("text"))
        assertTrue(cache.get("stream/a/r")!!.json.contains("end"))
    }

    @Test
    fun logoutWaitsForWebSessionCleanup() = runTest {
        var cleared = false
        val local =
            CursorRepository(
                CursorApi({ "cookie" }, server.url("/"), allowConfiguredOrigin = true),
                cache,
                credentials,
            ) {
                kotlinx.coroutines.delay(50)
                cleared = true
            }
        local.disconnect()
        assertTrue(cleared)
        assertNull(credentials.read("cookie"))
    }

    @Test
    fun streamErrorDoesNotAppearAsSuccessfulCompletion() = runTest {
        server.enqueue(
            MockResponse().setBody("event: error\ndata: {\"code\":\"usage_limit_exceeded\"}\n\n")
        )
        val error = runCatching { repository.stream("a", "r").toList() }.exceptionOrNull()
        assertEquals("usage_limit_exceeded", (error as app.cursor.android.data.ApiFailure).code)
    }

    @Test
    fun retryAfterIsRespectedBeyondTwoMinutesAndSupportsHttpDates() {
        assertEquals(300_000L, app.cursor.android.data.retryDelayMillis("300"))
        assertEquals(
            60_000L,
            app.cursor.android.data.retryDelayMillis(
                "Thu, 01 Oct 2026 12:01:00 GMT",
                java.time.Instant.parse("2026-10-01T12:00:00Z").toEpochMilli(),
            ),
        )
    }

    private fun signedInRepository(migration: MemoryMigration) =
        CursorRepository(
            CursorApi(
                { credentials.read("cookie") },
                server.url("/"),
                allowConfiguredOrigin = true,
            ),
            cache,
            credentials,
            migration,
        )

    @Test
    fun repositoryPickerUsesHourlyCache() = runTest {
        server.enqueue(MockResponse().setBody("""{"items":[{"url":"https://github.com/a/b"}]}"""))
        repository.repositories()
        repository.repositories()
        assertEquals(1, server.requestCount)
    }
}

class FakeCredentials : Credentials {
    private val values = mutableMapOf("api" to "fixture", "cookie" to "session=fixture")

    override fun read(name: String) = values[name]

    override fun write(name: String, value: String?) {
        if (value == null) values.remove(name) else values[name] = value
    }
}

class FakeCache : CacheDao {
    private val entries = MutableStateFlow<Map<String, CacheEntry>>(emptyMap())

    override fun observe(key: String) = entries.map { it[key] }

    override suspend fun get(key: String) = entries.value[key]

    override suspend fun put(entry: CacheEntry) {
        entries.value += entry.key to entry
    }

    override suspend fun clear() {
        entries.value = emptyMap()
    }

    override suspend fun clearExcept(keep: String) {
        entries.value = entries.value.filterKeys { it == keep }
    }
}
