package app.cursor.android.widget

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
import androidx.glance.appwidget.SizeMode
import androidx.glance.appwidget.action.ActionCallback
import androidx.glance.appwidget.action.actionRunCallback
import androidx.glance.appwidget.action.actionStartActivity
import androidx.glance.appwidget.cornerRadius
import androidx.glance.appwidget.provideContent
import androidx.glance.background
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
import androidx.glance.unit.ColorProvider
import app.cursor.android.CursorApplication
import app.cursor.android.data.Connections
import app.cursor.android.data.Preferences
import app.cursor.android.system.UsageSyncWorker
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.first

private val ink = ColorProvider(Color(0xFFEDECEC))
private val muted = ColorProvider(Color(0xFFAAA79E))
private val surface = Color(0xFF14120B)
private val tile = Color(0xFF26241D)

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
        Column(
            GlanceModifier.fillMaxSize()
                .background(surface)
                .cornerRadius(24.dp)
                .padding(if (detailed) 14.dp else 10.dp)
                .clickable(actionStartActivity(WidgetDestination("usage").intent(context)))
        ) {
            Caption(state.text("USAGE", "用量") + " · " + state.metric())
            if (detailed || wide) {
                Spacer(GlanceModifier.height(6.dp))
                Row(GlanceModifier.fillMaxWidth()) {
                    if (state.preferences.cursor) {
                        Column(GlanceModifier.defaultWeight()) {
                            Caption("Cursor Model")
                            Value(state.value(true), detailed)
                        }
                    }
                    if (state.preferences.other) {
                        Column(GlanceModifier.defaultWeight()) {
                            Caption("Other Model")
                            Value(state.value(false), detailed)
                        }
                    }
                }
            } else {
                if (state.preferences.cursor) CompactPool("Cursor Model", state.value(true))
                if (state.preferences.other) CompactPool("Other Model", state.value(false))
            }
            Spacer(GlanceModifier.defaultWeight())
            Caption(state.usageStatus(System.currentTimeMillis()))
            if (detailed) {
                if (wide && state.preferences.pace && state.connections.web) {
                    val pace = state.usage?.pace(System.currentTimeMillis())
                    val reset = state.usage?.cycleEnd
                    if (pace != null) {
                        Caption(
                            state.text("Cycle target used", "周期目标已用") +
                                " ${pace.targetUsed.toInt()}%" +
                                if (pace.estimated) state.text(" · estimated", " · 估算") else ""
                        )
                    }
                    if (reset != null && state.usage?.unlimited != true) {
                        Caption(state.text("Reset ", "重置于 ") + WidgetState.time(reset))
                    }
                }
                Refresh(state)
            }
        }
    }
}

class AgentsWidget : CursorWidget() {
    override val sizeMode =
        SizeMode.Responsive(
            setOf(DpSize(160.dp, 180.dp), DpSize(320.dp, 180.dp), DpSize(320.dp, 260.dp))
        )

    @Composable
    override fun Content(state: WidgetState) {
        val context = LocalContext.current
        val rows = state.agentRows().take(if (LocalSize.current.height >= 260.dp) 3 else 1)
        Column(
            GlanceModifier.fillMaxSize().background(surface).cornerRadius(24.dp).padding(14.dp)
        ) {
            Text(
                state.text("Recent Agents", "最近会话"),
                GlanceModifier.fillMaxWidth()
                    .height(32.dp)
                    .clickable(actionStartActivity(WidgetDestination("inbox").intent(context))),
                style = TextStyle(color = ink, fontSize = 15.sp, fontWeight = FontWeight.Bold),
                maxLines = 1,
            )
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
            } else {
                rows.forEach { agent ->
                    Column(
                        GlanceModifier.fillMaxWidth()
                            .height(52.dp)
                            .background(tile)
                            .cornerRadius(12.dp)
                            .padding(horizontal = 10.dp, vertical = 5.dp)
                            .clickable(
                                actionStartActivity(
                                    (WidgetDestination.parse("detail", agent.id)
                                            ?: WidgetDestination("inbox"))
                                        .intent(context)
                                )
                            )
                    ) {
                        Text(
                            agent.title,
                            style = TextStyle(color = ink, fontSize = 14.sp),
                            maxLines = 1,
                        )
                        Caption(agent.status)
                    }
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
