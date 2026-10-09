package app.cursor.android.data

import java.io.IOException
import java.util.concurrent.TimeUnit
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonObject
import okhttp3.Call
import okhttp3.Callback
import okhttp3.Cookie
import okhttp3.Headers
import okhttp3.HttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response
import okio.BufferedSource

class ApiFailure(val status: Int, val code: String, val retryAfter: String? = null) :
    IOException("HTTP $status · $code")

/**
 * Cookie is attached only to the session origin. Production origin is https://cursor.com.
 * Tests may opt into their configured origin; redirects are never followed.
 */
class CursorApi(
    private val cookie: () -> String?,
    private val webBase: HttpUrl = "https://cursor.com/".toHttpUrl(),
    private val allowConfiguredOrigin: Boolean = false,
    private val client: OkHttpClient =
        OkHttpClient.Builder()
            .connectTimeout(20, TimeUnit.SECONDS)
            .readTimeout(90, TimeUnit.SECONDS)
            .followRedirects(false)
            .followSslRedirects(false)
            .retryOnConnectionFailure(false)
            .build(),
) {
    @Volatile private var csrfToken: String? = null

    fun resetWebSession() {
        csrfToken = null
    }

    suspend fun webSettings(patch: JsonObject? = null): JsonObject {
        val operation = if (patch == null) "get" else "update"
        val path =
            listOf("api", "background-composer", "$operation-background-composer-user-settings")
        return request("POST", path, patch)
    }

    suspend fun request(
        method: String,
        segments: List<String>,
        body: JsonObject? = null,
        query: Map<String, String> = emptyMap(),
        cookieOverride: String? = null,
    ): JsonObject {
        try {
            return execute(method, segments, body, query, cookieOverride)
        } catch (failure: ApiFailure) {
            if (failure.code != "invalid_csrf_token" || method == "GET") throw failure
            refreshCsrf(cookieOverride)
            return execute(method, segments, body, query, cookieOverride)
        }
    }

    suspend fun conversation(
        bcId: String,
        offsetKey: String?,
        onUpdate: suspend (ConversationUpdate) -> Unit,
    ) {
        try {
            openConversation(bcId, offsetKey, onUpdate)
        } catch (failure: ApiFailure) {
            if (failure.code != "invalid_csrf_token") throw failure
            refreshCsrf(null)
            openConversation(bcId, offsetKey, onUpdate)
        }
    }

    private suspend fun openConversation(
        bcId: String,
        offsetKey: String?,
        onUpdate: suspend (ConversationUpdate) -> Unit,
    ) =
        withContext(Dispatchers.IO) {
            val call = client.newCall(conversationRequest(bcId, offsetKey))
            val cancellation =
                CoroutineScope(kotlinx.coroutines.currentCoroutineContext()).launch(
                    Dispatchers.Unconfined
                ) {
                    try {
                        awaitCancellation()
                    } finally {
                        call.cancel()
                    }
                }
            try {
                call.await().use { response ->
                    if (!response.isSuccessful)
                        throw failure(response, response.body?.string().orEmpty())
                    val source = response.body?.source() ?: throw IOException("Empty stream")
                    readConversation(source, onUpdate)
                }
            } catch (failure: IOException) {
                kotlinx.coroutines.currentCoroutineContext().ensureActive()
                throw failure
            } finally {
                cancellation.cancel()
                call.cancel()
            }
        }

    private suspend fun readConversation(
        source: BufferedSource,
        onUpdate: suspend (ConversationUpdate) -> Unit,
    ) {
        while (!source.exhausted()) {
            val frame = readFrame(source) ?: break
            if (frame.end) {
                val code = endErrorCode(frame.payload)
                if (code != null) throw ApiFailure(400, code)
                onUpdate(ConversationUpdate(null, "", end = true))
                break
            }
            if (frame.flags and 0x01 != 0) throw IOException("Compressed frame")
            onUpdate(decodeConversationPayload(frame.payload))
        }
    }

    private fun conversationRequest(bcId: String, offsetKey: String?): Request {
        val url =
            webBase
                .newBuilder()
                .addPathSegments("api/connect-proxy/aiserver.v1.BackgroundComposerService")
                .addPathSegment("StreamConversation")
                .build()
        if (!cookieAllowed(url, webBase, allowConfiguredOrigin)) {
            throw ApiFailure(0, "origin_rejected")
        }
        val credential = cookie()
        if (credential.isNullOrBlank()) throw ApiFailure(401, "connection_required")
        val payload = encodeConversationRequest(bcId, offsetKey)
        return Request.Builder()
            .url(url)
            .post(payload.toRequestBody("application/connect+proto".toMediaType()))
            .headers(sessionHeaders(url, credential, csrfToken, "POST"))
            .header("Content-Type", "application/connect+proto")
            .header("Connect-Protocol-Version", "1")
            .header("Accept", "application/connect+proto")
            .build()
    }

    private suspend fun execute(
        method: String,
        segments: List<String>,
        body: JsonObject?,
        query: Map<String, String>,
        cookieOverride: String?,
    ): JsonObject {
        val call = client.newCall(build(method, segments, body, query, cookieOverride))
        return call.await().use { response ->
            val text = withContext(Dispatchers.IO) { response.body?.string().orEmpty() }
            if (!response.isSuccessful) throw failure(response, text)
            jsonObjectOrFailure(response.code, text)
        }
    }

    private suspend fun refreshCsrf(cookieOverride: String?) {
        val call =
            client.newCall(
                build("GET", listOf("api", "csrf-token"), cookieOverride = cookieOverride)
            )
        call.await().use { response ->
            if (!response.isSuccessful) throw failure(response, response.body?.string().orEmpty())
            if (!sameOrigin(response.request.url)) {
                throw ApiFailure(response.code, "invalid_csrf_token")
            }
            csrfToken =
                Cookie.parseAll(response.request.url, response.headers)
                    .firstOrNull { it.name in listOf("csrf-token", "cursor-csrf-token") }
                    ?.value ?: throw ApiFailure(response.code, "invalid_csrf_token")
        }
    }

    internal fun build(
        method: String,
        segments: List<String>,
        body: JsonObject? = null,
        query: Map<String, String> = emptyMap(),
        cookieOverride: String? = null,
    ): Request {
        val url =
            webBase
                .newBuilder()
                .apply {
                    segments.forEach { addPathSegment(it) }
                    query.forEach { (name, value) -> addQueryParameter(name, value) }
                }
                .build()
        if (!cookieAllowed(url, webBase, allowConfiguredOrigin)) {
            throw ApiFailure(0, "origin_rejected")
        }
        val credential = cookieOverride ?: cookie()
        if (credential.isNullOrBlank()) throw ApiFailure(401, "connection_required")
        val requestBody =
            if (method in listOf("POST", "PUT", "PATCH", "DELETE")) {
                (body?.toString() ?: "{}").toRequestBody("application/json".toMediaType())
            } else null
        return Request.Builder()
            .url(url)
            .method(method, requestBody)
            .header("Accept", "application/json")
            .headers(sessionHeaders(url, credential, csrfToken, method))
            .build()
    }

    private fun sameOrigin(url: HttpUrl): Boolean =
        cookieAllowed(url, webBase, allowConfiguredOrigin)

    private fun jsonObjectOrFailure(status: Int, text: String): JsonObject {
        if (text.isBlank()) return JsonObject(emptyMap())
        val element = runCatching { Json.parseToJsonElement(text) }.getOrNull()
        if (element is JsonObject) return element
        throw ApiFailure(status, "invalid_body")
    }

    private fun failure(response: Response, body: String): ApiFailure {
        val error =
            runCatching { Json.parseToJsonElement(body).jsonObject["error"]?.jsonObject }
                .getOrNull()
        val code = (error?.get("code") as? JsonPrimitive)?.contentOrNull ?: "request_failed"
        return ApiFailure(response.code, code, response.header("Retry-After"))
    }
}

/** Cookie and CSRF headers for one origin. Never an Authorization header. */
internal fun sessionHeaders(
    url: HttpUrl,
    credential: String,
    csrfToken: String?,
    method: String,
): Headers {
    val token =
        csrfToken
            ?: credential
                .split(';')
                .map(String::trim)
                .firstOrNull { it.startsWith("csrf-token=") }
                ?.substringAfter('=')
    val cookies =
        if (csrfToken == null) credential
        else
            credential.split(';').filterNot { it.trim().startsWith("csrf-token=") }.joinToString(
                ";"
            ) + "; csrf-token=$csrfToken"
    val builder =
        Headers.Builder()
            .add("Accept", "application/json")
            .add("Cookie", cookies)
            .add("Origin", originOf(url))
    val team = teamId(credential)
    if (team != null) builder.add("x-cursor-team-id", team)
    if (token != null && method != "GET") builder.add("x-csrf-token", token)
    return builder.build()
}

internal fun cookieAllowed(
    url: HttpUrl,
    origin: HttpUrl,
    allowConfiguredOrigin: Boolean,
): Boolean {
    if (url.scheme == "https" && url.host == "cursor.com" && url.port == 443) return true
    return allowConfiguredOrigin &&
        url.scheme == origin.scheme &&
        url.host == origin.host &&
        url.port == origin.port
}

internal fun teamId(cookie: String): String? =
    cookie
        .split(';')
        .map(String::trim)
        .firstOrNull { it.startsWith("portal-selected-team-id=") }
        ?.substringAfter('=')
        ?.takeIf { it.isNotBlank() }

private fun originOf(url: HttpUrl): String = url.scheme + "://" + url.host

private suspend fun Call.await(): Response = suspendCancellableCoroutine { continuation ->
    continuation.invokeOnCancellation { cancel() }
    enqueue(
        object : Callback {
            override fun onFailure(call: Call, e: IOException) {
                if (!continuation.isCancelled) continuation.resumeWithException(e)
            }

            override fun onResponse(call: Call, response: Response) {
                continuation.resume(response) { _, value, _ -> value.close() }
            }
        }
    )
}

private fun readFrame(source: BufferedSource): ConnectFrame? {
    if (source.exhausted()) return null
    if (!source.request(5)) {
        if (source.exhausted()) return null
        throw IOException("Truncated frame")
    }
    val flags = source.readByte().toInt() and 0xFF
    val length = source.readInt()
    if (length < 0 || length > 8_000_000) throw IOException("Frame length")
    if (!source.request(length.toLong())) throw IOException("Truncated frame")
    return ConnectFrame(flags, source.readByteArray(length.toLong()))
}

private fun endErrorCode(payload: ByteArray): String? {
    val text = payload.toString(Charsets.UTF_8)
    if (text.isBlank()) return null
    val error =
        runCatching { Json.parseToJsonElement(text).jsonObject["error"]?.jsonObject }.getOrNull()
            ?: return null
    return (error["code"] as? JsonPrimitive)?.contentOrNull
}
