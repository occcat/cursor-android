package app.cursor.android.data

import app.cursor.android.domain.UsageSnapshot
import java.io.IOException
import java.util.UUID
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.channelFlow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.put

fun JsonObject.string(name: String): String = (get(name) as? JsonPrimitive)?.contentOrNull.orEmpty()

fun JsonObject.items(): List<JsonObject> =
    (get("items") as? JsonArray)?.mapNotNull { it as? JsonObject }.orEmpty()

class CursorRepository(
    val api: CursorApi,
    private val cache: CacheDao,
    private val credentials: Credentials,
    private val clearWebSession: suspend () -> Unit = {},
) {
    private val lock = Mutex()
    @Volatile private var generation = 0L
    val agents = cache.observe("agents").map { it?.json?.let(Json::parseToJsonElement)?.jsonObject }
    val usage =
        cache.observe("usage").map {
            it?.json?.let { text -> Json.decodeFromString<UsageSnapshot?>(text) }
        }
    val connected: Boolean
        get() = credentials.read("api") != null

    val webConnected: Boolean
        get() = credentials.read("cookie") != null

    suspend fun connect(key: String) {
        require(key.isNotBlank() && '\n' !in key && '\r' !in key)
        val verification = CursorApi({ key.trim() }, { null })
        verification.request("GET", listOf("v1", "me"))
        lock.withLock {
            generation++
            cache.clear()
            credentials.write("api", key.trim())
        }
    }

    suspend fun connectWeb(cookie: String) {
        val verification = CursorApi({ null }, { cookie })
        val value = verification.request("GET", listOf("api", "usage-summary"), web = true)
        lock.withLock {
            generation++
            api.resetWebSession()
            credentials.write("cookie", cookie)
            cache.put(
                CacheEntry(
                    "usage",
                    Json.encodeToString(UsageSnapshot.fromJson(value, System.currentTimeMillis())),
                    System.currentTimeMillis(),
                )
            )
        }
    }

    suspend fun disconnect() =
        lock.withLock {
            generation++
            credentials.write("api", null)
            credentials.write("cookie", null)
            api.resetWebSession()
            cache.clear()
            clearWebSession()
        }

    suspend fun refreshAgents(more: Boolean = false) {
        val session = generation
        val previous = cache.get("agents")?.json?.let(Json::parseToJsonElement)?.jsonObject
        val cursor = if (more) previous?.string("nextCursor") else null
        if (more && cursor.isNullOrBlank()) return
        val response =
            api.request(
                "GET",
                listOf("v1", "agents"),
                query =
                    buildMap {
                        put("limit", "100")
                        put("includeArchived", "true")
                        if (!cursor.isNullOrBlank()) put("cursor", cursor)
                    },
            )
        val combined =
            if (more && previous != null) {
                JsonObject(
                    response +
                        ("items" to
                            JsonArray(
                                (previous.items() + response.items()).distinctBy { it.string("id") }
                            ))
                )
            } else response
        persist(session, "agents", combined.toString())
    }

    suspend fun refreshUsage() {
        val session = generation
        try {
            val json = api.request("GET", listOf("api", "usage-summary"), web = true)
            persist(
                session,
                "usage",
                Json.encodeToString(UsageSnapshot.fromJson(json, System.currentTimeMillis())),
            )
        } catch (failure: ApiFailure) {
            if (failure.status == 401)
                lock.withLock {
                    if (generation == session) {
                        credentials.write("cookie", null)
                        cache.put(CacheEntry("usage", "null", System.currentTimeMillis()))
                    }
                }
            throw failure
        }
    }

    suspend fun cachedResource(path: List<String>, refresh: Boolean = true): JsonObject {
        val session = generation
        val key = path.joinToString("/")
        val cached = cache.get(key)
        if (!refresh && cached != null) return Json.parseToJsonElement(cached.json).jsonObject
        val result =
            try {
                api.request("GET", listOf("v1") + path)
            } catch (failure: IOException) {
                if (failure is ApiFailure || cached == null) throw failure
                return Json.parseToJsonElement(cached.json).jsonObject
            }
        persist(session, key, result.toString())
        return result
    }

    suspend fun repositories(): JsonObject {
        val cached = cache.get("repositories")
        if (cached != null && System.currentTimeMillis() - cached.updatedAt < 3_600_000L) {
            return Json.parseToJsonElement(cached.json).jsonObject
        }
        return cachedResource(listOf("repositories"))
    }

    suspend fun create(
        prompt: String,
        repos: List<String>,
        model: String,
        environment: String,
        plan: Boolean,
        autoPr: Boolean,
    ): String {
        val id = "bc-${UUID.randomUUID()}"
        persist(generation, "pendingCreate", buildJsonObject { put("id", id) }.toString())
        val body = buildJsonObject {
            put("agentId", id)
            put("prompt", buildJsonObject { put("text", prompt.trim()) })
            if (model.isNotBlank()) put("model", buildJsonObject { put("id", model) })
            if (environment.isNotBlank()) {
                put(
                    "env",
                    buildJsonObject {
                        put("type", "cloud")
                        put("name", environment)
                    },
                )
            } else if (repos.isNotEmpty()) {
                put("repos", JsonArray(repos.map { buildJsonObject { put("url", it) } }))
            }
            put("mode", if (plan) "plan" else "agent")
            put("autoCreatePR", autoPr)
        }
        try {
            api.request("POST", listOf("v1", "agents"), body)
        } catch (exception: IOException) {
            if (exception is ApiFailure) throw exception
            try {
                api.request("GET", listOf("v1", "agents", id))
            } catch (_: IOException) {
                throw IOException("Creation outcome unknown; refresh agents before sending again")
            }
        }
        runCatching { refreshAgents() }.onFailure { if (it is CancellationException) throw it }
        return id
    }

    suspend fun followUp(agent: String, prompt: String) {
        try {
            api.request(
                "POST",
                listOf("v1", "agents", agent, "runs"),
                buildJsonObject { put("prompt", buildJsonObject { put("text", prompt.trim()) }) },
            )
        } catch (exception: IOException) {
            if (exception is ApiFailure) throw exception
            throw IOException("Send outcome unknown; refresh runs before sending again")
        }
    }

    suspend fun action(agent: String, action: String, run: String? = null) {
        val path = listOf("v1", "agents", agent)
        when (action) {
            "delete" -> api.request("DELETE", path)
            "cancel" -> api.request("POST", path + listOf("runs", requireNotNull(run), "cancel"))
            "archive",
            "unarchive" -> api.request("POST", path + action)
            else -> error("Unsupported action")
        }
        refreshAgents()
    }

    fun stream(agent: String, run: String): Flow<JsonObject> = channelFlow {
        val session = generation
        val cacheKey = "stream/$agent/$run"
        var stored =
            cache.get(cacheKey)?.json?.let(Json::parseToJsonElement)?.jsonObject
                ?: buildJsonObject {
                    put("text", "")
                    put("lastId", "")
                    put("seen", JsonArray(emptyList()))
                }
        send(stored)
        var failures = 0
        while (failures < 5 && session == generation) {
            var done = false
            try {
                api.stream(agent, run, stored.string("lastId")) { event ->
                    val seen = (stored["seen"] as? JsonArray)?.map { it.toString() }.orEmpty()
                    val identity = event.identity?.let { JsonPrimitive(it).toString() }
                    if (identity == null || identity !in seen) {
                        val payload =
                            runCatching { Json.parseToJsonElement(event.data).jsonObject }
                                .getOrNull() ?: JsonObject(emptyMap())
                        if (event.type == "error") {
                            throw ApiFailure(400, payload.string("code").ifBlank { "stream_error" })
                        }
                        val text =
                            when (event.type) {
                                "assistant" -> stored.string("text") + payload.string("text")
                                "result" -> payload.string("text").ifBlank { stored.string("text") }
                                else -> stored.string("text")
                            }
                        stored = buildJsonObject {
                            put("text", text)
                            put(
                                "status",
                                payload.string("status").ifBlank { stored.string("status") },
                            )
                            put("lastId", event.id ?: stored.string("lastId"))
                            put(
                                "seen",
                                JsonArray(
                                    (seen + listOfNotNull(identity)).map(Json::parseToJsonElement)
                                ),
                            )
                        }
                        persist(session, cacheKey, stored.toString())
                        send(stored)
                    }
                    if (
                        event.type == "done" ||
                            (event.type == "result" &&
                                stored.string("status") in
                                    listOf("FINISHED", "ERROR", "CANCELLED", "EXPIRED"))
                    )
                        done = true
                }
                if (done) break
                failures++
                delay((1000L shl failures).coerceAtMost(30_000))
            } catch (exception: IOException) {
                if (exception is ApiFailure && exception.status == 410) {
                    val result = cachedResource(listOf("agents", agent, "runs", run))
                    send(
                        buildJsonObject {
                            put("text", result.string("result"))
                            put("status", result.string("status"))
                            put("expired", true)
                        }
                    )
                    break
                }
                if (exception is ApiFailure && exception.status in listOf(400, 401, 403))
                    throw exception
                failures++
                val retry = retryDelayMillis((exception as? ApiFailure)?.retryAfter)
                delay(retry ?: ((1000L shl failures) + kotlin.random.Random.nextLong(500)))
            }
        }
        if (failures >= 5) throw IOException("Live connection paused; refresh to reconnect")
    }

    private suspend fun persist(session: Long, key: String, json: String) =
        lock.withLock {
            if (generation == session) cache.put(CacheEntry(key, json, System.currentTimeMillis()))
        }
}

fun retryDelayMillis(header: String?, now: Long = System.currentTimeMillis()): Long? {
    if (header == null) return null
    header
        .toLongOrNull()
        ?.takeIf { it >= 0 }
        ?.let {
            return it.coerceAtMost(Long.MAX_VALUE / 1000) * 1000
        }
    return runCatching {
            (java.time.ZonedDateTime.parse(
                        header,
                        java.time.format.DateTimeFormatter.RFC_1123_DATE_TIME,
                    )
                    .toInstant()
                    .toEpochMilli() - now)
                .coerceAtLeast(0)
        }
        .getOrNull()
}
