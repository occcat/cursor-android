@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)

package app.cursor.android.ui

import android.Manifest
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.webkit.CookieManager
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatDelegate
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.AssistChip
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Checkbox
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.os.LocaleListCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.repeatOnLifecycle
import androidx.navigation3.runtime.NavKey
import androidx.navigation3.runtime.entryProvider
import androidx.navigation3.runtime.rememberNavBackStack
import androidx.navigation3.ui.NavDisplay
import app.cursor.android.data.Preferences
import app.cursor.android.data.items
import app.cursor.android.data.string
import app.cursor.android.domain.UsageSnapshot
import app.cursor.android.system.UsageNotifications
import app.cursor.android.system.UsageOverlayService
import java.text.DateFormat
import java.util.Date
import kotlinx.coroutines.delay
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

private val frost = Color(0xFF81A1C1)

@Serializable
private data class Destination(val screen: String, val id: String = "") : NavKey

@Composable
fun label(english: String, chinese: String): String =
    if (LocalConfiguration.current.locales[0].language == "zh") chinese else english

@Composable
fun CursorApp(state: UiState, model: CursorViewModel) {
    val dark = isSystemInDarkTheme()
    val colors = if (dark) darkColorScheme(
        primary = frost, background = Color(0xFF181818), surface = Color(0xFF181818),
        surfaceContainer = Color(0xFF242424), onSurface = Color(0xFFF0F0F0),
    ) else lightColorScheme(
        primary = Color(0xFF476580), background = Color(0xFFFCFCFC),
        surface = Color(0xFFFCFCFC), surfaceContainer = Color(0xFFF0F0EC),
        onSurface = Color(0xFF141414),
    )
    val backStack = rememberNavBackStack(Destination("inbox"))
    val context = LocalContext.current
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    var usageOpen by rememberSaveable { mutableStateOf(false) }
    LaunchedEffect(state.preferences.language) {
        AppCompatDelegate.setApplicationLocales(
            LocaleListCompat.forLanguageTags(state.preferences.language),
        )
    }
    LaunchedEffect(state.local.connected) {
        if (state.local.connected) model.refresh()
    }
    LaunchedEffect(state.local.webConnected, state.preferences.paused,
        state.preferences.intervalSeconds, lifecycle) {
        lifecycle.repeatOnLifecycle(Lifecycle.State.STARTED) {
            if (state.local.webConnected && !state.preferences.paused) {
                while (true) {
                    model.refreshUsage()
                    delay(state.preferences.intervalSeconds * 1000L)
                }
            }
        }
    }
    LaunchedEffect(state.usage, state.preferences) {
        UsageNotifications.update(context, state.usage, state.preferences)
    }
    MaterialTheme(colorScheme = colors) {
        Scaffold(topBar = {
            TopAppBar(title = { Text("Cursor Android", fontSize = 19.sp) },
                navigationIcon = {
                    if (backStack.size > 1) TextButton(onClick = { backStack.removeLastOrNull() }) {
                        Text(label("Back", "返回"))
                    }
                }, actions = {
                    TextButton(onClick = { usageOpen = true }) { Text(label("Usage", "用量")) }
                    TextButton(onClick = { backStack.add(Destination("settings")) }) {
                        Text(label("Settings", "设置"))
                    }
                })
        }) { padding ->
            Column(Modifier.fillMaxSize().padding(padding)) {
                if (state.local.busy) LinearProgressIndicator(Modifier.fillMaxWidth())
                if (state.local.error != null) {
                    Surface(color = MaterialTheme.colorScheme.errorContainer) {
                        Row(Modifier.fillMaxWidth().padding(12.dp),
                            verticalAlignment = Alignment.CenterVertically) {
                            Text(state.local.error, Modifier.weight(1f), fontSize = 13.sp)
                            TextButton(onClick = model::clearError) { Text(label("Dismiss", "关闭")) }
                        }
                    }
                }
                NavDisplay(backStack = backStack,
                    onBack = { backStack.removeLastOrNull() },
                    entryProvider = entryProvider {
                        entry<Destination> { route ->
                            when (route.screen) {
                                "inbox" -> Inbox(state, model,
                                    { backStack.add(Destination("create")) },
                                    { backStack.add(Destination("detail", it)) },
                                    { backStack.add(Destination("settings")) },
                                    { usageOpen = true })
                                "create" -> CreateAgent(state, model) {
                                    backStack.removeLastOrNull()
                                    backStack.add(Destination("detail", it))
                                }
                                "detail" -> AgentDetail(route.id, state, model) {
                                    backStack.removeLastOrNull()
                                }
                                "settings" -> SettingsScreen(state, model,
                                    { backStack.add(Destination("signin")) },
                                    { backStack.add(Destination("environment", it)) })
                                "signin" -> WebSignIn(model) { backStack.removeLastOrNull() }
                                "environment" -> EnvironmentScreen(route.id, state, model)
                            }
                        }
                    })
            }
        }
        if (usageOpen) ModalBottomSheet(onDismissRequest = { usageOpen = false }) {
            UsagePanel(state.usage, state.preferences, state.local.webConnected,
                model::refreshUsage)
        }
    }
}

@Composable
private fun Inbox(
    state: UiState,
    model: CursorViewModel,
    create: () -> Unit,
    detail: (String) -> Unit,
    settings: () -> Unit,
    usage: () -> Unit,
) {
    var query by rememberSaveable { mutableStateOf("") }
    var archived by rememberSaveable { mutableStateOf(false) }
    LazyColumn(contentPadding = PaddingValues(20.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)) {
        item {
            Text(label("Your work.\nWithin reach.", "你的工作，\n随时掌握。"),
                style = MaterialTheme.typography.headlineLarge, fontWeight = FontWeight.Medium)
            Spacer(Modifier.height(12.dp))
            Text(label("Cloud agents, wherever you are.", "随时随地，连接云端 Agent。"),
                color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        item { UsageCapsule(state.usage, state.preferences, usage) }
        if (!state.local.connected) {
            item {
                Card {
                    Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        Text(label("Connect your workspace", "连接你的工作区"),
                            style = MaterialTheme.typography.titleLarge)
                        Text(label("Use a Cursor API key to manage agents. Connect a web session " +
                            "separately to view account usage.",
                            "使用 Cursor API Key 管理 Agent，另行连接网页会话以查看账户用量。"))
                        Button(onClick = settings) { Text(label("Get started", "开始使用")) }
                    }
                }
            }
            item { FeatureLinks() }
        } else {
            item {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Button(onClick = create, enabled = !state.local.busy) {
                        Text(label("+ New agent", "+ 新建 Agent"))
                    }
                    OutlinedButton(onClick = { model.refresh() }) { Text(label("Refresh", "刷新")) }
                }
            }
            item {
                OutlinedTextField(query, { query = it }, Modifier.fillMaxWidth(),
                    label = { Text(label("Search agents", "搜索 Agent")) }, singleLine = true)
                FilterChip(archived, { archived = !archived },
                    label = { Text(label("Include archived", "包含归档")) })
            }
            val agents = state.agents?.items().orEmpty().filter {
                (archived || it.string("status") != "ARCHIVED") &&
                    it.string("name").contains(query, ignoreCase = true)
            }
            if (agents.isEmpty()) item {
                Text(label("No agents here yet. Start with a task.", "暂无 Agent，创建一个任务开始。"))
            }
            items(agents, key = { it.string("id") }) { agent ->
                Card(onClick = { detail(agent.string("id")) }, Modifier.fillMaxWidth()) {
                    Column(Modifier.padding(18.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Text(agent.string("name").ifBlank { label("Untitled agent", "未命名 Agent") },
                            style = MaterialTheme.typography.titleMedium)
                        Text(agent.string("status"), color = frost, fontSize = 12.sp,
                            fontFamily = FontFamily.Monospace)
                        Text(agent.string("updatedAt"), fontSize = 12.sp,
                            color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
            if (!state.agents?.string("nextCursor").isNullOrBlank()) item {
                OutlinedButton(onClick = { model.refresh(true) }) { Text(label("Load more", "加载更多")) }
            }
            item { FeatureLinks() }
        }
        item {
            Text(label("Independent, open-source client. Not affiliated with Cursor.",
                "独立开源客户端，与 Cursor 官方无关联。"), fontSize = 12.sp,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@Composable
private fun FeatureLinks() {
    val context = LocalContext.current
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(label("Continue on Cursor Web", "在 Cursor 网页中继续"),
            style = MaterialTheme.typography.titleMedium)
        Text(label("Automations, Codebase, Desktop, Terminal and Files open in your browser.",
            "自动化、Codebase、桌面、终端及文件功能将在浏览器中打开。"), fontSize = 13.sp)
        OutlinedButton(onClick = { openHttps(context, "https://cursor.com/agents") }) {
            Text(label("Open Cursor Web ↗", "打开 Cursor 网页 ↗"))
        }
    }
}

@Composable
fun UsageCapsule(usage: UsageSnapshot?, preferences: Preferences, click: () -> Unit) {
    if (!preferences.cursor && !preferences.other) return
    val remaining = label("remaining", "剩余")
    val used = label("used", "已用")
    val mode = if (preferences.remaining) remaining else used
    Surface(onClick = click, shape = RoundedCornerShape(24.dp),
        color = MaterialTheme.colorScheme.surfaceContainer) {
        FlowRow(Modifier.padding(horizontal = 16.dp, vertical = 12.dp),
            horizontalArrangement = Arrangement.spacedBy(14.dp)) {
            if (preferences.cursor) Text("● Cursor ${usageValue(usage, true, preferences.remaining)}",
                color = MaterialTheme.colorScheme.onSurface,
                modifier = Modifier.semantics { contentDescription =
                    "Cursor Model ${usageValue(usage, true, preferences.remaining)} $mode" })
            if (preferences.other) Text("○ Other ${usageValue(usage, false, preferences.remaining)}",
                modifier = Modifier.semantics { contentDescription =
                    "Other Model ${usageValue(usage, false, preferences.remaining)} $mode" })
            Text(mode, fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

fun usageValue(snapshot: UsageSnapshot?, cursor: Boolean, remaining: Boolean): String =
    if (snapshot?.unlimited == true) "∞" else snapshot?.value(cursor, remaining)
        ?.let { "${it.toInt()}%" } ?: "—"

@Composable
private fun UsagePanel(
    usage: UsageSnapshot?,
    preferences: Preferences,
    connected: Boolean,
    refresh: () -> Unit,
) {
    Column(Modifier.padding(24.dp).verticalScroll(rememberScrollState()),
        verticalArrangement = Arrangement.spacedBy(20.dp)) {
        Text("Cursor Usage", style = MaterialTheme.typography.headlineSmall)
        Text(if (connected) label("Account quota · last successful snapshot", "账户额度 · 最近成功快照")
            else label("Connect a web session in Settings to view usage.", "在设置中连接网页会话以查看用量。"))
        val now = System.currentTimeMillis()
        listOf(true, false).forEach { cursor ->
            if (if (cursor) preferences.cursor else preferences.other) {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                        Text(if (cursor) "Cursor Model" else "Other Model")
                        Text(usageValue(usage, cursor, preferences.remaining),
                            style = MaterialTheme.typography.headlineSmall,
                            fontFamily = FontFamily.Monospace)
                    }
                    Text(if (preferences.remaining) label("Remaining", "剩余额度")
                        else label("Used", "已用额度"), fontSize = 12.sp)
                    val value = usage?.value(cursor, preferences.remaining)
                    if (value != null && !usage.unlimited) {
                        LinearProgressIndicator(progress = { (value / 100).toFloat() },
                            modifier = Modifier.fillMaxWidth().height(8.dp),
                            color = if (cursor) frost else MaterialTheme.colorScheme.onSurfaceVariant)
                        val pace = if (preferences.pace) usage.pace(now) else null
                        if (pace != null) {
                            val raw = if (cursor) usage.cursorUsed else usage.otherUsed
                            val text = when (pace.category(raw ?: 0.0)) {
                                1 -> label("Faster than billing pace", "使用快于账单周期节奏")
                                -1 -> label("Slower than billing pace", "使用慢于账单周期节奏")
                                else -> label("On pace", "节奏正常")
                            }
                            Text(text + if (pace.estimated) label(" · estimated cycle", " · 估算周期")
                                else "", fontSize = 12.sp)
                        }
                    }
                }
            }
        }
        if (usage != null) {
            HorizontalDivider()
            Text(label("Updated ", "更新于 ") + time(usage.fetchedAt), fontSize = 12.sp)
            if (!usage.unlimited && usage.cycleEnd != null) {
                Text(label("Resets ", "重置时间 ") + time(usage.cycleEnd), fontSize = 12.sp)
            }
            if (usage.pendingReset(now)) Text(label("Awaiting new billing cycle data", "等待新账单周期数据"))
        }
        if (preferences.paused) Text(label("Automatic refresh paused", "自动刷新已暂停"))
        Button(onClick = refresh, enabled = connected) { Text(label("Refresh usage", "刷新用量")) }
        Text(label("Background updates are scheduled by Android, at least 15 minutes apart.",
            "后台更新由 Android 调度，间隔至少 15 分钟。"), fontSize = 12.sp)
        Spacer(Modifier.height(20.dp))
    }
}

private fun time(value: Long): String = DateFormat.getDateTimeInstance(
    DateFormat.MEDIUM, DateFormat.SHORT,
).format(Date(value))

fun openHttps(context: android.content.Context, url: String) {
    val uri = Uri.parse(url)
    if (uri.scheme != "https" || uri.host.isNullOrBlank()) return
    runCatching { context.startActivity(Intent(Intent.ACTION_VIEW, uri)) }
}

@Composable
private fun CreateAgent(state: UiState, model: CursorViewModel, complete: (String) -> Unit) {
    var prompt by rememberSaveable { mutableStateOf("") }
    var repository by rememberSaveable { mutableStateOf("") }
    var selectedModel by rememberSaveable { mutableStateOf("") }
    var environment by rememberSaveable { mutableStateOf("") }
    var plan by rememberSaveable { mutableStateOf(false) }
    var autoPr by rememberSaveable { mutableStateOf(false) }
    LaunchedEffect(Unit) { model.catalog() }
    Column(Modifier.padding(20.dp).verticalScroll(rememberScrollState()),
        verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Text(label("What should we build?", "我们要实现什么？"),
            style = MaterialTheme.typography.headlineMedium)
        Text(label("Start a cloud agent with your own Cursor account.", "使用你的 Cursor 账户启动云端 Agent。"))
        OutlinedTextField(prompt, { prompt = it }, Modifier.fillMaxWidth(), minLines = 5,
            label = { Text(label("Describe a task", "描述任务")) })
        Text(label("Workspace", "工作区"), style = MaterialTheme.typography.titleMedium)
        OutlinedTextField(repository, { repository = it }, Modifier.fillMaxWidth(),
            enabled = environment.isBlank(), label = { Text(label("Repository URLs · one per line",
                "仓库 URL · 每行一个")) }, supportingText = {
                Text(label("Leave empty to start without a repository.", "留空以创建无仓库任务。"))
            })
        FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            state.local.repositories.take(10).forEach { repo ->
                AssistChip(onClick = { repository = repo.string("url"); environment = "" },
                    label = { Text(repo.string("url").substringAfterLast('/')) })
            }
        }
        FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            FilterChip(environment.isBlank(), { environment = "" },
                label = { Text(label("Default environment", "默认环境")) })
            state.local.environments.forEach { env ->
                FilterChip(environment == env.string("name"),
                    { environment = env.string("name"); repository = "" },
                    label = { Text(env.string("name")) })
            }
        }
        Text(label("Model", "模型"), style = MaterialTheme.typography.titleMedium)
        FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            FilterChip(selectedModel.isBlank(), { selectedModel = "" },
                label = { Text(label("Account default", "账户默认")) })
            state.local.models.forEach { item ->
                FilterChip(selectedModel == item.string("id"), { selectedModel = item.string("id") },
                    label = { Text(item.string("displayName").ifBlank { item.string("id") }) })
            }
        }
        Toggle(label("Plan before implementing", "先制定计划"), plan) { plan = it }
        Toggle(label("Create a pull request automatically", "自动创建 Pull Request"), autoPr) {
            autoPr = it
        }
        Button(onClick = {
            model.create(prompt, repository.lines().map(String::trim).filter(String::isNotEmpty),
                selectedModel, environment, plan, autoPr, complete)
        }, enabled = prompt.isNotBlank() && !state.local.busy, modifier = Modifier.fillMaxWidth()) {
            Text(label("Start agent →", "启动 Agent →"))
        }
        Text(label("Runs may consume your Cursor allowance. Sending is never retried automatically.",
            "运行可能消耗 Cursor 额度，发送操作不会自动重试。"), fontSize = 12.sp)
        Spacer(Modifier.height(20.dp))
    }
}

@Composable
private fun AgentDetail(id: String, state: UiState, model: CursorViewModel, back: () -> Unit) {
    val context = LocalContext.current
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    var followUp by rememberSaveable(id) { mutableStateOf("") }
    var confirm by remember { mutableStateOf<String?>(null) }
    var showArtifacts by rememberSaveable { mutableStateOf(false) }
    LaunchedEffect(id, lifecycle) {
        lifecycle.repeatOnLifecycle(Lifecycle.State.STARTED) { model.detail(id).join() }
    }
    DisposableEffect(id) { onDispose { model.stopWatching() } }
    val agent = state.local.detail
    LazyColumn(contentPadding = PaddingValues(20.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)) {
        item {
            Text(agent?.string("name").orEmpty().ifBlank { label("Agent", "Agent") },
                style = MaterialTheme.typography.headlineMedium)
            Text(agent?.string("status").orEmpty(), color = frost)
        }
        item {
            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                AssistChip(onClick = { model.detail(id) }, label = { Text(label("Refresh", "刷新")) })
                AssistChip(onClick = { openHttps(context, "https://cursor.com/agents/$id") },
                    label = { Text(label("Workspace ↗", "工作区 ↗")) })
                AssistChip(onClick = { showArtifacts = !showArtifacts; model.artifacts(id) },
                    label = { Text(label("Artifacts", "产物")) })
                AssistChip(onClick = { confirm = if (agent?.string("status") == "ARCHIVED")
                    "unarchive" else "archive" }, label = {
                    Text(if (agent?.string("status") == "ARCHIVED") label("Restore", "恢复")
                        else label("Archive", "归档"))
                })
            }
        }
        if (showArtifacts) {
            items(state.local.artifacts) { artifact ->
                OutlinedButton(onClick = {
                    model.artifactUrl(id, artifact.string("path")) { openHttps(context, it) }
                }) { Text(artifact.string("path")) }
            }
            if (state.local.artifacts.isEmpty()) item {
                Text(label("No artifacts returned.", "暂无产物。"))
            }
        }
        if (state.local.streamText.isNotBlank()) item {
            Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainer)) {
                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(label("Live output", "实时输出"), color = frost, fontSize = 12.sp)
                    SelectionContainer { Text(state.local.streamText) }
                }
            }
        }
        items(state.local.runs, key = { it.string("id") }) { run ->
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(run.string("status") + " · " + run.string("createdAt"), fontSize = 12.sp,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
                if (run.string("result").isNotBlank()) SelectionContainer { Text(run.string("result")) }
                if (run.string("status") in listOf("CREATING", "RUNNING")) {
                    OutlinedButton(onClick = { confirm = "cancel" }) {
                        Text(label("Cancel active run", "取消运行"))
                    }
                }
                HorizontalDivider()
            }
        }
        item {
            Text(label("Historical prompts are not provided by the public v1 API.",
                "公开 v1 API 不提供历史用户提示词。"), fontSize = 12.sp)
            OutlinedTextField(followUp, { followUp = it }, Modifier.fillMaxWidth(), minLines = 3,
                label = { Text(label("Follow up", "继续追问")) })
            Button(onClick = { model.followUp(id, followUp); followUp = "" },
                enabled = followUp.isNotBlank() && !state.local.busy &&
                    state.local.runs.none { it.string("status") in listOf("CREATING", "RUNNING") }) {
                Text(label("Send follow-up", "发送追问"))
            }
        }
        item { FeatureLinks() }
        item {
            TextButton(onClick = { confirm = "delete" }) {
                Text(label("Delete agent permanently", "永久删除 Agent"),
                    color = MaterialTheme.colorScheme.error)
            }
        }
    }
    if (confirm != null) AlertDialog(onDismissRequest = { confirm = null },
        title = { Text(label("Confirm agent action", "确认操作")) },
        text = { Text(when (confirm) {
            "delete" -> label("Permanently delete this agent and its workspace?", "永久删除 Agent 及其工作区？")
            "cancel" -> label("Cancel the active run?", "取消当前运行？")
            "archive" -> label("Archive this agent?", "归档此 Agent？")
            else -> label("Restore this agent?", "恢复此 Agent？")
        }) }, confirmButton = {
            TextButton(onClick = {
                val action = confirm ?: return@TextButton
                confirm = null
                model.agentAction(id, action, state.local.runs.firstOrNull()?.string("id")) {
                    if (action == "delete") back()
                }
            }) { Text(label("Confirm", "确认")) }
        }, dismissButton = { TextButton(onClick = { confirm = null }) { Text(label("Keep", "保留")) } })
}

@Composable
private fun SettingsScreen(
    state: UiState,
    model: CursorViewModel,
    signIn: () -> Unit,
    environment: (String) -> Unit,
) {
    val context = LocalContext.current
    var key by remember { mutableStateOf("") }
    var signOut by remember { mutableStateOf(false) }
    val permission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) {
        model.boolean("notifications", it)
    }
    Column(Modifier.padding(20.dp).verticalScroll(rememberScrollState()),
        verticalArrangement = Arrangement.spacedBy(16.dp)) {
        Text(label("Make it yours.", "按你的方式使用。"), style = MaterialTheme.typography.headlineMedium)
        Section(label("CONNECTIONS", "连接"))
        Text(label("Cloud Agents API", "Cloud Agents API"), style = MaterialTheme.typography.titleMedium)
        Text(if (state.local.connected) label("API key connected", "已连接 API Key")
            else label("Create a key in Cursor Dashboard. It stays encrypted on this device.",
                "在 Cursor Dashboard 创建 Key，它将加密保存在本设备。"), fontSize = 13.sp)
        if (!state.local.connected) {
            OutlinedTextField(key, { key = it }, Modifier.fillMaxWidth(), singleLine = true,
                visualTransformation = PasswordVisualTransformation(), label = { Text("API key") })
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Button(onClick = { model.connect(key); key = "" }, enabled = key.isNotBlank()) {
                    Text(label("Connect API", "连接 API"))
                }
                TextButton(onClick = { openHttps(context, "https://cursor.com/dashboard?tab=integrations") }) {
                    Text(label("Get a key ↗", "获取 Key ↗"))
                }
            }
        }
        Text(label("Account usage", "账户用量"), style = MaterialTheme.typography.titleMedium)
        Text(label("Usage uses a separate Cursor web session, not your API key. " +
            "Connect the same account yourself; identities are not assumed to match.",
            "用量使用独立的 Cursor 网页会话，不使用 API Key。请自行连接同一账户，客户端不会假定身份一致。"),
            fontSize = 13.sp)
        OutlinedButton(onClick = signIn) {
            Text(if (state.local.webConnected) label("Reconnect web session", "重新连接网页会话")
                else label("Connect web session", "连接网页会话"))
        }
        if (state.local.connected || state.local.webConnected) {
            TextButton(onClick = { signOut = true }) { Text(label("Disconnect & clear local data", "断开并清除本地数据")) }
        }
        if (state.local.webConnected) WebSettings(state, model)
        Section(label("CURSOR USAGE", "CURSOR 用量"))
        Toggle("Cursor Model", state.preferences.cursor) { model.boolean("cursor", it) }
        Toggle("Other Model", state.preferences.other) { model.boolean("other", it) }
        Toggle(label("Show remaining allowance", "显示剩余额度"), state.preferences.remaining) {
            model.boolean("remaining", it)
        }
        Toggle(label("Billing pace", "账单周期节奏"), state.preferences.pace) { model.boolean("pace", it) }
        Toggle(label("Pause automatic refresh", "暂停自动刷新"), state.preferences.paused) {
            model.boolean("paused", it)
        }
        Text(label("Foreground refresh", "前台刷新间隔"))
        FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            listOf(30, 60, 120, 300).forEach { seconds ->
                FilterChip(state.preferences.intervalSeconds == seconds, { model.interval(seconds) },
                    label = { Text("${seconds}s") })
            }
        }
        Section(label("SYSTEM SURFACES", "系统展示"))
        Toggle(label("Usage notification", "用量通知"), state.preferences.notifications) {
            if (it && Build.VERSION.SDK_INT >= 33) permission.launch(Manifest.permission.POST_NOTIFICATIONS)
            else model.boolean("notifications", it)
        }
        Text(label("The status bar shows a monochrome icon. Values appear in the notification drawer; " +
            "lock-screen details stay private.", "状态栏显示单色图标，具体数值在通知抽屉中展示，锁屏默认隐藏。"),
            fontSize = 13.sp)
        OutlinedButton(onClick = {
            if (!Settings.canDrawOverlays(context)) {
                context.startActivity(Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                    Uri.parse("package:${context.packageName}")))
            } else {
                androidx.core.content.ContextCompat.startForegroundService(context,
                    Intent(context, UsageOverlayService::class.java))
            }
        }, enabled = state.local.webConnected && (state.preferences.cursor || state.preferences.other)) {
            Text(label("Start floating capsule", "启动悬浮胶囊"))
        }
        TextButton(onClick = { context.stopService(Intent(context, UsageOverlayService::class.java)) }) {
            Text(label("Stop floating capsule", "停止悬浮胶囊"))
        }
        Text(label("Drag to position. Tap to open the app. The capsule displays cached snapshots; " +
            "Android schedules background refresh. Starting requires overlay permission.",
            "拖动可调整位置，点击打开应用。胶囊显示缓存快照，后台刷新由 Android 调度，需要悬浮权限。"), fontSize = 13.sp)
        Section(label("LANGUAGE", "语言"))
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            FilterChip(state.preferences.language == "en", { model.language("en") }, label = { Text("English") })
            FilterChip(state.preferences.language == "zh-CN", { model.language("zh-CN") }, label = { Text("简体中文") })
        }
        if (state.local.connected) {
            Section(label("CLOUD ENVIRONMENTS", "云端环境"))
            OutlinedButton(onClick = model::catalog) { Text(label("Load environments", "加载环境")) }
            state.local.environments.forEach { item ->
                TextButton(onClick = { environment(item.string("id")) }) { Text(item.string("name")) }
            }
        }
        FeatureLinks()
        Spacer(Modifier.height(24.dp))
    }
    if (signOut) AlertDialog(onDismissRequest = { signOut = false },
        title = { Text(label("Disconnect this device?", "断开此设备连接？")) },
        text = { Text(label("Credentials, cached agents, live output and usage will be cleared.",
            "将清除凭据、缓存 Agent、实时输出及用量。")) },
        confirmButton = {
            TextButton(onClick = {
                model.disconnect()
                CookieManager.getInstance().removeAllCookies(null)
                CookieManager.getInstance().flush()
                android.webkit.WebStorage.getInstance().deleteAllData()
                context.stopService(Intent(context, UsageOverlayService::class.java))
                UsageNotifications.cancel(context)
                signOut = false
            }) { Text(label("Disconnect", "断开连接")) }
        }, dismissButton = { TextButton(onClick = { signOut = false }) { Text(label("Cancel", "取消")) } })
}

@Composable
private fun Section(text: String) {
    HorizontalDivider()
    Text(text, fontSize = 11.sp, fontFamily = FontFamily.Monospace,
        color = MaterialTheme.colorScheme.onSurfaceVariant)
}

@Composable
private fun Toggle(text: String, checked: Boolean, onChange: (Boolean) -> Unit) {
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Text(text, Modifier.weight(1f))
        Switch(checked, onChange)
    }
}

@Composable
private fun WebSignIn(model: CursorViewModel, back: () -> Unit) {
    val context = LocalContext.current
    val web = remember {
        WebView(context).apply {
            settings.javaScriptEnabled = true
            settings.domStorageEnabled = true
            settings.allowFileAccess = false
            settings.allowContentAccess = false
            settings.mixedContentMode = android.webkit.WebSettings.MIXED_CONTENT_NEVER_ALLOW
            CookieManager.getInstance().setAcceptThirdPartyCookies(this, false)
            webViewClient = object : WebViewClient() {
                override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
                    val uri = request.url
                    if (uri.scheme != "https") return true
                    val host = uri.host.orEmpty()
                    val trusted = host == "cursor.com" || host.endsWith(".cursor.com") ||
                        host == "workos.com" || host.endsWith(".workos.com") ||
                        host == "accounts.google.com" || host == "github.com"
                    if (!trusted) openHttps(context, uri.toString())
                    return !trusted
                }
            }
            loadUrl("https://cursor.com/agents")
        }
    }
    DisposableEffect(web) { onDispose { web.stopLoading(); web.destroy() } }
    Column {
        Text(label("Sign in, then connect. Some SSO providers reject embedded browsers; " +
            "API key mode remains available for agents.",
            "登录后点击连接。部分 SSO 不支持内嵌浏览器，Agent 仍可通过 API Key 使用。"),
            Modifier.padding(16.dp), fontSize = 12.sp)
        Row(Modifier.padding(horizontal = 16.dp)) {
            Button(onClick = {
                val cookie = CookieManager.getInstance().getCookie("https://cursor.com").orEmpty()
                model.connectWeb(cookie)
                back()
            }) { Text(label("Connect this session", "连接此会话")) }
        }
        AndroidView(factory = { web }, modifier = Modifier.fillMaxSize())
    }
}

@Composable
private fun EnvironmentScreen(id: String, state: UiState, model: CursorViewModel) {
    var name by rememberSaveable(id) { mutableStateOf("") }
    var configuration by rememberSaveable(id) { mutableStateOf("") }
    var secretName by remember { mutableStateOf("") }
    var secretValue by remember { mutableStateOf("") }
    var pendingDelete by remember { mutableStateOf<JsonObject?>(null) }
    var confirmSave by remember { mutableStateOf(false) }
    var invalidJson by remember { mutableStateOf(false) }
    LaunchedEffect(id) { model.environment(id) }
    LaunchedEffect(state.local.environment) {
        name = state.local.environment?.string("name").orEmpty()
        configuration = state.local.environment?.string("environmentJson").orEmpty()
    }
    Column(Modifier.padding(20.dp).verticalScroll(rememberScrollState()),
        verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Text(label("Environment", "环境"), style = MaterialTheme.typography.headlineMedium)
        OutlinedTextField(name, { name = it }, Modifier.fillMaxWidth(), label = { Text(label("Name", "名称")) })
        OutlinedTextField(configuration, { configuration = it; invalidJson = false },
            Modifier.fillMaxWidth(), minLines = 8, isError = invalidJson,
            label = { Text("environment.json") })
        Text(label("Saving replaces the full environment configuration. Repositories and owner stay unchanged.",
            "保存将替换完整环境配置，仓库和所有者保持不变。"), fontSize = 12.sp)
        Button(onClick = {
            invalidJson = runCatching { Json.parseToJsonElement(configuration) is JsonObject }
                .getOrDefault(false).not()
            if (!invalidJson) confirmSave = true
        }, enabled = name.isNotBlank() && !state.local.busy) { Text(label("Save environment", "保存环境")) }
        Section(label("RUNTIME SECRETS", "运行时密钥"))
        Text(label("Values cannot be read back. New values are sent once and never cached.",
            "密钥值无法回读。新值仅发送一次，不存入缓存。"), fontSize = 12.sp)
        state.local.secrets.forEach { secret ->
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(secret.string("name") + " · " + secret.string("type"), Modifier.weight(1f))
                TextButton(onClick = { pendingDelete = secret }) { Text(label("Delete", "删除")) }
            }
        }
        OutlinedTextField(secretName, { secretName = it }, Modifier.fillMaxWidth(), singleLine = true,
            label = { Text(label("New secret name", "新密钥名称")) })
        OutlinedTextField(secretValue, { secretValue = it }, Modifier.fillMaxWidth(),
            visualTransformation = PasswordVisualTransformation(), label = { Text(label("Secret value", "密钥值")) })
        Button(onClick = {
            model.secret(id, secretName, buildJsonObject {
                put("value", secretValue); put("type", "runtime_secret")
            })
            secretName = ""
            secretValue = ""
        }, enabled = secretName.isNotBlank() && secretValue.isNotBlank() && !state.local.busy) {
            Text(label("Add secret", "添加密钥"))
        }
    }
    if (confirmSave) AlertDialog(onDismissRequest = { confirmSave = false },
        title = { Text(label("Replace configuration?", "替换环境配置？")) },
        text = { Text(label("This changes the saved environment for future agents.", "此操作会修改后续 Agent 使用的环境。")) },
        confirmButton = { TextButton(onClick = {
            confirmSave = false
            model.saveEnvironment(id, buildJsonObject { put("name", name); put("environmentJson", configuration) })
        }) { Text(label("Save", "保存")) } },
        dismissButton = { TextButton(onClick = { confirmSave = false }) { Text(label("Cancel", "取消")) } })
    if (pendingDelete != null) AlertDialog(onDismissRequest = { pendingDelete = null },
        title = { Text(label("Delete secret version?", "删除密钥版本？")) },
        text = { Text(pendingDelete?.string("name").orEmpty()) },
        confirmButton = { TextButton(onClick = {
            pendingDelete?.let { model.secret(id, it.string("name"), null, it.string("id")) }
            pendingDelete = null
        }) { Text(label("Delete", "删除")) } },
        dismissButton = { TextButton(onClick = { pendingDelete = null }) { Text(label("Cancel", "取消")) } })
}


@Composable
private fun WebSettings(state: UiState, model: CursorViewModel) {
    var prefix by remember { mutableStateOf("") }
    var defaultModel by remember { mutableStateOf("") }
    var pr by remember { mutableStateOf("") }
    var confirmation by remember { mutableStateOf(false) }
    LaunchedEffect(state.local.webSettings) {
        prefix = state.local.webSettings?.string("branchPrefix").orEmpty()
        defaultModel = state.local.webSettings?.string("modelName").orEmpty()
        pr = state.local.webSettings?.string("autoCreatePrSetting").orEmpty()
    }
    Section(label("CURSOR WEB DEFAULTS", "CURSOR 网页默认设置"))
    Text(label("Personal web preferences. Team policies can override them; API create options are separate.",
        "个人网页偏好，可能受团队策略覆盖；API 新建选项与此独立。"), fontSize = 12.sp)
    OutlinedButton(onClick = { model.webSettings() }) { Text(label("Load web settings", "加载网页设置")) }
    if (state.local.webSettings != null) {
        OutlinedTextField(prefix, { prefix = it }, Modifier.fillMaxWidth(),
            label = { Text(label("Branch prefix", "分支前缀")) })
        OutlinedTextField(defaultModel, { defaultModel = it }, Modifier.fillMaxWidth(),
            label = { Text(label("Default model ID", "默认模型 ID")) })
        FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            listOf("ALWAYS", "SINGLE", "NEVER").forEach { option ->
                FilterChip(pr == "AUTO_CREATE_PR_SETTING_$option",
                    { pr = "AUTO_CREATE_PR_SETTING_$option" }, label = { Text(option.lowercase()) })
            }
        }
        Text(label("Auto PR: always / single / never, using Cursor’s server values.",
            "自动 PR：始终 / 单个 / 从不，使用 Cursor 服务端定义。"), fontSize = 12.sp)
        Button(onClick = { confirmation = true }, enabled = !state.local.busy) {
            Text(label("Save web defaults", "保存网页默认设置"))
        }
    }
    if (confirmation) AlertDialog(onDismissRequest = { confirmation = false },
        title = { Text(label("Update personal defaults?", "更新个人默认设置？")) },
        text = { Text(label("Only changed fields are sent. Settings are reloaded after saving.",
            "只发送已更改字段，保存后重新读取设置。")) },
        confirmButton = { TextButton(onClick = {
            confirmation = false
            val original = state.local.webSettings
            model.webSettings(buildJsonObject {
                if (prefix != original?.string("branchPrefix")) put("branchPrefix", prefix)
                if (defaultModel != original?.string("modelName")) put("modelName", defaultModel)
                if (pr != original?.string("autoCreatePrSetting") && pr.isNotBlank()) {
                    put("autoCreatePrSetting", pr)
                }
            })
        }) { Text(label("Save", "保存")) } },
        dismissButton = { TextButton(onClick = { confirmation = false }) { Text(label("Cancel", "取消")) } })
}
