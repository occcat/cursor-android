package app.cursor.android.data

import app.cursor.android.domain.UsageSnapshot
import java.io.IOException
import java.util.UUID
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.channelFlow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.put

fun JsonObject.string(name: String): String = (get(name) as? JsonPrimitive)?.contentOrNull.orEmpty()

fun JsonObject.items(): List<JsonObject> =
    (get("items") as? JsonArray)?.mapNotNull { it as? JsonObject }.orEmpty()

fun JsonObject.array(name: String): List<JsonObject> =
    (get(name) as? JsonArray)?.mapNotNull { it as? JsonObject }.orEmpty()

data class AgentSnapshot(val agents: List<JsonObject>, val updatedAt: Long)

/** The only connection is the cursor.com web session. */
data class Connections(val web: Boolean)

class CursorRepository(
    val api: CursorApi,
    private val cache: CacheDao,
    private val credentials: Credentials,
    private val migration: SessionMigration = MemoryMigration(true),
    private val clearWebSession: suspend () -> Unit = {},
) {
    private val lock = Mutex()
    @Volatile private var generation = 0L
    private val connectionState = MutableStateFlow(Connections(false))
    val connections = connectionState.asStateFlow()
    val agentSnapshot =
        cache.observe("agents").map { entry ->
            entry?.let {
                (Json.parseToJsonElement(it.json) as? JsonObject)?.let { value ->
                    AgentSnapshot(value.array("composers"), it.updatedAt)
                }
            }
        }
    val agents =
        cache.observe("agents").map { it?.json?.let(Json::parseToJsonElement) as? JsonObject }
    val usage =
        cache.observe("usage").map {
            it?.json?.let { text -> Json.decodeFromString<UsageSnapshot?>(text) }
        }
    val webConnected: Boolean
        get() = connectionState.value.web

    /**
     * First launch after this upgrade drops any API key, clears remote v1 cache, and
     * keeps a cookie only when GET /api/auth/me returns 200.
     */
    suspend fun restore() {
        val session = generation
        val upgrading = !migration.completed()
        if (upgrading) {
            credentials.write("api", null)
            cache.clearExcept("usage")
            migration.markCompleted()
        } else if (credentials.read("api") != null) {
            credentials.write("api", null)
        }
        val cookie = credentials.read("cookie")
        if (cookie.isNullOrBlank()) {
            connectionState.value = Connections(false)
            return
        }
        try {
            val me = api.request("GET", listOf("api", "auth", "me"))
            persist(session, "identity", identityOf(me).toString())
            if (generation == session) connectionState.value = Connections(true)
        } catch (failure: ApiFailure) {
            if (failure.status == 401) expire(session)
            else if (failure.status != 403) throw failure
            else if (generation == session) connectionState.value = Connections(true)
        } catch (_: IOException) {
            val stale = upgrading || cache.get("usage") != null || cache.get("identity") != null
            if (generation == session) connectionState.value = Connections(stale)
        }
    }

    suspend fun connectWeb(cookie: String) {
        require(cookie.isNotBlank() && '\n' !in cookie && '\r' !in cookie)
        val me = api.request("GET", listOf("api", "auth", "me"), cookieOverride = cookie)
        lock.withLock {
            generation++
            api.resetWebSession()
            credentials.write("api", null)
            credentials.write("cookie", cookie)
            connectionState.value = Connections(true)
            cache.put(
                CacheEntry("identity", identityOf(me).toString(), System.currentTimeMillis())
            )
        }
    }

    suspend fun disconnect() =
        lock.withLock {
            generation++
            credentials.write("api", null)
            credentials.write("cookie", null)
            connectionState.value = Connections(false)
            api.resetWebSession()
            cache.clear()
            clearWebSession()
        }

    private suspend fun expire(session: Long) {
        lock.withLock {
            if (generation != session) return
            generation++
            credentials.write("api", null)
            credentials.write("cookie", null)
            connectionState.value = Connections(false)
            api.resetWebSession()
            cache.clear()
            clearWebSession()
        }
    }

    suspend fun refreshAgents(more: Boolean = false) {
        val session = generation
        val previous = cache.get("agents")?.json?.let(Json::parseToJsonElement) as? JsonObject
        val hasMore = (previous?.get("hasMore") as? JsonPrimitive)?.booleanOrNull == true
        val offset = if (more) previous?.get("nextPageOffset") else null
        if (more && (!hasMore || offset == null)) return
        val body = buildJsonObject {
            put("n", 50)
            put("include_status", true)
            put("include_archived", true)
            put("include_pinned_state", true)
            if (more && offset != null) put("last_message_activity_at_ms_offset", offset)
        }
        val response =
            try {
                api.request("POST", listOf("api", "background-composer", "list"), body)
            } catch (failure: ApiFailure) {
                if (failure.status == 401) expire(session)
                throw failure
            }
        val combined =
            if (more && previous != null) {
                val merged =
                    (previous.array("composers") + response.array("composers")).distinctBy {
                        it.string("bcId")
                    }
                JsonObject(response + ("composers" to JsonArray(merged)))
            } else response
        persist(session, "agents", combined.toString())
    }

    suspend fun composer(id: String): JsonObject {
        val session = generation
        val key = "composer/$id"
        val result =
            try {
                api.request(
                    "POST",
                    listOf("api", "background-composer", "get-detailed-composer"),
                    buildJsonObject {
                        put("bcId", id)
                        put("n", 1)
                        put("includeTeamWide", true)
                    },
                )
            } catch (failure: ApiFailure) {
                if (failure.status == 401) expire(session)
                throw failure
            } catch (failure: IOException) {
                val cached = cache.get(key) ?: throw failure
                return Json.parseToJsonElement(cached.json).jsonObject
            }
        val normalized = normalizeComposer(id, result)
        persist(session, key, normalized.toString())
        return normalized
    }

    suspend fun models(): JsonObject = postCached(
        "models",
        listOf("api", "background-composer", "available-models"),
    )

    suspend fun environments(): JsonObject {
        val session = generation
        val shared =
            authed(session) {
                api.request(
                    "POST",
                    listOf("api", "background-composer", "list-environments"),
                    buildJsonObject {},
                )
            }
        val personal =
            authed(session) {
                api.request(
                    "POST",
                    listOf("api", "background-composer", "list-personal-environments"),
                    buildJsonObject {},
                )
            }
        val merged =
            (shared.array("environments") + personal.array("environments")).distinctBy {
                it.string("publicId")
            }
        val value = buildJsonObject { put("environments", JsonArray(merged)) }
        persist(session, "environments", value.toString())
        return value
    }

    suspend fun environment(id: String): JsonObject {
        val session = generation
        val result =
            authed(session) {
                api.request(
                    "POST",
                    listOf("api", "background-composer", "get-environment"),
                    buildJsonObject {
                        put("publicId", id)
                        put("includeEnvironmentJson", true)
                    },
                )
            }
        val env = (result["environment"] as? JsonObject) ?: result
        val normalized = buildJsonObject {
            put("publicId", env.string("publicId").ifBlank { id })
            put("name", env.string("name"))
            put("environmentJson", environmentJsonText(env["environmentJson"]))
        }
        persist(session, "environment/$id", normalized.toString())
        return normalized
    }

    suspend fun secrets(environmentId: String): JsonObject {
        val session = generation
        val result =
            authed(session) {
                api.request(
                    "POST",
                    listOf("api", "background-composer", "list-background-composer-secrets"),
                    buildJsonObject { put("redact", true) },
                )
            }
        val listed =
            result.array("secrets").map { secret ->
                JsonObject(secret.filterKeys { it != "value" && it != "secretValue" })
            }
        val value = buildJsonObject { put("secrets", JsonArray(listed)) }
        persist(session, "secrets/$environmentId", value.toString())
        return value
    }

    suspend fun artifacts(id: String): JsonObject {
        val session = generation
        val result =
            authed(session) {
                api.request(
                    "POST",
                    listOf("api", "background-composer", "list-artifacts"),
                    buildJsonObject { put("bcId", id) },
                )
            }
        val value = buildJsonObject { put("artifacts", JsonArray(result.array("artifacts"))) }
        persist(session, "artifacts/$id", value.toString())
        return value
    }

    suspend fun artifactBytes(id: String, artifact: JsonObject): JsonObject {
        val session = generation
        return authed(session) {
            api.request(
                "POST",
                listOf("api", "background-composer", "get-artifact-bytes"),
                buildJsonObject {
                    put("bcId", id)
                    listOf("path", "absolutePath", "name").forEach { field ->
                        val present = artifact.string(field)
                        if (present.isNotBlank()) put(field, present)
                    }
                },
            )
        }
    }

    suspend fun refreshUsage() {
        val session = generation
        try {
            val json = api.request("GET", listOf("api", "usage-summary"))
            persist(
                session,
                "usage",
                Json.encodeToString(UsageSnapshot.fromJson(json, System.currentTimeMillis())),
            )
        } catch (failure: ApiFailure) {
            if (failure.status == 401) expire(session)
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
        val session = generation
        val result =
            authed(session) {
                api.request(
                    "POST",
                    listOf("api", "dashboard", "get-github-installations"),
                    buildJsonObject {},
                )
            }
        val repos =
            result.array("installations").flatMap { installation -> installation.array("repos") }
        val value = buildJsonObject { put("repos", JsonArray(repos)) }
        persist(session, "repositories", value.toString())
        return value
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

    private suspend fun postCached(key: String, path: List<String>): JsonObject {
        val session = generation
        val result =
            authed(session) { api.request("POST", path, buildJsonObject {}) }
        persist(session, key, result.toString())
        return result
    }

    private suspend fun authed(session: Long, block: suspend () -> JsonObject): JsonObject =
        try {
            block()
        } catch (failure: ApiFailure) {
            if (failure.status == 401) expire(session)
            throw failure
        }

    private suspend fun persist(session: Long, key: String, json: String) =
        lock.withLock {
            if (generation == session) cache.put(CacheEntry(key, json, System.currentTimeMillis()))
        }
}

internal fun normalizeComposer(id: String, root: JsonObject): JsonObject {
    val first = root.array("composers").firstOrNull()
    val composer = (first?.get("composer") as? JsonObject) ?: first ?: JsonObject(emptyMap())
    val bcId = composer.string("bcId").ifBlank { first?.string("bcId").orEmpty() }.ifBlank { id }
    val status = composer.string("status").ifBlank { first?.string("status").orEmpty() }
    val name = composer.string("name").ifBlank { first?.string("name").orEmpty() }
    return JsonObject(
        composer +
            mapOf(
                "bcId" to JsonPrimitive(bcId),
                "status" to JsonPrimitive(status),
                "name" to JsonPrimitive(name),
            )
    )
}

internal fun environmentJsonText(element: JsonElement?): String =
    when (element) {
        null -> ""
        is JsonPrimitive -> element.contentOrNull.orEmpty()
        else -> element.toString()
    }

private fun identityOf(me: JsonObject) = buildJsonObject {
    put("email", me.string("email"))
    put("name", me.string("name"))
    put("id", me.string("id"))
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
