package app.cursor.android

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.provider.Settings
import app.cursor.android.system.UsageOverlayService
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Flutter host activity. Registers the `app.cursor.android/overlay` channel that Dart
 * `OverlayBridge` uses to check the draw-over-other-apps permission and to start or stop
 * [UsageOverlayService].
 */
class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, OVERLAY_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "canDrawOverlays" -> result.success(Settings.canDrawOverlays(this))
                    "openOverlaySettings" ->
                        try {
                            openOverlaySettings()
                            result.success(null)
                        } catch (error: ActivityNotFoundException) {
                            result.error("unavailable", error.message, null)
                        }
                    "startOverlay" ->
                        if (Settings.canDrawOverlays(this)) {
                            startForegroundService(overlayIntent())
                            result.success(null)
                        } else {
                            result.error("permission", "Display over other apps is off", null)
                        }
                    "stopOverlay" -> {
                        stopService(overlayIntent())
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /** Opens this app's "display over other apps" settings screen. */
    private fun openOverlaySettings() {
        val intent =
            Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:$packageName"))
        startActivity(intent)
    }

    private fun overlayIntent(): Intent = Intent(this, UsageOverlayService::class.java)

    private companion object {
        const val OVERLAY_CHANNEL = "app.cursor.android/overlay"
    }
}
