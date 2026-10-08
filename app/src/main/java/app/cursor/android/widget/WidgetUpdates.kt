package app.cursor.android.widget

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import androidx.glance.appwidget.updateAll
import app.cursor.android.CursorApplication
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.launch

/** Cache/preferences drive every surface; Android owns the process and refresh schedule. */
object WidgetUpdates {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    fun observe(application: CursorApplication) {
        scope.launch {
            combine(
                    application.repository.usage,
                    application.repository.agentSnapshot,
                    application.settings.preferences,
                    application.repository.connections,
                ) { usage, agents, preferences, connections ->
                    WidgetState(usage, agents, preferences, connections)
                }
                .collectLatest { updateAll(application) }
        }
    }

    suspend fun updateAll(context: Context) {
        UsageWidget().updateAll(context)
        AgentsWidget().updateAll(context)
        ActionsWidget().updateAll(context)
    }

    fun hasAgents(context: Context): Boolean =
        AppWidgetManager.getInstance(context)
            .getAppWidgetIds(ComponentName(context, AgentsWidgetReceiver::class.java))
            .isNotEmpty()
}
