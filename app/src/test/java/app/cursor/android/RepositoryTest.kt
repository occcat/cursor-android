package app.cursor.android

import app.cursor.android.data.CacheDao
import app.cursor.android.data.CacheEntry
import app.cursor.android.data.Credentials
import app.cursor.android.data.CursorApi
import app.cursor.android.data.CursorRepository
import app.cursor.android.data.items
import app.cursor.android.data.string
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.test.runTest
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

class RepositoryTest {
    private lateinit var server: MockWebServer
    private lateinit var cache: FakeCache
    private lateinit var repository: CursorRepository
    private lateinit var credentials: FakeCredentials

    @Before fun setup() {
        server = MockWebServer()
        server.start()
        cache = FakeCache()
        credentials = FakeCredentials()
        repository = CursorRepository(CursorApi({ credentials.read("api") },
            { credentials.read("cookie") }, server.url("/"), server.url("/")), cache, credentials)
    }

    @After fun cleanup() { server.shutdown() }

    @Test fun paginationFollowsCursorAndDeduplicatesIds() = runTest {
        server.enqueue(MockResponse().setBody("""{"items":[{"id":"a"}],"nextCursor":"two"}"""))
        server.enqueue(MockResponse().setBody("""{"items":[{"id":"a"},{"id":"b"}]}"""))
        repository.refreshAgents()
        repository.refreshAgents(true)
        assertEquals(listOf("a", "b"), repository.agents.first()!!.items().map { it.string("id") })
        server.takeRequest()
        assertTrue(server.takeRequest().path!!.contains("cursor=two"))
    }

    @Test fun usage401ClearsPrivateSnapshotAndStopsSession() = runTest {
        cache.put(CacheEntry("usage", "{\"cursorUsed\":32.0}", 1))
        server.enqueue(MockResponse().setResponseCode(401))
        runCatching { repository.refreshUsage() }
        assertNull(repository.usage.first())
        assertNull(credentials.read("cookie"))
    }

    @Test fun logoutClearsCredentialsAndEveryCachedSurface() = runTest {
        cache.put(CacheEntry("agents", "{\"items\":[]}", 1))
        repository.disconnect()
        assertNull(credentials.read("api"))
        assertNull(credentials.read("cookie"))
        assertNull(repository.agents.first())
    }

    @Test fun stream410FetchesFinalRunWithoutReplayingOldStream() = runTest {
        server.enqueue(MockResponse().setResponseCode(410)
            .setBody("""{"error":{"code":"stream_expired"}}"""))
        server.enqueue(MockResponse().setBody("""{"id":"r","status":"FINISHED","result":"Final"}"""))
        val values = repository.stream("a", "r").toList()
        assertEquals("Final", values.last().string("text"))
        assertEquals(2, server.requestCount)
        server.takeRequest()
        assertEquals("/v1/agents/a/runs/r", server.takeRequest().path)
    }

    @Test fun streamDuplicateEventsDoNotDuplicateTextAndCursorPersistsAfterProcessing() = runTest {
        server.enqueue(MockResponse().setBody(
            "id: one\nevent: assistant\ndata: {\"text\":\"Hello\"}\n\n" +
                "id: one\nevent: assistant\ndata: {\"text\":\"Hello\"}\n\n" +
                "id: end\nevent: result\ndata: {\"text\":\"Hello\"}\n\n" +
                "id: end\nevent: done\ndata: {}\n\n",
        ))
        assertEquals("Hello", repository.stream("a", "r").toList().last().string("text"))
        assertTrue(cache.get("stream/a/r")!!.json.contains("end"))
    }

    @Test fun repositoryPickerUsesHourlyCache() = runTest {
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
    override suspend fun put(entry: CacheEntry) { entries.value += entry.key to entry }
    override suspend fun clear() { entries.value = emptyMap() }
}
