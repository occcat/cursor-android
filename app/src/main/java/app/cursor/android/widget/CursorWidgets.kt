package app.cursor.android.widget

import android.annotation.SuppressLint
import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.LocalContext
import androidx.glance.LocalSize
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.appwidget.LinearProgressIndicator
import androidx.glance.appwidget.SizeMode
import androidx.glance.appwidget.action.ActionCallback
import androidx.glance.appwidget.action.actionRunCallback
import androidx.glance.appwidget.action.actionStartActivity
import androidx.glance.appwidget.cornerRadius
import androidx.glance.appwidget.provideContent
import androidx.glance.background
import androidx.glance.color.ColorProvider
import androidx.glance.layout.Alignment
import androidx.glance.layout.Box
import androidx.glance.layout.Column
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.layout.width
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import app.cursor.android.CursorApplication
import app.cursor.android.data.Connections
import app.cursor.android.data.Preferences
import app.cursor.android.system.UsageSyncWorker
import app.cursor.android.ui.CursorColors
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.first

private val ink = dayNight(CursorColors::fg)
private val muted = dayNight(CursorColors::textSecondary)
private val surface = dayNight(CursorColors::bg)
private val tile = dayNight(CursorColors::card03)
private val poolCursor = dayNight(CursorColors::poolCursor)
private val poolOther = dayNight(CursorColors::poolOther)

/** Launchers on API 31+ switch these without a new render when the system theme flips. */
private fun dayNight(token: (CursorColors) -> Color) =
    ColorProvider(day = token(CursorColors.light), night = token(CursorColors.dark))

abstract class CursorWidget : GlanceAppWidget() {
    override val stateDefinition = null

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val application = context.applicationContext as CursorApplication
        val states =
            combine(
                application.repository.usage,
                application.repository.agentSnapshot,
                application.settings.preferences,
                application.repository.connections,
            ) { usage, agents, preferences, connections ->
                WidgetState(usage, agents, preferences, connections)
            }
        val initial = states.first()
        provideContent {
            val state by states.collectAsState(initial)
            Content(state)
        }
    }

    override suspend fun providePreview(context: Context, widgetCategory: Int) {
        provideContent {
            Content(WidgetState(null, null, Preferences(), Connections(false, false)))
        }
    }

    @Composable abstract fun Content(state: WidgetState)
}

class UsageWidget : CursorWidget() {
    override val sizeMode =
        SizeMode.Responsive(
            setOf(
                DpSize(160.dp, 80.dp),
                DpSize(320.dp, 80.dp),
                DpSize(160.dp, 180.dp),
                DpSize(320.dp, 180.dp),
            )
        )

    @Composable
    override fun Content(state: WidgetState) {
        val size = LocalSize.current
        val detailed = size.height >= 180.dp
        val wide = size.width >= 320.dp
        val context = LocalContext.current
        val largerText = usesLargeText()
        Column(
            GlanceModifier.fillMaxSize()
                .background(surface)
                .cornerRadius(24.dp)
                .padding(
                    horizontal = if (detailed) 12.dp else 8.dp,
                    vertical = if (detailed) 12.dp else 8.dp,
                )
                .clickable(actionStartActivity(WidgetDestination("usage").intent(context)))
        ) {
            if (detailed) Caption(state.text("USAGE", "用量") + " · " + state.metric())
            if (detailed && (wide || !largerText)) {
                Spacer(GlanceModifier.height(4.dp))
                Row(GlanceModifier.fillMaxWidth()) {
                    if (state.preferences.cursor) {
                        Column(GlanceModifier.defaultWeight()) {
                            Caption("Cursor Model")
                            Value(state.value(true), detailed)
                            PoolProgress(state, true)
                        }
                    }
                    if (state.preferences.other) {
                        Column(GlanceModifier.defaultWeight()) {
                            Caption("Other Model")
                            Value(state.value(false), detailed)
                            PoolProgress(state, false)
                        }
                    }
                }
            } else {
                if (state.preferences.cursor) {
                    CompactPool("Cursor Model", state.value(true))
                    if (detailed) PoolProgress(state, true)
                }
                if (state.preferences.other) {
                    CompactPool("Other Model", state.value(false))
                    if (detailed) PoolProgress(state, false)
                }
            }
            Spacer(GlanceModifier.defaultWeight())
            Caption(
                if (detailed) state.usageStatus(System.currentTimeMillis())
                else state.compactUsageStatus(System.currentTimeMillis())
            )
            if (detailed) {
                if (wide && !largerText && state.preferences.pace && state.connections.web) {
                    val pace = state.usage?.pace(System.currentTimeMillis())
                    val reset = state.usage?.cycleEnd
                    val parts = buildList {
                        if (pace != null)
                            add(
                                state.text("Target used", "目标已用") +
                                    " ${pace.targetUsed.toInt()}%" +
                                    if (pace.estimated) " ~" else ""
                            )
                        if (reset != null && state.usage?.unlimited != true)
                            add(
                                state.text("Reset ", "重置 ") +
                                    WidgetState.time(reset).substringBefore(' ')
                            )
                    }
                    if (parts.isNotEmpty()) Caption(parts.joinToString(" · "))
                }
                Refresh(state)
            }
        }
    }
}

class AgentsWidget : CursorWidget() {
    override val sizeMode =
        SizeMode.Responsive(
            setOf(DpSize(160.dp, 180.dp), DpSize(320.dp, 180.dp), DpSize(320.dp, 300.dp))
        )

    @Composable
    override fun Content(state: WidgetState) {
        val context = LocalContext.current
        val largerText = usesLargeText()
        val tall = LocalSize.current.height >= 300.dp
        val wide = LocalSize.current.width >= 320.dp
        val rows = state.agentRows().take(if (tall && !largerText) 3 else if (wide) 2 else 1)
        Column(
            GlanceModifier.fillMaxSize()
                .background(surface)
                .cornerRadius(24.dp)
                .padding(horizontal = 12.dp, vertical = if (largerText) 8.dp else 12.dp)
        ) {
            Text(
                state.text("Recent Agents", "最近会话"),
                GlanceModifier.fillMaxWidth(),
                style = TextStyle(color = ink, fontSize = 15.sp, fontWeight = FontWeight.Bold),
                maxLines = 1,
            )
            Spacer(GlanceModifier.height(4.dp))
            if (rows.isEmpty()) {
                Text(
                    if (state.connections.api && state.agents != null)
                        state.text("No agents yet", "暂无会话")
                    else state.text("Open the app to connect", "打开应用以连接"),
                    GlanceModifier.fillMaxWidth()
                        .height(48.dp)
                        .clickable(
                            actionStartActivity(WidgetDestination("settings").intent(context))
                        ),
                    style = TextStyle(color = ink, fontSize = 13.sp),
                    maxLines = 2,
                )
            } else if (wide && !tall) {
                Row(GlanceModifier.fillMaxWidth()) {
                    rows.forEachIndexed { index, agent ->
                        if (index > 0) Spacer(GlanceModifier.width(6.dp))
                        Column(GlanceModifier.defaultWeight()) { AgentRow(agent) }
                    }
                }
            } else {
                rows.forEach { agent ->
                    AgentRow(agent)
                    Spacer(GlanceModifier.height(4.dp))
                }
            }
            Spacer(GlanceModifier.defaultWeight())
            Caption(state.agentStatus(System.currentTimeMillis()))
            Refresh(state)
        }
    }
}

class ActionsWidget : CursorWidget() {
    override val sizeMode = SizeMode.Responsive(setOf(DpSize(160.dp, 80.dp), DpSize(320.dp, 80.dp)))

    @Composable
    override fun Content(state: WidgetState) {
        val context = LocalContext.current
        val actions =
            listOf(
                    "inbox" to state.text("Inbox", "收件箱"),
                    "create" to state.text("New Agent", "新建会话"),
                    "usage" to state.text("Usage", "用量"),
                    "settings" to state.text("Settings", "设置"),
                )
                .take(if (LocalSize.current.width >= 320.dp) 4 else 2)
        Row(
            GlanceModifier.fillMaxSize().background(surface).cornerRadius(24.dp).padding(8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            actions.forEachIndexed { index, (screen, title) ->
                if (index > 0) Spacer(GlanceModifier.width(4.dp))
                Box(
                    GlanceModifier.defaultWeight()
                        .height(64.dp)
                        .background(tile)
                        .cornerRadius(16.dp)
                        .clickable(actionStartActivity(WidgetDestination(screen).intent(context))),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(
                        title,
                        GlanceModifier.padding(4.dp),
                        style =
                            TextStyle(
                                color = ink,
                                fontSize = 13.sp,
                                fontWeight = FontWeight.Medium,
                            ),
                        maxLines = 2,
                    )
                }
            }
        }
    }
}

@Composable
private fun AgentRow(agent: WidgetAgent) {
    val context = LocalContext.current
    Column(
        GlanceModifier.fillMaxWidth()
            .height(if (usesLargeText()) 64.dp else 52.dp)
            .background(tile)
            .cornerRadius(12.dp)
            .padding(horizontal = 10.dp, vertical = 5.dp)
            .clickable(
                actionStartActivity(
                    (WidgetDestination.parse("detail", agent.id) ?: WidgetDestination("inbox"))
                        .intent(context)
                )
            )
    ) {
        Text(agent.title, style = TextStyle(color = ink, fontSize = 14.sp), maxLines = 1)
        Caption(agent.status)
    }
}

@Composable
private fun PoolProgress(state: WidgetState, cursor: Boolean) {
    val value = state.usage?.value(cursor, state.preferences.remaining)
    if (state.connections.web && state.usage?.unlimited == false && value != null) {
        LinearProgressIndicator(
            progress = (value / 100).toFloat(),
            modifier = GlanceModifier.fillMaxWidth().height(4.dp).padding(end = 8.dp),
            color = if (cursor) poolCursor else poolOther,
            backgroundColor = tile,
        )
    }
}

@Composable
private fun Caption(text: String) {
    Text(text, style = TextStyle(color = muted, fontSize = 11.sp), maxLines = 1)
}

@Composable
private fun Value(value: String, detailed: Boolean) {
    Text(
        value,
        style =
            TextStyle(
                color = ink,
                fontSize = if (detailed) 28.sp else 18.sp,
                fontWeight = FontWeight.Medium,
            ),
        maxLines = 1,
    )
}

@Composable
private fun CompactPool(name: String, value: String) {
    Row(GlanceModifier.fillMaxWidth()) {
        Text(
            name,
            GlanceModifier.defaultWeight(),
            style = TextStyle(color = ink, fontSize = 11.sp),
            maxLines = 1,
        )
        Text(
            value,
            style = TextStyle(color = ink, fontSize = 12.sp, fontWeight = FontWeight.Bold),
            maxLines = 1,
        )
    }
}

@Composable
private fun Refresh(state: WidgetState) {
    Box(
        GlanceModifier.fillMaxWidth()
            .height(48.dp)
            .clickable(actionRunCallback<RefreshWidgetsAction>()),
        contentAlignment = Alignment.CenterStart,
    ) {
        Text(state.text("↻ Refresh", "↻ 刷新"), style = TextStyle(color = ink, fontSize = 13.sp))
    }
}

class RefreshWidgetsAction : ActionCallback {
    override suspend fun onAction(
        context: Context,
        glanceId: GlanceId,
        parameters: androidx.glance.action.ActionParameters,
    ) {
        UsageSyncWorker.refresh(context)
        WidgetUpdates.updateAll(context)
    }
}

class UsageWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget = UsageWidget()
}

class AgentsWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget = AgentsWidget()
}

class ActionsWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget = ActionsWidget()
}

/** Glance supplies its own context; Compose UI's LocalConfiguration is not provided here. */
@SuppressLint("LocalContextConfigurationRead")
@Composable
private fun usesLargeText(): Boolean =
    LocalContext.current.resources.configuration.fontScale > 1.15f
