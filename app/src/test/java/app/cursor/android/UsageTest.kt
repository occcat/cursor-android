package app.cursor.android

import app.cursor.android.domain.UsageSnapshot
import java.time.Instant
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class UsageTest {
    @Test fun exactPoolsAndNumericStringsRemainIndependent() {
        val json = Json.parseToJsonElement("""{
            "individualUsage":{"plan":{"autoPercentUsed":"32","apiPercentUsed":61,
            "used":999999,"limit":1}},"isUnlimited":false
        }""").jsonObject
        val usage = UsageSnapshot.fromJson(json, 42)
        assertEquals(68.0, usage.value(true, true)!!, 0.0)
        assertEquals(39.0, usage.value(false, true)!!, 0.0)
        assertEquals(32.0, usage.value(true, false)!!, 0.0)
        assertEquals(42, usage.fetchedAt)
    }

    @Test fun invalidPercentIsUnknownRatherThanZero() {
        listOf("", "NaN", "Infinity", "true", " 2", "3%", "0x20", "1e4").forEach {
            assertNull(UsageSnapshot.percent(JsonPrimitive(it)))
        }
        assertNull(UsageSnapshot.percent(JsonPrimitive(true)))
    }

    @Test fun partialUsageKeepsMissingSlotAndClampsDisplayOnly() {
        val usage = UsageSnapshot(cursorUsed = 130.0)
        assertEquals(0.0, usage.value(true, true)!!, 0.0)
        assertEquals(130.0, usage.cursorUsed!!, 0.0)
        assertNull(usage.value(false, true))
    }

    @Test fun unlimitedHasNoPaceOrResetWarning() {
        val usage = UsageSnapshot(unlimited = true, cycleEnd = 10)
        assertNull(usage.pace(20))
        assertFalse(usage.pendingReset(20))
    }

    @Test fun paceTargetsBillingDayEndAndThresholdIsStrict() {
        val start = Instant.parse("2026-10-01T12:00:00Z").toEpochMilli()
        val usage = UsageSnapshot(cycleStart = start, cycleEnd = start + 30 * UsageSnapshot.day)
        val pace = usage.pace(start)!!
        assertEquals(100.0 / 30, pace.targetUsed, 0.0001)
        assertEquals(0, pace.category(pace.targetUsed + 5))
        assertEquals(1, pace.category(pace.targetUsed + 5.01))
        assertEquals(-1, pace.category(pace.targetUsed - 5.01))
    }

    @Test fun expiredCyclePreservesOldValuesUntilServerReturnsNewCycle() {
        val usage = UsageSnapshot(cursorUsed = 32.0, cycleStart = 0,
            cycleEnd = 30 * UsageSnapshot.day)
        assertTrue(usage.pendingReset(31 * UsageSnapshot.day))
        assertEquals(68.0, usage.value(true, true)!!, 0.0)
        assertNull(usage.pace(31 * UsageSnapshot.day))
    }

    @Test fun invalidStartUsesPreviousCalendarMonthAndMarksEstimate() {
        val end = Instant.parse("2024-03-31T12:00:00Z").toEpochMilli()
        val now = Instant.parse("2024-02-29T12:00:00Z").toEpochMilli()
        val pace = UsageSnapshot(cycleEnd = end).pace(now)!!
        assertTrue(pace.estimated)
        assertEquals(100.0 / 31, pace.targetUsed, 0.0001)
        assertNull(UsageSnapshot(cycleEnd = end).pace(now - 1))
    }
}
