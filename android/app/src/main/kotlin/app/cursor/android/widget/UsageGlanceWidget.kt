package app.cursor.android.widget

import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.provideContent
import androidx.glance.background
import androidx.glance.currentState
import androidx.glance.layout.Alignment
import androidx.glance.layout.Column
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import androidx.glance.unit.ColorProvider
import app.cursor.android.MainActivity
import es.antonborri.home_widget.HomeWidgetGlanceState
import es.antonborri.home_widget.HomeWidgetGlanceStateDefinition
import es.antonborri.home_widget.HomeWidgetPlugin
import es.antonborri.home_widget.actionStartActivity

/**
 * Usage pool Glance widget. Reads the `usage.*` keys that Flutter `WidgetHomeSync` writes
 * through home_widget; tapping it opens [MainActivity].
 */
class UsageGlanceWidget : GlanceAppWidget() {
    override val stateDefinition = HomeWidgetGlanceStateDefinition()

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        provideContent { Content(context, currentState()) }
    }

    override suspend fun providePreview(context: Context, widgetCategory: Int) {
        val preferences =
            context.getSharedPreferences(HomeWidgetPlugin.PREFERENCES, Context.MODE_PRIVATE)
        provideContent {
            Content(context, HomeWidgetGlanceState(preferences), preview = true)
        }
    }

    @Composable
    private fun Content(
        context: Context,
        state: HomeWidgetGlanceState,
        preview: Boolean = false,
    ) {
        val prefs = state.preferences
        val metric = prefs.getString(KEY_METRIC, null) ?: "Usage"
        val status = prefs.getString(KEY_STATUS, null) ?: PLACEHOLDER
        val cursor = prefs.getString(KEY_CURSOR, null) ?: if (preview) "68%" else PLACEHOLDER
        val other = prefs.getString(KEY_OTHER, null) ?: if (preview) "∞" else PLACEHOLDER
        val showCursor = prefs.getBoolean(KEY_SHOW_CURSOR, true)
        val showOther = prefs.getBoolean(KEY_SHOW_OTHER, true)

        Column(
            modifier =
                GlanceModifier.fillMaxSize()
                    .background(BACKGROUND)
                    .padding(12.dp)
                    .clickable(actionStartActivity<MainActivity>(context)),
            verticalAlignment = Alignment.Top,
            horizontalAlignment = Alignment.Start,
        ) {
            Text(metric, style = textStyle(PRIMARY, 12.sp))
            Spacer(GlanceModifier.height(4.dp))
            Text(status, style = textStyle(SECONDARY, 11.sp))
            Spacer(GlanceModifier.height(8.dp))
            Row(modifier = GlanceModifier.fillMaxWidth()) {
                if (showCursor) {
                    Text("Cursor $cursor", style = textStyle(CURSOR, 14.sp, FontWeight.Bold))
                }
                if (showCursor && showOther) {
                    Text("  ·  ", style = textStyle(DIVIDER, 14.sp))
                }
                if (showOther) {
                    Text("Other $other", style = textStyle(OTHER, 14.sp, FontWeight.Bold))
                }
            }
        }
    }

    private fun textStyle(color: Color, size: TextUnit, weight: FontWeight? = null): TextStyle =
        TextStyle(color = ColorProvider(color), fontSize = size, fontWeight = weight)

    private companion object {
        const val KEY_METRIC = "usage.metric"
        const val KEY_STATUS = "usage.status"
        const val KEY_CURSOR = "usage.cursor"
        const val KEY_OTHER = "usage.other"
        const val KEY_SHOW_CURSOR = "usage.showCursor"
        const val KEY_SHOW_OTHER = "usage.showOther"
        const val PLACEHOLDER = "—"

        val BACKGROUND = Color(0xFF1A1A1A)
        val PRIMARY = Color.White
        val SECONDARY = Color(0xFFB0B0B0)
        val CURSOR = Color(0xFF7DD3FC)
        val OTHER = Color(0xFFFBBF24)
        val DIVIDER = Color(0xFF666666)
    }
}
