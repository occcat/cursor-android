package app.cursor.android.system

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import app.cursor.android.MainActivity
import app.cursor.android.R
import app.cursor.android.data.Preferences
import app.cursor.android.domain.UsageSnapshot
import app.cursor.android.ui.usageValue
import java.text.DateFormat
import java.util.Date

object UsageNotifications {
    const val channel = "cursor_usage"
    const val notificationId = 21
    const val overlayId = 22

    fun createChannels(context: Context) {
        val manager = context.getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(
            NotificationChannel(
                    channel,
                    context.getString(R.string.usage_channel),
                    NotificationManager.IMPORTANCE_LOW,
                )
                .apply {
                    description = context.getString(R.string.usage_description)
                    lockscreenVisibility = Notification.VISIBILITY_PRIVATE
                }
        )
    }

    fun build(
        context: Context,
        usage: UsageSnapshot?,
        preferences: Preferences,
        overlay: Boolean = false,
    ): Notification {
        val open =
            PendingIntent.getActivity(
                context,
                0,
                Intent(context, MainActivity::class.java),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        val refresh =
            PendingIntent.getBroadcast(
                context,
                1,
                Intent(context, UsageActionReceiver::class.java).setAction("refresh"),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        val stop =
            PendingIntent.getBroadcast(
                context,
                2,
                Intent(context, UsageActionReceiver::class.java).setAction("stop"),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        val mode =
            context.getString(if (preferences.remaining) R.string.remaining else R.string.used)
        val values = buildList {
            if (preferences.cursor)
                add("Cursor Model ${usageValue(usage, true, preferences.remaining)}")
            if (preferences.other)
                add("Other Model ${usageValue(usage, false, preferences.remaining)}")
        }
        val updated =
            usage
                ?.let {
                    context.getString(
                        R.string.updated,
                        DateFormat.getDateTimeInstance(DateFormat.SHORT, DateFormat.SHORT)
                            .format(Date(it.fetchedAt)),
                    )
                }
                .orEmpty()
        val pending =
            if (usage?.pendingReset(System.currentTimeMillis()) == true)
                context.getString(R.string.pending_reset)
            else ""
        val accent = context.getColor(R.color.cursor_accent)
        val publicVersion =
            NotificationCompat.Builder(context, channel)
                .setSmallIcon(R.drawable.ic_cursor)
                .setColor(accent)
                .setContentTitle("Cursor Android")
                .setContentText(context.getString(R.string.private_notification))
                .build()
        return NotificationCompat.Builder(context, channel)
            .setSmallIcon(R.drawable.ic_cursor)
            .setColor(accent)
            .setContentTitle("Cursor Usage · $mode")
            .setContentText(values.joinToString(" · "))
            .setStyle(
                NotificationCompat.BigTextStyle()
                    .bigText(
                        (values + listOf(updated, pending).filter(String::isNotBlank)).joinToString(
                            "\n"
                        )
                    )
            )
            .setContentIntent(open)
            .setOnlyAlertOnce(true)
            .setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
            .setPublicVersion(publicVersion)
            .setOngoing(overlay)
            .setShowWhen(false)
            .addAction(0, context.getString(R.string.refresh), refresh)
            .apply { if (overlay) addAction(0, context.getString(R.string.stop), stop) }
            .build()
    }

    fun update(context: Context, usage: UsageSnapshot?, preferences: Preferences) {
        if (
            !preferences.notifications ||
                usage == null ||
                (!preferences.cursor && !preferences.other)
        ) {
            cancel(context)
            return
        }
        if (
            Build.VERSION.SDK_INT >= 33 &&
                ContextCompat.checkSelfPermission(
                    context,
                    Manifest.permission.POST_NOTIFICATIONS,
                ) != PackageManager.PERMISSION_GRANTED
        )
            return
        context
            .getSystemService(NotificationManager::class.java)
            .notify(notificationId, build(context, usage, preferences))
    }

    fun cancel(context: Context) {
        context.getSystemService(NotificationManager::class.java).cancel(notificationId)
    }
}

class UsageActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == "stop") {
            context.stopService(Intent(context, UsageOverlayService::class.java))
        } else if (intent.action == "refresh") {
            UsageSyncWorker.refresh(context)
        }
    }
}
