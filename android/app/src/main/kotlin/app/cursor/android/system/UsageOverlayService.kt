package app.cursor.android.system

import android.annotation.SuppressLint
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.os.IBinder
import android.provider.Settings
import android.util.TypedValue
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.view.WindowManager
import android.widget.TextView
import app.cursor.android.MainActivity
import es.antonborri.home_widget.HomeWidgetPlugin
import kotlin.math.abs

/**
 * Foreground service showing a draggable usage capsule over other apps. The text comes from the
 * `usage.*` keys that Flutter `WidgetHomeSync` writes through home_widget and refreshes when they
 * change; tapping the capsule opens [MainActivity].
 */
class UsageOverlayService : Service() {
    private var windowManager: WindowManager? = null
    private var data: SharedPreferences? = null
    private var capsule: TextView? = null
    private val params =
        WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
            PixelFormat.TRANSLUCENT,
        ).apply { gravity = Gravity.TOP or Gravity.START }
    private val dataListener =
        SharedPreferences.OnSharedPreferenceChangeListener { _, _ -> refresh() }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        // Promote first: a service started with startForegroundService must call startForeground
        // even when it stops right away.
        startForeground(NOTIFICATION_ID, notification())
        if (!Settings.canDrawOverlays(this)) {
            stopSelf()
            return
        }
        windowManager = getSystemService(WindowManager::class.java)
        val prefs = HomeWidgetPlugin.getData(this)
        prefs.registerOnSharedPreferenceChangeListener(dataListener)
        data = prefs
        showCapsule()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        refresh()
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        data?.unregisterOnSharedPreferenceChangeListener(dataListener)
        data = null
        capsule?.let { view -> windowManager?.removeView(view) }
        capsule = null
        stopForeground(STOP_FOREGROUND_REMOVE)
        super.onDestroy()
    }

    @SuppressLint("ClickableViewAccessibility")
    private fun showCapsule() {
        val manager = windowManager ?: return
        val horizontal = dp(14)
        val vertical = dp(8)
        val view =
            TextView(this).apply {
                setTextColor(Color.WHITE)
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
                setPadding(horizontal, vertical, horizontal, vertical)
                background =
                    GradientDrawable().apply {
                        setColor(CAPSULE_COLOR)
                        cornerRadius = dp(20).toFloat()
                    }
                setOnClickListener { openApp() }
                setOnTouchListener(DragListener())
            }
        val metrics = resources.displayMetrics
        val position = getSharedPreferences(POSITION_PREFS, Context.MODE_PRIVATE)
        params.x = (position.getFloat(KEY_X, DEFAULT_X) * metrics.widthPixels).toInt()
        params.y = (position.getFloat(KEY_Y, DEFAULT_Y) * metrics.heightPixels).toInt()
        capsule = view
        refresh()
        manager.addView(view, params)
    }

    /** Shows "Cursor X  ·  Other Y" for the visible pools, or a dash when both are hidden. */
    private fun refresh() {
        val view = capsule ?: return
        val prefs = data ?: return
        val parts =
            buildList {
                if (prefs.getBoolean(KEY_SHOW_CURSOR, true)) {
                    add("Cursor ${prefs.getString(KEY_CURSOR, null) ?: PLACEHOLDER}")
                }
                if (prefs.getBoolean(KEY_SHOW_OTHER, true)) {
                    add("Other ${prefs.getString(KEY_OTHER, null) ?: PLACEHOLDER}")
                }
            }
        view.text = if (parts.isEmpty()) PLACEHOLDER else parts.joinToString(SEPARATOR)
    }

    private fun savePosition() {
        val metrics = resources.displayMetrics
        val x = (params.x.toFloat() / metrics.widthPixels).coerceIn(0f, 1f)
        val y = (params.y.toFloat() / metrics.heightPixels).coerceIn(0f, 1f)
        getSharedPreferences(POSITION_PREFS, Context.MODE_PRIVATE)
            .edit()
            .putFloat(KEY_X, x)
            .putFloat(KEY_Y, y)
            .apply()
    }

    private fun openApp() {
        startActivity(launchIntent())
    }

    private fun launchIntent(): Intent =
        Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)

    private fun notification(): Notification {
        val manager = getSystemService(NotificationManager::class.java)
        if (manager.getNotificationChannel(CHANNEL_ID) == null) {
            val channel =
                NotificationChannel(CHANNEL_ID, TITLE, NotificationManager.IMPORTANCE_LOW)
            manager.createNotificationChannel(channel)
        }
        val open =
            PendingIntent.getActivity(
                this,
                0,
                launchIntent(),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
        return Notification.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle(TITLE)
            .setContentText("Floating usage capsule is on")
            .setContentIntent(open)
            .setOngoing(true)
            .build()
    }

    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()

    /** Moves the capsule while dragging; a touch without movement counts as a click. */
    private inner class DragListener : View.OnTouchListener {
        private val touchSlop = ViewConfiguration.get(this@UsageOverlayService).scaledTouchSlop
        private var startX = 0
        private var startY = 0
        private var downX = 0f
        private var downY = 0f
        private var dragging = false

        override fun onTouch(view: View, event: MotionEvent): Boolean {
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    startX = params.x
                    startY = params.y
                    downX = event.rawX
                    downY = event.rawY
                    dragging = false
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = event.rawX - downX
                    val dy = event.rawY - downY
                    if (!dragging && (abs(dx) > touchSlop || abs(dy) > touchSlop)) {
                        dragging = true
                    }
                    if (dragging) {
                        params.x = startX + dx.toInt()
                        params.y = startY + dy.toInt()
                        windowManager?.updateViewLayout(view, params)
                    }
                }
                MotionEvent.ACTION_UP -> {
                    if (dragging) {
                        savePosition()
                    } else {
                        view.performClick()
                    }
                }
            }
            return true
        }
    }

    private companion object {
        const val CHANNEL_ID = "cursor_overlay"
        const val TITLE = "Cursor usage"
        const val NOTIFICATION_ID = 1001
        const val POSITION_PREFS = "overlay_position"
        const val KEY_X = "x"
        const val KEY_Y = "y"
        const val DEFAULT_X = 0.05f
        const val DEFAULT_Y = 0.2f
        const val KEY_CURSOR = "usage.cursor"
        const val KEY_OTHER = "usage.other"
        const val KEY_SHOW_CURSOR = "usage.showCursor"
        const val KEY_SHOW_OTHER = "usage.showOther"
        const val PLACEHOLDER = "—"
        const val SEPARATOR = "  ·  "
        val CAPSULE_COLOR = Color.argb(230, 26, 26, 26)
    }
}
