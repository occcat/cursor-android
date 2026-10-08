package app.cursor.android.widget

import android.content.Context
import android.content.Intent
import app.cursor.android.MainActivity

/** Only allow native destinations. Widget taps cannot launch a remote mutation or arbitrary URL. */
data class WidgetDestination(val screen: String, val agentId: String = "") {
    companion object {
        const val action = "app.cursor.android.OPEN_WIDGET"
        const val screenExtra = "widget_screen"
        const val agentExtra = "widget_agent"

        fun parse(screen: String?, id: String?): WidgetDestination? =
            when (screen) {
                "inbox",
                "create",
                "usage",
                "settings" -> WidgetDestination(screen)
                "detail" ->
                    id?.takeIf { it.matches(Regex("[A-Za-z0-9_-]{1,128}")) }
                        ?.let { WidgetDestination(screen, it) }
                else -> null
            }

        fun from(intent: Intent?): WidgetDestination? =
            if (intent?.action == action) {
                parse(intent.getStringExtra(screenExtra), intent.getStringExtra(agentExtra))
            } else null
    }

    fun intent(context: Context): Intent =
        Intent(context, MainActivity::class.java)
            .setAction(action)
            .putExtra(screenExtra, screen)
            .putExtra(agentExtra, agentId)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
}
