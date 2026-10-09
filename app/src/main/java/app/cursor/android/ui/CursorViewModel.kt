package app.cursor.android.ui

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import app.cursor.android.data.CursorRepository
import app.cursor.android.data.Preferences
import app.cursor.android.data.UserPreferences
import app.cursor.android.data.array
import app.cursor.android.data.items
import app.cursor.android.data.string
import app.cursor.android.domain.UsageSnapshot
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.json.JsonObject

/** Owns user actions; composables only render immutable state and send intents. */
@HiltViewModel
class CursorViewModel
@Inject
constructor(private val repository: CursorRepository, val settings: UserPreferences) : ViewModel() {
    private val local = MutableStateFlow(LocalState(webConnected = repository.webConnected))
    val uiState: StateFlow<UiState> =
        combine(local, repository.agents, repository.usage, settings.preferences) {
                state,
                agents,
                usage,
                preferences ->
                UiState(state, agents, usage, preferences)
            }
            .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), UiState(local.value))
    private var streaming: Job? = null
    private val actions = Mutex()

    init {
        viewModelScope.launch {
            repository.connections.collect { connections ->
                local.update { it.copy(webConnected = connections.web) }
            }
        }
    }

    fun connectWeb(cookie: String, connected: () -> Unit = {}) = action {
        repository.connectWeb(cookie)
        local.update { it.copy(webConnected = true) }
        connected()
        repository.refreshUsage()
        repository.refreshAgents()
    }

    fun disconnect() = action {
        streaming?.cancel()
        repository.disconnect()
        local.value = LocalState()
    }

    fun refresh(more: Boolean = false) = action { repository.refreshAgents(more) }

    fun refreshUsage() = action { repository.refreshUsage() }

    fun clearError() {
        local.update { it.copy(error = null) }
    }

    fun catalog() = action {
        val models = repository.models()
        local.update { it.copy(models = models.array("models")) }
        val repos = repository.repositories()
        local.update { it.copy(repositories = repos.array("repos")) }
        val environments = repository.environments()
        local.update { it.copy(environments = environments.array("environments")) }
    }

    fun create(
        prompt: String,
        repositories: List<String>,
        model: String,
        environment: String,
        plan: Boolean,
        autoPr: Boolean,
        complete: (String) -> Unit,
    ) = action {
        val id = repository.create(prompt, repositories, model, environment, plan, autoPr)
        complete(id)
    }

    fun detail(id: String) = action {
        streaming?.cancel()
        local.update { it.copy(detail = null, runs = emptyList(), streamText = "") }
        val detail = repository.composer(id)
        local.update { it.copy(detail = detail, streamText = "") }
    }

    fun stopWatching() {
        streaming?.cancel()
    }

    private fun watch(agent: String, run: String) {
        streaming =
            viewModelScope.launch {
                try {
                    repository.stream(agent, run).collect { event ->
                        val status = event.string("status")
                        local.update { state ->
                            state.copy(
                                streamText = event.string("text"),
                                runs =
                                    state.runs.map { item ->
                                        if (item.string("id") == run && status.isNotBlank()) {
                                            JsonObject(
                                                item +
                                                    ("status" to
                                                        kotlinx.serialization.json.JsonPrimitive(
                                                            status
                                                        ))
                                            )
                                        } else item
                                    },
                            )
                        }
                    }
                    val current = repository.cachedResource(listOf("agents", agent, "runs"))
                    local.update { it.copy(runs = current.items()) }
                } catch (exception: Exception) {
                    if (exception is CancellationException) throw exception
                    local.update { it.copy(error = exception.message ?: "Stream unavailable") }
                }
            }
    }

    fun followUp(id: String, text: String) = action {
        repository.followUp(id, text)
        val runs = repository.cachedResource(listOf("agents", id, "runs"))
        local.update { it.copy(runs = runs.items(), streamText = "") }
        runs.items().firstOrNull()?.let { watch(id, it.string("id")) }
    }

    fun agentAction(id: String, action: String, run: String?, complete: () -> Unit) = action {
        repository.action(id, action, run)
        complete()
    }

    fun artifacts(id: String) = action {
        val response = repository.artifacts(id)
        local.update { it.copy(artifacts = response.array("artifacts")) }
    }

    fun artifactText(id: String, artifact: JsonObject, show: (String) -> Unit) = action {
        val response = repository.artifactBytes(id, artifact)
        show(decodeArtifact(response.string("content")))
    }

    fun webSettings(patch: JsonObject? = null) = action {
        if (patch != null) repository.api.webSettings(patch)
        val current = repository.api.webSettings()
        local.update { it.copy(webSettings = current) }
    }

    fun environment(id: String) = action {
        local.update { it.copy(environment = null, secrets = emptyList()) }
        val resource = repository.environment(id)
        val secrets = repository.secrets(id)
        local.update { it.copy(environment = resource, secrets = secrets.array("secrets")) }
    }

    fun saveEnvironment(id: String, body: JsonObject) = action {
        require(local.value.environment?.string("publicId") == id) {
            "Reload this environment before saving"
        }
        repository.api.request("PATCH", listOf("v1", "environments", id), body)
        val value = repository.cachedResource(listOf("environments", id))
        local.update { it.copy(environment = value) }
    }

    fun secret(id: String, name: String, body: JsonObject?, version: String? = null) = action {
        require(local.value.environment?.string("publicId") == id) {
            "Reload this environment before saving"
        }
        if (body != null) {
            require(local.value.secrets.none { it.string("name") == name }) {
                "A secret with this name exists. Use Cursor Web to rotate an existing secret."
            }
        }
        repository.api.request(
            if (body == null) "DELETE" else "PUT",
            listOf("v1", "environments", id, "secrets", name),
            body,
            if (version == null) emptyMap() else mapOf("id" to version),
        )
        val secrets = repository.secrets(id)
        local.update { it.copy(secrets = secrets.array("secrets")) }
    }

    fun boolean(name: String, value: Boolean) = action { settings.boolean(name, value) }

    fun interval(seconds: Int) = action { settings.interval(seconds) }

    fun language(language: String) = action { settings.language(language) }

    private fun action(block: suspend () -> Unit): Job =
        viewModelScope.launch {
            actions.withLock {
                local.update { it.copy(busy = true, error = null) }
                try {
                    block()
                } catch (exception: Exception) {
                    if (exception is CancellationException) throw exception
                    local.update { it.copy(error = exception.message ?: "Request failed") }
                } finally {
                    local.update {
                        it.copy(busy = false, webConnected = repository.webConnected)
                    }
                }
            }
        }
}

data class LocalState(
    val webConnected: Boolean = false,
    val busy: Boolean = false,
    val error: String? = null,
    val detail: JsonObject? = null,
    val runs: List<JsonObject> = emptyList(),
    val streamText: String = "",
    val artifacts: List<JsonObject> = emptyList(),
    val models: List<JsonObject> = emptyList(),
    val repositories: List<JsonObject> = emptyList(),
    val environments: List<JsonObject> = emptyList(),
    val environment: JsonObject? = null,
    val webSettings: JsonObject? = null,
    val secrets: List<JsonObject> = emptyList(),
)

internal fun decodeArtifact(content: String): String {
    if (content.isBlank()) return ""
    return runCatching {
            String(java.util.Base64.getDecoder().decode(content), Charsets.UTF_8)
        }
        .getOrDefault("")
}

data class UiState(
    val local: LocalState = LocalState(),
    val agents: JsonObject? = null,
    val usage: UsageSnapshot? = null,
    val preferences: Preferences = Preferences(),
)
