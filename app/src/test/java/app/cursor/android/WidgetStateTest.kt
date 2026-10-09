package app.cursor.android

import app.cursor.android.data.AgentSnapshot
import app.cursor.android.data.Connections
import app.cursor.android.data.Preferences
import app.cursor.android.domain.UsageSnapshot
import app.cursor.android.widget.WidgetDestination
import app.cursor.android.widget.WidgetState
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class WidgetStateTest {
    private val now = 1_790_000_000_000L
    private val usage = UsageSnapshot(cursorUsed = 32.0, otherUsed = 61.0, fetchedAt = now)

    private fun state(
        snapshot: UsageSnapshot? = usage,
        preferences: Preferences = Preferences(),
        connected: Boolean = true,
    ) = WidgetState(snapshot, null, preferences, Connections(connected))

    @Test
    fun valuesUseSharedMetricAndNeverTreatUnknownAsZero() {
        assertEquals("68%", state().value(true))
        assertEquals("61%", state(preferences = Preferences(remaining = false)).value(false))
        assertEquals("—", state(usage.copy(cursorUsed = null)).value(true))
        assertEquals("∞", state(usage.copy(unlimited = true)).value(false))
        assertEquals("—", state(usage.copy(unlimited = true), connected = false).value(false))
    }

    @Test
    fun disabledAndExpiredStatesDoNotPretendToHaveCurrentUsage() {
        assertEquals(
            "Pools hidden",
            state(preferences = Preferences(cursor = false, other = false)).usageStatus(now),
        )
        assertEquals("Connect web session", state(connected = false).usageStatus(now))
        assertEquals("—", state(connected = false).value(true))
        assertEquals("No snapshot yet", state(null).usageStatus(now))
        assertTrue(state().usageStatus(now + 1_800_001).startsWith("Stale"))
        assertTrue(
            state(usage.copy(cycleEnd = now - 1)).usageStatus(now).contains("Awaiting reset")
        )
        assertTrue(
            state(preferences = Preferences(language = "zh-CN")).usageStatus(now).startsWith("更新于")
        )
    }

    @Test
    fun cachedAgentRowsPreserveAgentStatusAndHideTitlesByDefault() {
        val agent =
            Json.parseToJsonElement(
                """{"bcId":"bc-a","name":"Private project","status":"ACTIVE"}"""
            )
                .jsonObject
        val state =
            WidgetState(
                null,
                AgentSnapshot(listOf(agent), now),
                Preferences(),
                Connections(true),
            )
        assertEquals("Agent 1", state.agentRows().single().title)
        assertEquals("Active", state.agentRows().single().status)
        assertFalse(state.agentStatus(now).contains("1970"))
        assertEquals(
            "Private project",
            state.copy(preferences = Preferences(widgetTitles = true)).agentRows().single().title,
        )
        assertTrue(state.copy(connections = Connections(false)).agentRows().isEmpty())
    }

    @Test
    fun destinationsRejectExternalRoutesAndMalformedIdentifiers() {
        assertEquals("create", WidgetDestination.parse("create", null)?.screen)
        assertEquals("bc-safe_1", WidgetDestination.parse("detail", "bc-safe_1")?.agentId)
        assertNull(WidgetDestination.parse("https://evil.example", null))
        assertNull(WidgetDestination.parse("detail", "../secret"))
        assertNull(WidgetDestination.parse("detail", ""))
    }
}
