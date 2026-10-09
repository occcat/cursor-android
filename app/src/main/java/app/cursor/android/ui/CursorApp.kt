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
import androidx.compose.animation.core.tween
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
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
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.BottomSheetDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.LocalTextStyle
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
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
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
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
import app.cursor.android.data.array
import app.cursor.android.data.string
import app.cursor.android.domain.UsageSnapshot
import app.cursor.android.domain.isGoogleSignInHost
import app.cursor.android.domain.isTrustedSignInUrl
import app.cursor.android.system.UsageNotifications
import app.cursor.android.system.UsageOverlayService
import app.cursor.android.widget.WidgetDestination
import app.cursor.android.widget.WidgetPicker
import java.text.DateFormat
import java.util.Date
import kotlinx.coroutines.delay
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.put

@Serializable private data class Destination(val screen: String, val id: String = "") : NavKey

@Composable
fun label(english: String, chinese: String): String =
    if (LocalConfiguration.current.locales[0].language == "zh") chinese else english

@Composable
fun CursorApp(
    state: UiState,
    model: CursorViewModel,
    widgetDestination: WidgetDestination? = null,
    consumeWidgetDestination: () -> Unit = {},
) {
    val backStack = rememberNavBackStack(Destination("inbox"))
    val context = LocalContext.current
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    var usageOpen by rememberSaveable { mutableStateOf(false) }
    LaunchedEffect(widgetDestination) {
        widgetDestination?.let { target ->
            backStack.clear()
            backStack.add(Destination("inbox"))
            usageOpen = target.screen == "usage"
            if (target.screen !in listOf("inbox", "usage")) {
                backStack.add(Destination(target.screen, target.agentId))
            }
            consumeWidgetDestination()
        }
    }
    LaunchedEffect(state.preferences.language) {
        AppCompatDelegate.setApplicationLocales(
            LocaleListCompat.forLanguageTags(state.preferences.language)
        )
    }
    LaunchedEffect(state.local.webConnected) { if (state.local.webConnected) model.refresh() }
    LaunchedEffect(
        state.local.webConnected,
        state.preferences.paused,
        state.preferences.intervalSeconds,
        lifecycle,
    ) {
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
    CursorTheme {
        val colors = CursorTheme.colors
        val toolbarPadding = PaddingValues(horizontal = 8.dp)
        Scaffold(
            topBar = {
                Column {
                    TopAppBar(
                        title = {
                            Text("Cursor Android", style = MaterialTheme.typography.titleSmall)
                        },
                        navigationIcon = {
                            if (backStack.size > 1)
                                CursorTextButton(
                                    onClick = { backStack.removeLastOrNull() },
                                    contentPadding = toolbarPadding,
                                ) {
                                    Text(label("Back", "返回"))
                                }
                        },
                        actions = {
                            CursorTextButton(
                                onClick = { usageOpen = true },
                                contentPadding = toolbarPadding,
                            ) {
                                Text(label("Usage", "用量"))
                            }
                            CursorTextButton(
                                onClick = { backStack.add(Destination("settings")) },
                                contentPadding = toolbarPadding,
                            ) {
                                Text(label("Settings", "设置"))
                            }
                        },
                        expandedHeight = 56.dp,
                        colors =
                            TopAppBarDefaults.topAppBarColors(
                                containerColor = colors.bg,
                                scrolledContainerColor = colors.bg,
                                titleContentColor = colors.fg,
                            ),
                    )
                    HorizontalDivider(color = colors.border02)
                }
            }
        ) { padding ->
            Column(Modifier.fillMaxSize().padding(padding)) {
                if (state.local.busy)
                    LinearProgressIndicator(
                        Modifier.fillMaxWidth().height(2.dp),
                        color = colors.accent,
                        trackColor = Color.Transparent,
                        gapSize = 0.dp,
                    )
                if (state.local.error != null) {
                    Surface(color = colors.cardWarm, contentColor = colors.fg) {
                        Row(
                            Modifier.fillMaxWidth().height(IntrinsicSize.Min),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Box(Modifier.width(2.dp).fillMaxHeight().background(colors.error))
                            Text(
                                state.local.error,
                                Modifier.weight(1f).padding(12.dp),
                                style = MaterialTheme.typography.bodyMedium,
                            )
                            CursorTextButton(onClick = model::clearError) {
                                Text(label("Dismiss", "关闭"))
                            }
                        }
                    }
                }
                NavDisplay(
                    backStack = backStack,
                    onBack = { backStack.removeLastOrNull() },
                    entryProvider =
                        entryProvider {
                            entry<Destination> { route ->
                                when (route.screen) {
                                    "inbox" ->
                                        Inbox(
                                            state,
                                            model,
                                            { backStack.add(Destination("create")) },
                                            { backStack.add(Destination("detail", it)) },
                                            { backStack.add(Destination("signin")) },
                                            { usageOpen = true },
                                        )
                                    "create" ->
                                        CreateAgent(state, model) {
                                            backStack.removeLastOrNull()
                                            backStack.add(Destination("detail", it))
                                        }
                                    "detail" -> AgentDetail(route.id, state, model)
                                    "settings" ->
                                        SettingsScreen(
                                            state,
                                            model,
                                            { backStack.add(Destination("signin")) },
                                            { backStack.add(Destination("environment", it)) },
                                        )
                                    "signin" -> WebSignIn(model) { backStack.removeLastOrNull() }
                                    "environment" -> EnvironmentScreen(route.id, state, model)
                                }
                            }
                        },
                )
            }
        }
        if (usageOpen)
            ModalBottomSheet(
                onDismissRequest = { usageOpen = false },
                containerColor = CursorTheme.colors.bg,
                contentColor = CursorTheme.colors.fg,
                tonalElevation = 0.dp,
                dragHandle = {
                    BottomSheetDefaults.DragHandle(color = CursorTheme.colors.border025)
                },
            ) {
                UsagePanel(
                    state.usage,
                    state.preferences,
                    state.local.webConnected,
                    model::refreshUsage,
                )
            }
    }
}

@Composable
private fun Inbox(
    state: UiState,
    model: CursorViewModel,
    create: () -> Unit,
    detail: (String) -> Unit,
    signIn: () -> Unit,
    usage: () -> Unit,
) {
    var query by rememberSaveable { mutableStateOf("") }
    var archived by rememberSaveable { mutableStateOf(false) }
    LazyColumn(
        contentPadding = PaddingValues(20.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        item {
            Text(
                label("Your work.\nWithin reach.", "你的工作，\n随时掌握。"),
                style = MaterialTheme.typography.headlineLarge,
            )
            Spacer(Modifier.height(8.dp))
            Text(
                label("Cloud agents, wherever you are.", "随时随地，连接云端 Agent。"),
                color = CursorTheme.colors.textSecondary,
            )
        }
        item { UsageCapsule(state.usage, state.preferences, usage) }
        if (!state.local.webConnected) {
            item {
                CursorCard {
                    Column(
                        Modifier.padding(16.dp),
                        verticalArrangement = Arrangement.spacedBy(12.dp),
                    ) {
                        Text(
                            label("Connect your workspace", "连接你的工作区"),
                            style = MaterialTheme.typography.titleLarge,
                        )
                        Description(
                            label(
                                "Sign in with the Cursor web session on this device. " +
                                    "Email codes and GitHub stay in the app.",
                                "在本机使用 Cursor 网页会话登录。邮箱验证码和 GitHub 留在应用内。",
                            )
                        )
                        CursorButton(onClick = signIn) { Text(label("Get started", "开始使用")) }
                    }
                }
            }
            item { FeatureLinks() }
        } else {
            item {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    CursorButton(onClick = create, enabled = !state.local.busy) {
                        Text(label("+ New agent", "+ 新建 Agent"))
                    }
                    CursorSecondaryButton(onClick = { model.refresh() }) {
                        Text(label("Refresh", "刷新"))
                    }
                }
            }
            item {
                CursorTextField(
                    query,
                    { query = it },
                    Modifier.fillMaxWidth(),
                    label = { Text(label("Search agents", "搜索 Agent")) },
                    singleLine = true,
                )
                CursorChip(archived, { archived = !archived }, label("Include archived", "包含归档"))
            }
            val agents =
                state.agents?.array("composers").orEmpty().filter {
                    (archived || it.string("status") != "ARCHIVED") &&
                        it.string("name").contains(query, ignoreCase = true)
                }
            if (agents.isEmpty())
                item {
                    Description(
                        label("No agents here yet. Start with a task.", "暂无 Agent，创建一个任务开始。")
                    )
                }
            items(agents, key = { it.string("bcId").ifBlank { it.string("name") } }) { agent ->
                CursorCard(Modifier.fillMaxWidth(), onClick = { detail(agent.string("bcId")) }) {
                    Column(
                        Modifier.padding(16.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        Text(
                            agent.string("name").ifBlank { label("Untitled agent", "未命名 Agent") },
                            style = MaterialTheme.typography.titleMedium,
                        )
                        FlowRow(
                            horizontalArrangement = Arrangement.spacedBy(10.dp),
                            itemVerticalAlignment = Alignment.CenterVertically,
                        ) {
                            AgentStatus(agent.string("status"))
                            Note(updatedLabel(agent))
                        }
                    }
                }
            }
            if ((state.agents?.get("hasMore") as? JsonPrimitive)?.booleanOrNull == true)
                item {
                    CursorSecondaryButton(onClick = { model.refresh(true) }) {
                        Text(label("Load more", "加载更多"))
                    }
                }
            item { FeatureLinks() }
        }
        item {
            Note(
                label(
                    "Independent community client. Not affiliated with Cursor.",
                    "独立社区客户端，与 Cursor 官方无关联。",
                )
            )
        }
    }
}

@Composable
private fun FeatureLinks() {
    val context = LocalContext.current
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(
            label("Continue on Cursor Web", "在 Cursor 网页中继续"),
            style = MaterialTheme.typography.titleMedium,
        )
        Description(
            label(
                "Automations, Codebase, Desktop, Terminal and Files open in your browser.",
                "自动化、Codebase、桌面、终端及文件功能将在浏览器中打开。",
            )
        )
        CursorSecondaryButton(onClick = { openHttps(context, "https://cursor.com/agents") }) {
            Text(label("Open Cursor Web ↗", "打开 Cursor 网页 ↗"))
        }
    }
}

@Composable
fun UsageCapsule(usage: UsageSnapshot?, preferences: Preferences, click: () -> Unit) {
    if (!preferences.cursor && !preferences.other) return
    val colors = CursorTheme.colors
    val remaining = label("remaining", "剩余")
    val used = label("used", "已用")
    val mode = if (preferences.remaining) remaining else used
    val cursorValue = usageValue(usage, true, preferences.remaining)
    val otherValue = usageValue(usage, false, preferences.remaining)
    val figures = LocalTextStyle.current.copy(fontFeatureSettings = "tnum")
    Surface(
        onClick = click,
        shape = RoundedCornerShape(24.dp),
        color = colors.card,
        contentColor = colors.fg,
        border = BorderStroke(1.dp, colors.border02),
    ) {
        FlowRow(
            Modifier.padding(horizontal = 16.dp, vertical = 12.dp),
            horizontalArrangement = Arrangement.spacedBy(14.dp),
            itemVerticalAlignment = Alignment.CenterVertically,
        ) {
            if (preferences.cursor)
                Text(
                    pool("●", colors.poolCursor, "Cursor $cursorValue"),
                    style = figures,
                    modifier =
                        Modifier.semantics {
                            contentDescription = "Cursor Model $cursorValue $mode"
                        },
                )
            if (preferences.other)
                Text(
                    pool("○", colors.poolOther, "Other $otherValue"),
                    style = figures,
                    modifier =
                        Modifier.semantics {
                            contentDescription = "Other Model $otherValue $mode"
                        },
                )
            Note(mode)
        }
    }
}

/** Colors only the pool marker so the capsule text stays identical for tests and TalkBack. */
private fun pool(marker: String, tint: Color, text: String): AnnotatedString =
    buildAnnotatedString {
        withStyle(SpanStyle(color = tint)) { append(marker) }
        append(" ")
        append(text)
    }

fun usageValue(snapshot: UsageSnapshot?, cursor: Boolean, remaining: Boolean): String =
    if (snapshot?.unlimited == true) "∞"
    else snapshot?.value(cursor, remaining)?.let { "${it.toInt()}%" } ?: "—"

@Composable
private fun UsagePanel(
    usage: UsageSnapshot?,
    preferences: Preferences,
    connected: Boolean,
    refresh: () -> Unit,
) {
    val colors = CursorTheme.colors
    Column(
        Modifier.padding(24.dp).verticalScroll(rememberScrollState()),
        verticalArrangement = Arrangement.spacedBy(20.dp),
    ) {
        Text("Cursor Usage", style = MaterialTheme.typography.headlineSmall)
        Description(
            if (connected) label("Account quota · last successful snapshot", "账户额度 · 最近成功快照")
            else label("Connect a web session in Settings to view usage.", "在设置中连接网页会话以查看用量。")
        )
        val now = System.currentTimeMillis()
        listOf(true, false).forEach { cursor ->
            if (if (cursor) preferences.cursor else preferences.other) {
                val tint = if (cursor) colors.poolCursor else colors.poolOther
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Row(
                        Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Row(
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Dot(tint)
                            Text(if (cursor) "Cursor Model" else "Other Model")
                        }
                        Text(
                            usageValue(usage, cursor, preferences.remaining),
                            style =
                                MaterialTheme.typography.headlineSmall.copy(
                                    fontFamily = FontFamily.Monospace,
                                    fontFeatureSettings = "tnum",
                                ),
                        )
                    }
                    Note(
                        if (preferences.remaining) label("Remaining", "剩余额度")
                        else label("Used", "已用额度")
                    )
                    val value = usage?.value(cursor, preferences.remaining)
                    if (value != null && !usage.unlimited) {
                        CursorProgress((value / 100).toFloat(), tint)
                        val pace = if (preferences.pace) usage.pace(now) else null
                        if (pace != null) {
                            val raw = if (cursor) usage.cursorUsed else usage.otherUsed
                            val text =
                                when (pace.category(raw ?: 0.0)) {
                                    1 -> label("Faster than billing pace", "使用快于账单周期节奏")
                                    -1 -> label("Slower than billing pace", "使用慢于账单周期节奏")
                                    else -> label("On pace", "节奏正常")
                                }
                            Note(
                                text +
                                    if (pace.estimated) label(" · estimated cycle", " · 估算周期")
                                    else ""
                            )
                        }
                    }
                }
            }
        }
        if (usage != null) {
            HorizontalDivider()
            Note(label("Updated ", "更新于 ") + time(usage.fetchedAt))
            if (!usage.unlimited && usage.cycleEnd != null) {
                Note(label("Resets ", "重置时间 ") + time(usage.cycleEnd))
            }
            if (usage.pendingReset(now)) Text(label("Awaiting new billing cycle data", "等待新账单周期数据"))
        }
        if (preferences.paused) Text(label("Automatic refresh paused", "自动刷新已暂停"))
        CursorButton(onClick = refresh, enabled = connected) {
            Text(label("Refresh usage", "刷新用量"))
        }
        Note(
            label(
                "Background updates are scheduled by Android, at least 15 minutes apart.",
                "后台更新由 Android 调度，间隔至少 15 分钟。",
            )
        )
        Spacer(Modifier.height(20.dp))
    }
}

private fun updatedLabel(agent: JsonObject): String {
    val raw = (agent["updatedAtMs"] as? JsonPrimitive)?.contentOrNull
    val millis = raw?.toLongOrNull()
    return if (millis != null) time(millis) else agent.string("updatedAt")
}

private fun time(value: Long): String =
    DateFormat.getDateTimeInstance(DateFormat.MEDIUM, DateFormat.SHORT).format(Date(value))

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
    LaunchedEffect(Unit) { model.catalog() }
    Column(
        Modifier.padding(20.dp).verticalScroll(rememberScrollState()),
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Text(
            label("What should we build?", "我们要实现什么？"),
            style = MaterialTheme.typography.headlineMedium,
        )
        Text(
            label("Start a cloud agent with your own Cursor account.", "使用你的 Cursor 账户启动云端 Agent。"),
            color = CursorTheme.colors.textSecondary,
        )
        CursorTextField(
            prompt,
            { prompt = it },
            Modifier.fillMaxWidth(),
            minLines = 5,
            label = { Text(label("Describe a task", "描述任务")) },
        )
        Text(label("Workspace", "工作区"), style = MaterialTheme.typography.titleMedium)
        CursorTextField(
            repository,
            { repository = it },
            Modifier.fillMaxWidth(),
            enabled = environment.isBlank(),
            label = { Text(label("Repository URLs · one per line", "仓库 URL · 每行一个")) },
            supportingText = {
                Text(label("Leave empty to start without a repository.", "留空以创建无仓库任务。"))
            },
        )
        FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            state.local.repositories.take(10).forEach { repo ->
                CursorActionChip(
                    onClick = {
                        repository = repo.string("htmlUrl")
                        environment = ""
                    },
                    label = repo.string("htmlUrl").substringAfterLast('/'),
                )
            }
        }
        FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            CursorChip(
                environment.isBlank(),
                { environment = "" },
                label = label("Default environment", "默认环境"),
            )
            state.local.environments.forEach { env ->
                CursorChip(
                    environment == env.string("publicId"),
                    {
                        environment = env.string("publicId")
                        repository = ""
                    },
                    label = env.string("name").ifBlank { env.string("publicId") },
                )
            }
        }
        Text(label("Model", "模型"), style = MaterialTheme.typography.titleMedium)
        FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            CursorChip(
                selectedModel.isBlank(),
                { selectedModel = "" },
                label = label("Account default", "账户默认"),
            )
            state.local.models.forEach { item ->
                CursorChip(
                    selectedModel == item.string("serverModelName"),
                    { selectedModel = item.string("serverModelName") },
                    label =
                        item.string("clientDisplayName").ifBlank {
                            item.string("serverModelName")
                        },
                )
            }
        }
        CursorButton(
            onClick = {
                model.create(
                    prompt,
                    repository.lines().map(String::trim).filter(String::isNotEmpty),
                    selectedModel,
                    environment,
                    complete,
                )
            },
            enabled = prompt.isNotBlank() && !state.local.busy,
            modifier = Modifier.fillMaxWidth(),
        ) {
            Text(label("Start agent →", "启动 Agent →"))
        }
        Note(
            label(
                "Runs may consume your Cursor allowance. Sending is never retried automatically.",
                "运行可能消耗 Cursor 额度，发送操作不会自动重试。",
            )
        )
        Spacer(Modifier.height(20.dp))
    }
}

@Composable
private fun AgentDetail(id: String, state: UiState, model: CursorViewModel) {
    val context = LocalContext.current
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    var followUp by rememberSaveable(id) { mutableStateOf("") }
    var confirm by remember { mutableStateOf<String?>(null) }
    var showArtifacts by rememberSaveable { mutableStateOf(false) }
    var artifactBody by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(id, lifecycle) {
        lifecycle.repeatOnLifecycle(Lifecycle.State.STARTED) { model.detail(id).join() }
    }
    DisposableEffect(id) { onDispose { model.stopWatching() } }
    val agent = state.local.detail?.takeIf { it.string("bcId") == id }
    if (agent == null) {
        Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text(label("Loading this workspace…", "正在加载此工作区…"))
            CursorSecondaryButton(onClick = { model.detail(id) }) { Text(label("Retry", "重试")) }
        }
        return
    }
    LazyColumn(
        contentPadding = PaddingValues(20.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        item {
            Text(
                agent?.string("name").orEmpty().ifBlank { label("Agent", "Agent") },
                style = MaterialTheme.typography.headlineMedium,
            )
            Spacer(Modifier.height(8.dp))
            AgentStatus(agent?.string("status").orEmpty())
        }
        item {
            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                CursorActionChip(onClick = { model.detail(id) }, label = label("Refresh", "刷新"))
                CursorActionChip(
                    onClick = { openHttps(context, "https://cursor.com/agents/$id") },
                    label = label("Workspace ↗", "工作区 ↗"),
                )
                CursorActionChip(
                    onClick = {
                        showArtifacts = !showArtifacts
                        model.artifacts(id)
                    },
                    label = label("Artifacts", "产物"),
                )
                if (agent?.string("status") !in listOf(
                        "FINISHED",
                        "ERROR",
                        "FAILED",
                        "EXPIRED",
                        "CANCELLED",
                        "ARCHIVED",
                    )
                ) {
                    CursorActionChip(
                        onClick = { if (!state.local.pauseUnavailable) confirm = "pause" },
                        label =
                            if (state.local.pauseUnavailable) label("Pause unavailable", "无法暂停")
                            else label("Pause", "暂停"),
                    )
                }
                CursorActionChip(
                    onClick = {
                        confirm =
                            if (agent?.string("status") == "ARCHIVED") "unarchive" else "archive"
                    },
                    label =
                        if (agent?.string("status") == "ARCHIVED") label("Restore", "恢复")
                        else label("Archive", "归档"),
                )
            }
            if (state.local.pauseUnavailable) {
                Spacer(Modifier.height(8.dp))
                Note(
                    label(
                        "This response cannot pause the agent.",
                        "这次返回无法表示暂停。",
                    )
                )
            }
        }
        if (showArtifacts) {
            items(state.local.artifacts) { artifact ->
                val title =
                    listOf("path", "name", "absolutePath")
                        .map { artifact.string(it) }
                        .firstOrNull { it.isNotBlank() }
                if (title != null)
                    CursorSecondaryButton(
                        onClick = { model.artifactText(id, artifact) { artifactBody = it } },
                        modifier =
                            Modifier.animateItem(fadeInSpec = tween(CursorMotion.slowMillis)),
                    ) {
                        Text(title)
                    }
            }
            if (
                state.local.artifacts.isEmpty() ||
                    state.local.artifacts.none { artifact ->
                        listOf("path", "name", "absolutePath").any {
                            artifact.string(it).isNotBlank()
                        }
                    }
            )
                item { Description(label("No artifacts returned.", "暂无产物。")) }
        }
        item {
            CursorTextField(
                followUp,
                { followUp = it },
                Modifier.fillMaxWidth(),
                minLines = 3,
                label = { Text(label("Follow up", "继续追问")) },
            )
            CursorButton(
                onClick = {
                    model.followUp(id, followUp)
                    followUp = ""
                },
                enabled = followUp.isNotBlank() && !state.local.busy,
            ) {
                Text(label("Send follow-up", "发送追问"))
            }
        }
        item { FeatureLinks() }
    }
    if (artifactBody != null)
        CursorAlertDialog(
            onDismissRequest = { artifactBody = null },
            title = { Text(label("Artifact", "产物")) },
            text = {
                SelectionContainer {
                    Text(artifactBody.orEmpty().ifBlank { label("No bytes returned.", "没有返回内容。") })
                }
            },
            confirmButton = {
                CursorTextButton(onClick = { artifactBody = null }) { Text(label("Close", "关闭")) }
            },
        )
    if (confirm != null)
        CursorAlertDialog(
            onDismissRequest = { confirm = null },
            title = { Text(label("Confirm agent action", "确认操作")) },
            text = {
                Text(
                    when (confirm) {
                        "pause" -> label("Pause this agent?", "暂停此 Agent？")
                        "archive" -> label("Archive this agent?", "归档此 Agent？")
                        else -> label("Restore this agent?", "恢复此 Agent？")
                    }
                )
            },
            confirmButton = {
                CursorTextButton(
                    onClick = {
                        val action = confirm ?: return@CursorTextButton
                        confirm = null
                        model.agentAction(id, action) {}
                    },
                    tone = CursorTone.Default,
                ) {
                    Text(label("Confirm", "确认"))
                }
            },
            dismissButton = {
                CursorTextButton(onClick = { confirm = null }) { Text(label("Keep", "保留")) }
            },
        )
}

@Composable
private fun SettingsScreen(
    state: UiState,
    model: CursorViewModel,
    signIn: () -> Unit,
    environment: (String) -> Unit,
) {
    val context = LocalContext.current
    var signOut by remember { mutableStateOf(false) }
    val permission =
        rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) {
            model.boolean("notifications", it)
        }
    Column(
        Modifier.padding(20.dp).verticalScroll(rememberScrollState()),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Text(label("Make it yours.", "按你的方式使用。"), style = MaterialTheme.typography.headlineMedium)
        Section(label("CONNECTIONS", "连接"))
        Text(label("Web session", "网页会话"), style = MaterialTheme.typography.titleMedium)
        Description(
            if (state.local.webConnected)
                label(
                    "Signed in with the cursor.com session stored on this device.",
                    "已使用保存在本设备的 cursor.com 会话登录。",
                )
            else
                label(
                    "Sign in inside the app. The session cookie stays encrypted on this device.",
                    "在应用内登录。会话 cookie 会加密保存在本设备。",
                )
        )
        CursorSecondaryButton(onClick = signIn) {
            Text(
                if (state.local.webConnected) label("Reconnect web session", "重新连接网页会话")
                else label("Connect web session", "连接网页会话")
            )
        }
        if (state.local.webConnected) {
            CursorTextButton(onClick = { signOut = true }) {
                Text(label("Disconnect & clear local data", "断开并清除本地数据"))
            }
        }
        if (state.local.webConnected) WebSettings(state, model)
        Section(label("CURSOR USAGE", "CURSOR 用量"))
        Toggle("Cursor Model", state.preferences.cursor) { model.boolean("cursor", it) }
        Toggle("Other Model", state.preferences.other) { model.boolean("other", it) }
        Toggle(label("Show remaining allowance", "显示剩余额度"), state.preferences.remaining) {
            model.boolean("remaining", it)
        }
        Toggle(label("Billing pace", "账单周期节奏"), state.preferences.pace) {
            model.boolean("pace", it)
        }
        Toggle(label("Pause automatic refresh", "暂停自动刷新"), state.preferences.paused) {
            model.boolean("paused", it)
        }
        Text(label("Foreground refresh", "前台刷新间隔"))
        FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            listOf(30, 60, 120, 300).forEach { seconds ->
                CursorChip(
                    state.preferences.intervalSeconds == seconds,
                    { model.interval(seconds) },
                    label = "${seconds}s",
                )
            }
        }
        Section(label("SYSTEM SURFACES", "系统展示"))
        Toggle(label("Usage notification", "用量通知"), state.preferences.notifications) {
            if (it && Build.VERSION.SDK_INT >= 33)
                permission.launch(Manifest.permission.POST_NOTIFICATIONS)
            else model.boolean("notifications", it)
        }
        Description(
            label(
                "The status bar shows a monochrome icon. " +
                    "Values appear in the notification drawer; " +
                    "lock-screen details stay private.",
                "状态栏显示单色图标，具体数值在通知抽屉中展示，锁屏默认隐藏。",
            )
        )
        CursorSecondaryButton(
            onClick = {
                if (!Settings.canDrawOverlays(context)) {
                    context.startActivity(
                        Intent(
                            Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                            Uri.parse("package:${context.packageName}"),
                        )
                    )
                } else {
                    androidx.core.content.ContextCompat.startForegroundService(
                        context,
                        Intent(context, UsageOverlayService::class.java),
                    )
                }
            },
            enabled =
                state.local.webConnected && (state.preferences.cursor || state.preferences.other),
        ) {
            Text(label("Start floating capsule", "启动悬浮胶囊"))
        }
        CursorTextButton(
            onClick = { context.stopService(Intent(context, UsageOverlayService::class.java)) }
        ) {
            Text(label("Stop floating capsule", "停止悬浮胶囊"))
        }
        Description(
            label(
                "Drag to position. Tap to open the app. The capsule displays cached snapshots; " +
                    "Android schedules background refresh. Starting requires overlay permission.",
                "拖动可调整位置，点击打开应用。胶囊显示缓存快照，后台刷新由 Android 调度，需要悬浮权限。",
            )
        )
        Section(label("HOME SCREEN WIDGETS", "桌面小组件"))
        Description(
            label(
                "Add Usage, Recent Agents or Quick Actions, then resize on your home screen. " +
                    "Cached snapshots refresh about every 15 minutes when Android permits.",
                "添加用量、最近会话或快捷操作后，可在桌面调整大小。缓存快照在 Android 允许时约每 15 分钟刷新。",
            )
        )
        Toggle(
            label("Show agent titles in widgets", "在小组件显示会话标题"),
            state.preferences.widgetTitles,
        ) {
            model.boolean("widgetTitles", it)
        }
        WidgetPicker()
        Section(label("LANGUAGE", "语言"))
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            CursorChip(
                state.preferences.language == "en",
                { model.language("en") },
                label = "English",
            )
            CursorChip(
                state.preferences.language == "zh-CN",
                { model.language("zh-CN") },
                label = "简体中文",
            )
        }
        if (state.local.webConnected) {
            Section(label("CLOUD ENVIRONMENTS", "云端环境"))
            CursorSecondaryButton(onClick = model::catalog) {
                Text(label("Load environments", "加载环境"))
            }
            state.local.environments.forEach { item ->
                CursorTextButton(onClick = { environment(item.string("publicId")) }) {
                    Text(item.string("name").ifBlank { item.string("publicId") })
                }
            }
        }
        FeatureLinks()
        Spacer(Modifier.height(24.dp))
    }
    if (signOut)
        CursorAlertDialog(
            onDismissRequest = { signOut = false },
            title = { Text(label("Disconnect this device?", "断开此设备连接？")) },
            text = {
                Text(
                    label(
                        "Credentials, cached agents, live output and usage will be cleared.",
                        "将清除凭据、缓存 Agent、实时输出及用量。",
                    )
                )
            },
            confirmButton = {
                CursorTextButton(
                    onClick = {
                        model.disconnect()
                        context.stopService(Intent(context, UsageOverlayService::class.java))
                        UsageNotifications.cancel(context)
                        signOut = false
                    },
                    tone = CursorTone.Danger,
                ) {
                    Text(label("Disconnect", "断开连接"))
                }
            },
            dismissButton = {
                CursorTextButton(onClick = { signOut = false }) { Text(label("Cancel", "取消")) }
            },
        )
}

@Composable
private fun Section(text: String) {
    HorizontalDivider()
    Text(
        text,
        style = MaterialTheme.typography.labelSmall,
        color = CursorTheme.colors.textSecondary,
    )
}

@Composable
private fun Toggle(text: String, checked: Boolean, onChange: (Boolean) -> Unit) {
    Row(
        Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text(text, Modifier.weight(1f))
        CursorSwitch(checked, onChange)
    }
}

@Composable
private fun WebSignIn(model: CursorViewModel, back: () -> Unit) {
    val context = LocalContext.current
    var googleBlocked by remember { mutableStateOf(false) }
    val web = remember {
        WebView(context).apply {
            settings.javaScriptEnabled = true
            settings.domStorageEnabled = true
            settings.allowFileAccess = false
            settings.allowContentAccess = false
            settings.mixedContentMode = android.webkit.WebSettings.MIXED_CONTENT_NEVER_ALLOW
            CookieManager.getInstance().setAcceptThirdPartyCookies(this, false)
            webViewClient =
                object : WebViewClient() {
                    override fun shouldOverrideUrlLoading(
                        view: WebView,
                        request: WebResourceRequest,
                    ): Boolean {
                        val uri = request.url
                        if (uri.scheme != "https") return true
                        if (uri.host?.let(::isGoogleSignInHost) == true) {
                            googleBlocked = true
                            return true
                        }
                        val trusted = isTrustedSignInUrl(uri.toString())
                        if (!trusted) openHttps(context, uri.toString())
                        return !trusted
                    }
                }
            loadUrl("https://cursor.com/agents")
        }
    }
    DisposableEffect(web) {
        onDispose {
            web.stopLoading()
            web.destroy()
        }
    }
    Column {
        Note(
            label(
                "Sign in with an email code or GitHub, then connect this session.",
                "用邮箱验证码或 GitHub 登录，然后连接此会话。",
            ),
            Modifier.padding(16.dp),
        )
        if (googleBlocked) {
            Column(
                Modifier.padding(horizontal = 16.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Text(
                    label(
                        "Google sign-in is not available here. Use an email code or GitHub. " +
                            "If this Cursor account only has Google, add an email login in the " +
                            "system browser, then come back and use the code.",
                        "应用内不能使用 Google 登录。请用邮箱验证码或 GitHub。" +
                            "如果账号只有 Google，请先在系统浏览器里给 Cursor 账号加上邮箱登录，" +
                            "再回到这里用验证码。",
                    )
                )
                CursorSecondaryButton(
                    onClick = { openHttps(context, "https://cursor.com/dashboard") }
                ) {
                    Text(label("Add email in the browser ↗", "在浏览器中添加邮箱 ↗"))
                }
                CursorTextButton(
                    onClick = {
                        googleBlocked = false
                        web.loadUrl("https://cursor.com/agents")
                    }
                ) {
                    Text(label("Back to sign in", "返回登录"))
                }
            }
        }
        Row(Modifier.padding(horizontal = 16.dp)) {
            CursorButton(
                onClick = {
                    val cookie =
                        CookieManager.getInstance().getCookie("https://cursor.com").orEmpty()
                    if (cookie.isBlank()) return@CursorButton
                    model.connectWeb(cookie) { back() }
                }
            ) {
                Text(label("Connect this session", "连接此会话"))
            }
        }
        if (!googleBlocked) AndroidView(factory = { web }, modifier = Modifier.fillMaxSize())
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
    val loaded = state.local.environment?.string("publicId") == id
    LaunchedEffect(state.local.environment, id) {
        name = state.local.environment?.string("name").orEmpty()
        configuration = state.local.environment?.string("environmentJson").orEmpty()
    }
    Column(
        Modifier.padding(20.dp).verticalScroll(rememberScrollState()),
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Text(label("Environment", "环境"), style = MaterialTheme.typography.headlineMedium)
        CursorTextField(
            name,
            { name = it },
            Modifier.fillMaxWidth(),
            label = { Text(label("Name", "名称")) },
        )
        CursorTextField(
            configuration,
            {
                configuration = it
                invalidJson = false
            },
            Modifier.fillMaxWidth(),
            minLines = 8,
            isError = invalidJson,
            label = { Text("environment.json") },
        )
        Note(
            label(
                "Saving replaces the full environment configuration. " +
                    "Repositories and owner stay unchanged.",
                "保存将替换完整环境配置，仓库和所有者保持不变。",
            )
        )
        CursorButton(
            onClick = {
                invalidJson =
                    runCatching { Json.parseToJsonElement(configuration) is JsonObject }
                        .getOrDefault(false)
                        .not()
                if (!invalidJson) confirmSave = true
            },
            enabled = loaded && name.isNotBlank() && !state.local.busy,
        ) {
            Text(label("Save environment", "保存环境"))
        }
        Section(label("RUNTIME SECRETS", "运行时密钥"))
        Note(
            label(
                "Values cannot be read back. New values are sent once and never cached.",
                "密钥值无法回读。新值仅发送一次，不存入缓存。",
            )
        )
        state.local.secrets.forEach { secret ->
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(secret.string("name") + " · " + secret.string("type"), Modifier.weight(1f))
                CursorTextButton(onClick = { pendingDelete = secret }, tone = CursorTone.Danger) {
                    Text(label("Delete", "删除"))
                }
            }
        }
        CursorTextField(
            secretName,
            { secretName = it },
            Modifier.fillMaxWidth(),
            singleLine = true,
            label = { Text(label("New secret name", "新密钥名称")) },
        )
        CursorTextField(
            secretValue,
            { secretValue = it },
            Modifier.fillMaxWidth(),
            visualTransformation = PasswordVisualTransformation(),
            keyboardOptions =
                KeyboardOptions(keyboardType = KeyboardType.Password, autoCorrectEnabled = false),
            label = { Text(label("Secret value", "密钥值")) },
        )
        CursorButton(
            onClick = {
                model.secret(id, secretName, secretValue)
                secretName = ""
                secretValue = ""
            },
            enabled =
                loaded && secretName.isNotBlank() && secretValue.isNotBlank() && !state.local.busy,
        ) {
            Text(label("Add secret", "添加密钥"))
        }
    }
    if (confirmSave)
        CursorAlertDialog(
            onDismissRequest = { confirmSave = false },
            title = { Text(label("Replace configuration?", "替换环境配置？")) },
            text = {
                Text(
                    label(
                        "This changes the saved environment for future agents.",
                        "此操作会修改后续 Agent 使用的环境。",
                    )
                )
            },
            confirmButton = {
                CursorTextButton(
                    onClick = {
                        confirmSave = false
                        model.saveEnvironment(
                            id,
                            buildJsonObject {
                                put("name", name)
                                put("environmentJson", configuration)
                            },
                        )
                    }
                ) {
                    Text(label("Save", "保存"))
                }
            },
            dismissButton = {
                CursorTextButton(onClick = { confirmSave = false }) { Text(label("Cancel", "取消")) }
            },
        )
    if (pendingDelete != null)
        CursorAlertDialog(
            onDismissRequest = { pendingDelete = null },
            title = { Text(label("Revoke secret?", "撤销密钥？")) },
            text = { Text(pendingDelete?.string("name").orEmpty()) },
            confirmButton = {
                CursorTextButton(
                    onClick = {
                        pendingDelete?.let { model.secret(id, it.string("name"), null) }
                        pendingDelete = null
                    },
                    tone = CursorTone.Danger,
                ) {
                    Text(label("Delete", "删除"))
                }
            },
            dismissButton = {
                CursorTextButton(onClick = { pendingDelete = null }) { Text(label("Cancel", "取消")) }
            },
        )
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
    Note(
        label(
            "Personal web preferences. Team policies can override them.",
            "个人网页偏好，可能受团队策略覆盖。",
        )
    )
    CursorSecondaryButton(onClick = { model.webSettings() }) {
        Text(label("Load web settings", "加载网页设置"))
    }
    if (state.local.webSettings != null) {
        CursorTextField(
            prefix,
            { prefix = it },
            Modifier.fillMaxWidth(),
            label = { Text(label("Branch prefix", "分支前缀")) },
        )
        CursorTextField(
            defaultModel,
            { defaultModel = it },
            Modifier.fillMaxWidth(),
            label = { Text(label("Default model ID", "默认模型 ID")) },
        )
        FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            listOf("ALWAYS", "SINGLE", "NEVER").forEach { option ->
                CursorChip(
                    pr == "AUTO_CREATE_PR_SETTING_$option",
                    { pr = "AUTO_CREATE_PR_SETTING_$option" },
                    label = option.lowercase(),
                )
            }
        }
        Note(
            label(
                "Auto PR: always / single / never, using Cursor’s server values.",
                "自动 PR：始终 / 单个 / 从不，使用 Cursor 服务端定义。",
            )
        )
        CursorButton(onClick = { confirmation = true }, enabled = !state.local.busy) {
            Text(label("Save web defaults", "保存网页默认设置"))
        }
    }
    if (confirmation)
        CursorAlertDialog(
            onDismissRequest = { confirmation = false },
            title = { Text(label("Update personal defaults?", "更新个人默认设置？")) },
            text = {
                Text(
                    label(
                        "Only changed fields are sent. Settings are reloaded after saving.",
                        "只发送已更改字段，保存后重新读取设置。",
                    )
                )
            },
            confirmButton = {
                CursorTextButton(
                    onClick = {
                        confirmation = false
                        val original = state.local.webSettings
                        model.webSettings(
                            buildJsonObject {
                                if (prefix != original?.string("branchPrefix"))
                                    put("branchPrefix", prefix)
                                if (defaultModel != original?.string("modelName"))
                                    put("modelName", defaultModel)
                                if (
                                    pr != original?.string("autoCreatePrSetting") && pr.isNotBlank()
                                ) {
                                    put("autoCreatePrSetting", pr)
                                }
                            }
                        )
                    }
                ) {
                    Text(label("Save", "保存"))
                }
            },
            dismissButton = {
                CursorTextButton(onClick = { confirmation = false }) { Text(label("Cancel", "取消")) }
            },
        )
}
