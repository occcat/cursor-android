package app.cursor.android.system

import android.app.Service
import android.content.Intent
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.os.IBinder
import android.provider.Settings
import android.view.Gravity
import android.view.MotionEvent
import android.view.ViewConfiguration
import android.view.WindowManager
import android.widget.TextView
import app.cursor.android.CursorApplication
import app.cursor.android.MainActivity
import app.cursor.android.data.Preferences
import app.cursor.android.ui.usageValue
import kotlin.math.abs
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.launch

/** Visible user-controlled special-use overlay; network refresh belongs to WorkManager. */
class UsageOverlayService : Service() {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private var capsule: TextView? = null
    private lateinit var windows: WindowManager

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        startForeground(UsageNotifications.overlayId,
            UsageNotifications.build(this, null, Preferences(), overlay = true))
        if (!Settings.canDrawOverlays(this)) {
            stopSelf()
            return
        }
        windows = getSystemService(WindowManager::class.java)
        val density = resources.displayMetrics.density
        val position = getSharedPreferences("overlay_position", MODE_PRIVATE)
        val bounds = resources.displayMetrics
        val layout = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = (position.getFloat("x", 0.3f) * bounds.widthPixels).toInt()
            y = (position.getFloat("y", 0.65f) * bounds.heightPixels).toInt()
        }
        val view = TextView(this).apply {
            textSize = 13f
            setTextColor(Color.rgb(240, 240, 240))
            setPadding((16 * density).toInt(), (14 * density).toInt(),
                (16 * density).toInt(), (14 * density).toInt())
            background = GradientDrawable().apply {
                setColor(Color.rgb(24, 24, 24))
                cornerRadius = 28 * density
                setStroke((density).toInt().coerceAtLeast(1), Color.rgb(75, 75, 75))
            }
            contentDescription = "Cursor Usage"
            setOnClickListener {
                startActivity(Intent(this@UsageOverlayService, MainActivity::class.java)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            }
        }
        var startX = 0f
        var startY = 0f
        var originX = 0
        var originY = 0
        var dragging = false
        val slop = ViewConfiguration.get(this).scaledTouchSlop
        view.setOnTouchListener { _, event ->
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    startX = event.rawX; startY = event.rawY
                    originX = layout.x; originY = layout.y; dragging = false
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = event.rawX - startX
                    val dy = event.rawY - startY
                    dragging = dragging || abs(dx) > slop || abs(dy) > slop
                    if (dragging) {
                        layout.x = (originX + dx).toInt().coerceIn(0,
                            (bounds.widthPixels - view.width).coerceAtLeast(0))
                        layout.y = (originY + dy).toInt().coerceIn(0,
                            (bounds.heightPixels - view.height).coerceAtLeast(0))
                        runCatching { windows.updateViewLayout(view, layout) }.onFailure { stopSelf() }
                    }
                    true
                }
                MotionEvent.ACTION_UP -> {
                    if (!dragging) view.performClick()
                    position.edit().putFloat("x", layout.x.toFloat() / bounds.widthPixels)
                        .putFloat("y", layout.y.toFloat() / bounds.heightPixels).apply()
                    true
                }
                else -> false
            }
        }
        try {
            windows.addView(view, layout)
            capsule = view
        } catch (_: RuntimeException) {
            stopSelf()
            return
        }
        val container = application as CursorApplication
        scope.launch {
            combine(container.repository.usage, container.settings.preferences) { usage, preferences ->
                usage to preferences
            }.collect { (usage, preferences) ->
                if (!Settings.canDrawOverlays(this@UsageOverlayService) || usage == null ||
                    (!preferences.cursor && !preferences.other)) {
                    stopSelf()
                } else {
                    view.text = buildList {
                        if (preferences.cursor) add("Cursor ${usageValue(usage, true, preferences.remaining)}")
                        if (preferences.other) add("Other ${usageValue(usage, false, preferences.remaining)}")
                    }.joinToString("  ·  ") + "\n" + getString(
                        if (preferences.remaining) app.cursor.android.R.string.remaining
                        else app.cursor.android.R.string.used,
                    )
                    view.contentDescription = view.text
                    getSystemService(android.app.NotificationManager::class.java).notify(
                        UsageNotifications.overlayId,
                        UsageNotifications.build(this@UsageOverlayService, usage, preferences, true),
                    )
                }
            }
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int = START_NOT_STICKY

    override fun onDestroy() {
        scope.cancel()
        capsule?.let { runCatching { windows.removeView(it) } }
        capsule = null
        stopForeground(STOP_FOREGROUND_REMOVE)
        super.onDestroy()
    }
}
