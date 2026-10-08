package app.cursor.android.widget

import app.cursor.android.data.AgentSnapshot
import app.cursor.android.data.Connections
import app.cursor.android.data.Preferences
import app.cursor.android.data.string
import app.cursor.android.domain.UsageSnapshot
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import kotlin.math.roundToInt

/** Presentation values contain no credentials or raw account responses. */
data class WidgetState(
    val usage: UsageSnapshot?,
    val agents: AgentSnapshot?,
    val preferences: Preferences,
    val connections: Connections,
) {
    fun text(english: String, chinese: String) =
        if (preferences.language == "zh-CN") chinese else english

    fun metric() = if (preferences.remaining) text("Remaining", "剩余") else text("Used", "已用")

    fun value(cursor: Boolean): String =
        when {
            !connections.web || usage == null -> "—"
            usage.unlimited -> "∞"
            else -> usage.value(cursor, preferences.remaining)?.roundToInt()?.let { "$it%" } ?: "—"
        }

    fun usageStatus(now: Long): String =
        when {
            !preferences.cursor && !preferences.other -> text("Pools hidden", "模型用量已隐藏")
            !connections.web -> text("Connect web session", "连接网页会话")
            usage == null -> text("No snapshot yet", "暂无快照")
            usage.pendingReset(now) -> text("Awaiting reset · cached", "等待重置 · 缓存")
            now - usage.fetchedAt > staleAfter -> text("Stale · ", "已过期 · ") + time(usage.fetchedAt)
            preferences.paused -> text("Paused · ", "已暂停 · ") + time(usage.fetchedAt)
            else -> text("Updated ", "更新于 ") + time(usage.fetchedAt)
        }

    fun agentStatus(now: Long): String =
        when {
            !connections.api -> text("Connect API key", "连接 API Key")
            agents == null -> text("No snapshot yet", "暂无快照")
            now - agents.updatedAt > staleAfter ->
                text("Stale · ", "已过期 · ") + time(agents.updatedAt)
            else -> text("Updated ", "更新于 ") + time(agents.updatedAt)
        }

    fun agentRows(): List<WidgetAgent> =
        if (!connections.api) emptyList()
        else {
            agents?.agents.orEmpty().mapIndexed { index, agent ->
                WidgetAgent(
                    id = agent.string("id"),
                    title =
                        if (preferences.widgetTitles) {
                            agent.string("name").ifBlank { text("Agent", "会话") + " ${index + 1}" }
                        } else text("Agent", "会话") + " ${index + 1}",
                    status =
                        when (agent.string("status")) {
                            "ACTIVE" -> text("Active", "活跃")
                            "IDLE" -> text("Idle", "空闲")
                            "ARCHIVED" -> text("Archived", "已归档")
                            else -> text("Unknown", "未知")
                        },
                )
            }
        }

    companion object {
        const val staleAfter = 30 * 60 * 1000L

        fun time(timestamp: Long): String =
            DateTimeFormatter.ofPattern("MM-dd HH:mm")
                .withZone(ZoneId.systemDefault())
                .format(Instant.ofEpochMilli(timestamp))
    }
}

data class WidgetAgent(val id: String, val title: String, val status: String)
