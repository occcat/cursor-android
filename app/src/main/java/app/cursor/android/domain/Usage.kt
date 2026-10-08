package app.cursor.android.domain

import java.time.Instant
import java.time.ZoneOffset
import kotlin.math.floor
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonObject

@Serializable
data class UsageSnapshot(
    val cursorUsed: Double? = null,
    val otherUsed: Double? = null,
    val cycleStart: Long? = null,
    val cycleEnd: Long? = null,
    val unlimited: Boolean = false,
    val membership: String? = null,
    val fetchedAt: Long = 0,
) {
    fun value(cursor: Boolean, remaining: Boolean): Double? {
        val used = (if (cursor) cursorUsed else otherUsed)?.coerceIn(0.0, 100.0)
        return used?.let { if (remaining) 100.0 - it else it }
    }

    fun pendingReset(now: Long): Boolean = !unlimited && cycleEnd?.let { now >= it } == true

    fun pace(now: Long): Pace? {
        if (unlimited) return null
        val end = cycleEnd ?: return null
        val validStart = cycleStart?.takeIf { end - it in day..32 * day }
        val start = validStart ?: Instant.ofEpochMilli(end).atZone(ZoneOffset.UTC)
            .minusMonths(1).toInstant().toEpochMilli()
        if (now < start || now >= end || end <= start) return null
        val target = ((floor((now - start).toDouble() / day) + 1) * day / (end - start))
            .coerceIn(0.0, 1.0) * 100.0
        return Pace(target, validStart == null)
    }

    companion object {
        const val day = 86_400_000L

        fun fromJson(root: JsonObject, now: Long): UsageSnapshot {
            val plan = (root["individualUsage"] as? JsonObject)?.get("plan") as? JsonObject
            return UsageSnapshot(
                cursorUsed = percent(plan?.get("autoPercentUsed")),
                otherUsed = percent(plan?.get("apiPercentUsed")),
                cycleStart = timestamp(root["billingCycleStart"]),
                cycleEnd = timestamp(root["billingCycleEnd"]),
                unlimited = (root["isUnlimited"] as? JsonPrimitive)?.booleanOrNull == true,
                membership = (root["membershipType"] as? JsonPrimitive)?.contentOrNull,
                fetchedAt = now,
            )
        }

        fun percent(element: JsonElement?): Double? {
            val text = (element as? JsonPrimitive)?.contentOrNull ?: return null
            if (!Regex("[+-]?(?:[0-9]+(?:\\.[0-9]*)?|\\.[0-9]+)").matches(text)) return null
            return text.toDoubleOrNull()?.takeIf { it.isFinite() }
        }

        private fun timestamp(element: JsonElement?): Long? {
            val value = (element as? JsonPrimitive)?.contentOrNull ?: return null
            return runCatching { Instant.parse(value).toEpochMilli() }.getOrNull()
        }
    }
}

data class Pace(val targetUsed: Double, val estimated: Boolean) {
    fun category(used: Double): Int = when {
        used - targetUsed > 5 -> 1
        used - targetUsed < -5 -> -1
        else -> 0
    }
}
