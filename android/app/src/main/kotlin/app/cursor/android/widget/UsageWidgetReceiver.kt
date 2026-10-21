package app.cursor.android.widget

import es.antonborri.home_widget.HomeWidgetGlanceWidgetReceiver

/**
 * Receiver for [UsageGlanceWidget]. The class name must stay `UsageWidgetReceiver`: it matches
 * `WidgetHomeSync.defaultAndroidName` on the Flutter side.
 */
class UsageWidgetReceiver : HomeWidgetGlanceWidgetReceiver<UsageGlanceWidget>() {
    override val glanceAppWidget = UsageGlanceWidget()
}
