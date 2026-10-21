package app.cursor.android

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Flutter host activity. Registers the `app.cursor.android/overlay` channel that Dart
 * `OverlayBridge` uses to check and request the draw-over-other-apps permission.
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

    private companion object {
        const val OVERLAY_CHANNEL = "app.cursor.android/overlay"
    }
}
