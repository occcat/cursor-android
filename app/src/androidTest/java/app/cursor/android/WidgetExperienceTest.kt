package app.cursor.android

import android.app.Instrumentation
import android.appwidget.AppWidgetHost
import android.appwidget.AppWidgetHostView
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.graphics.Bitmap
import android.os.Bundle
import android.os.LocaleList
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import androidx.glance.appwidget.ExperimentalGlanceRemoteViewsApi
import androidx.glance.appwidget.GlanceRemoteViews
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.runner.lifecycle.ActivityLifecycleMonitorRegistry
import androidx.test.runner.lifecycle.Stage
import app.cursor.android.data.AgentSnapshot
import app.cursor.android.data.Connections
import app.cursor.android.data.Preferences
import app.cursor.android.domain.UsageSnapshot
import app.cursor.android.widget.ActionsWidget
import app.cursor.android.widget.ActionsWidgetReceiver
import app.cursor.android.widget.AgentsWidget
import app.cursor.android.widget.AgentsWidgetReceiver
import app.cursor.android.widget.CursorWidget
import app.cursor.android.widget.UsageWidget
import app.cursor.android.widget.UsageWidgetReceiver
import app.cursor.android.widget.WidgetDestination
import app.cursor.android.widget.WidgetState
import java.io.File
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

@OptIn(ExperimentalGlanceRemoteViewsApi::class)
class WidgetExperienceTest {
    @get:Rule val compose = createEmptyComposeRule()
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context = instrumentation.targetContext
    private val now = System.currentTimeMillis()
    private val state =
        WidgetState(
            UsageSnapshot(
                cursorUsed = 32.0,
                otherUsed = 61.0,
                fetchedAt = now,
                cycleStart = now - 10 * UsageSnapshot.day,
                cycleEnd = now + 20 * UsageSnapshot.day,
            ),
            AgentSnapshot(
                listOf(
                    Json.parseToJsonElement(
                            """{"id":"bc-a","name":"Private title","status":"ACTIVE"}"""
                        )
                        .jsonObject,
                    Json.parseToJsonElement(
                            """{"id":"bc-b","name":"Another title","status":"IDLE"}"""
                        )
                        .jsonObject,
                    Json.parseToJsonElement(
                            """{"id":"bc-c","name":"Archived title","status":"ARCHIVED"}"""
                        )
                        .jsonObject,
                ),
                now,
            ),
            Preferences(),
            Connections(true),
        )

    @Test
    fun realRemoteViewsRenderUsageSizesAndHonestStates() = runBlocking {
        ActivityScenario.launch(WidgetQaActivity::class.java).use { scenario ->
            for ((width, height) in listOf(160 to 80, 320 to 80, 160 to 180, 320 to 180)) {
                val views =
                    render(
                        scenario,
                        UsageWidget(),
                        width,
                        height,
                        state,
                        "Usage ${width}×${height}dp · synthetic fixture",
                    )
                assertTrue(views.any { it.text.toString() == "68%" })
                assertTrue(views.any { it.text.toString() == "39%" })
                assertTextFits(views, views.map { it.text.toString() }.toSet())
                screenshot("usage-${width}x${height}")
            }
            val expired =
                render(
                    scenario,
                    UsageWidget(),
                    320,
                    180,
                    state.copy(connections = Connections(false)),
                    "Expired session fixture",
                )
            assertFalse(expired.any { it.text.toString().contains("68%") })
            assertTrue(expired.any { it.text.toString() == "Connect web session" })
            screenshot("usage-expired")
            val hidden =
                render(
                    scenario,
                    UsageWidget(),
                    160,
                    80,
                    state.copy(preferences = Preferences(cursor = false, other = false)),
                    "Hidden pools fixture",
                )
            assertTrue(hidden.any { it.text.toString() == "Pools hidden" })
            val unlimited =
                render(
                    scenario,
                    UsageWidget(),
                    320,
                    180,
                    state.copy(usage = state.usage!!.copy(unlimited = true)),
                    "Unlimited fixture",
                )
            assertEquals(2, unlimited.count { it.text.toString() == "∞" })
            val chinese =
                render(
                    scenario,
                    UsageWidget(),
                    320,
                    180,
                    state.copy(preferences = Preferences(language = "zh-CN", remaining = false)),
                    "用量 · 合成测试数据",
                )
            assertTrue(chinese.any { it.text.toString() == "用量 · 已用" })
            assertTrue(chinese.any { it.text.toString() == "32%" })
            screenshot("usage-chinese")
        }
    }

    @Test
    fun agentsAndActionsRenderPrivateTitlesAndExpectedSizeActions() = runBlocking {
        ActivityScenario.launch(WidgetQaActivity::class.java).use { scenario ->
            val agents =
                render(
                    scenario,
                    AgentsWidget(),
                    320,
                    300,
                    state,
                    "Recent Agents · synthetic fixture",
                )
            assertTrue(agents.any { it.text.toString() == "Agent 1" })
            assertTrue(agents.any { it.text.toString() == "Active" })
            assertTrue(agents.any { it.text.toString() == "Agent 3" })
            assertFalse(agents.any { it.text.toString().contains("Private title") })
            assertTextFits(agents, agents.map { it.text.toString() }.toSet())
            screenshot("agents-private")
            val wideAgents =
                render(
                    scenario,
                    AgentsWidget(),
                    320,
                    180,
                    state,
                    "Recent Agents · wide synthetic fixture",
                )
            assertEquals(2, wideAgents.count { it.text.toString().startsWith("Agent ") })
            assertTextFits(wideAgents, wideAgents.map { it.text.toString() }.toSet())
            screenshot("agents-wide")
            val compact =
                render(scenario, ActionsWidget(), 160, 80, state, "Quick Actions · compact")
            assertTrue(compact.any { it.text.toString() == "Inbox" })
            assertTrue(compact.any { it.text.toString() == "New Agent" })
            assertFalse(compact.any { it.text.toString() == "Settings" })
            screenshot("actions-compact")
            val wide = render(scenario, ActionsWidget(), 320, 80, state, "Quick Actions · wide")
            assertTrue(wide.any { it.text.toString() == "Usage" })
            assertTrue(wide.any { it.text.toString() == "Settings" })
            assertTextFits(wide, setOf("Inbox", "New Agent", "Usage", "Settings"))
            screenshot("actions-wide")
        }
    }

    @Test
    fun installedProvidersBindAndResizeInRealHost() = runBlocking {
        val manager = AppWidgetManager.getInstance(context)
        val providers =
            listOf(
                UsageWidgetReceiver::class.java,
                AgentsWidgetReceiver::class.java,
                ActionsWidgetReceiver::class.java,
            )
        val host = AppWidgetHost(context, 9184)
        instrumentation.uiAutomation.adoptShellPermissionIdentity(
            "android.permission.BIND_APPWIDGET"
        )
        try {
            providers.forEach { receiver ->
                val component = ComponentName(context, receiver)
                val info = manager.installedProviders.single { it.provider == component }
                assertTrue(info.previewImage != 0)
                assertTrue(info.previewLayout != 0)
                assertEquals(0, info.updatePeriodMillis)
                val id = host.allocateAppWidgetId()
                assertTrue(manager.bindAppWidgetIdIfAllowed(id, component))
                val options =
                    Bundle().apply {
                        putInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 160)
                        putInt(AppWidgetManager.OPTION_APPWIDGET_MAX_WIDTH, 320)
                        putInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 180)
                        putInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT, 260)
                    }
                manager.updateAppWidgetOptions(id, options)
                assertNotNull(manager.getAppWidgetInfo(id))
                assertEquals(
                    320,
                    manager
                        .getAppWidgetOptions(id)
                        .getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_WIDTH),
                )
                host.deleteAppWidgetId(id)
            }
        } finally {
            host.deleteHost()
            instrumentation.uiAutomation.dropShellPermissionIdentity()
        }
    }

    @Test
    fun largerTextAndDifferentOsLocalePreserveReadableEnglishDefaults() = runBlocking {
        shell("settings put system font_scale 1.3")
        try {
            ActivityScenario.launch(WidgetQaActivity::class.java).use { scenario ->
                val configuration =
                    android.content.res.Configuration(context.resources.configuration)
                configuration.setLocales(LocaleList.forLanguageTags("zh-CN"))
                val chineseContext = context.createConfigurationContext(configuration)
                for ((width, height) in listOf(160 to 80, 320 to 80, 160 to 180, 320 to 180)) {
                    val views =
                        render(
                            scenario,
                            UsageWidget(),
                            width,
                            height,
                            state,
                            "Larger text · English preference · Chinese OS context",
                            chineseContext,
                        )
                    screenshot("large-text-${width}x${height}")
                    assertTrue(
                        views.any {
                            it.text.toString() == "USAGE · Remaining" ||
                                it.text.toString().startsWith("Left · ")
                        }
                    )
                    assertTextFits(views, views.map { it.text.toString() }.toSet())
                }
                val agents =
                    render(scenario, AgentsWidget(), 320, 180, state, "Recent Agents · larger text")
                assertTextFits(agents, agents.map { it.text.toString() }.toSet())
                val actions =
                    render(scenario, ActionsWidget(), 160, 80, state, "Quick Actions · larger text")
                assertTextFits(actions, setOf("Inbox", "New Agent"))
                screenshot("actions-large-text")
            }
        } finally {
            shell("settings put system font_scale 1.0")
        }
    }

    @Test
    fun actualWidgetPendingIntentsOpenColdAndWarmNativeDestinations() = runBlocking {
        val monitor = Instrumentation.ActivityMonitor(MainActivity::class.java.name, null, false)
        instrumentation.addMonitor(monitor)
        try {
            ActivityScenario.launch(WidgetQaActivity::class.java).use { scenario ->
                val actions =
                    render(
                        scenario,
                        ActionsWidget(),
                        320,
                        80,
                        state,
                        "Real PendingIntent navigation",
                    )
                click(actions.single { it.text.toString() == "New Agent" })
                val activity = monitor.waitForActivityWithTimeout(5_000) as MainActivity
                instrumentation.waitForIdleSync()
                assertEquals(
                    "create",
                    activity.intent.getStringExtra(WidgetDestination.screenExtra),
                )
                for ((label, destination) in
                    listOf("Usage" to "usage", "Settings" to "settings", "Inbox" to "inbox")) {
                    click(actions.single { it.text.toString() == label })
                    waitForIntent(destination, "")
                }
                val agents =
                    render(
                        scenario,
                        AgentsWidget(),
                        320,
                        180,
                        state,
                        "Real agent PendingIntent navigation",
                    )
                click(agents.single { it.text.toString() == "Agent 1" })
                waitForIntent("detail", "bc-a")
                click(agents.single { it.text.toString() == "Agent 2" })
                waitForIntent("detail", "bc-b")
                instrumentation.runOnMainSync {
                    ActivityLifecycleMonitorRegistry.getInstance()
                        .getActivitiesInStage(Stage.RESUMED)
                        .filterIsInstance<MainActivity>()
                        .forEach { it.finish() }
                }
            }
        } finally {
            instrumentation.removeMonitor(monitor)
        }
    }

    private fun waitForIntent(screen: String, id: String) {
        val deadline = System.currentTimeMillis() + 5_000
        var matched = false
        while (!matched && System.currentTimeMillis() < deadline) {
            instrumentation.runOnMainSync {
                matched =
                    ActivityLifecycleMonitorRegistry.getInstance()
                        .getActivitiesInStage(Stage.RESUMED)
                        .filterIsInstance<MainActivity>()
                        .any {
                            it.intent.getStringExtra(WidgetDestination.screenExtra) == screen &&
                                it.intent.getStringExtra(WidgetDestination.agentExtra) == id
                        }
            }
            if (!matched) Thread.sleep(50)
        }
        assertTrue("Widget did not navigate to $screen/$id", matched)
        instrumentation.waitForIdleSync()
        val expected =
            when (screen) {
                "usage" -> "Cursor Usage"
                "settings" -> "Make it yours."
                "inbox" -> "Your work."
                "detail" -> "Loading this workspace"
                else -> "Describe a task"
            }
        compose.waitUntil(5_000) {
            compose
                .onAllNodesWithText(expected, substring = true)
                .fetchSemanticsNodes()
                .isNotEmpty()
        }
    }

    private fun click(text: TextView) {
        instrumentation.runOnMainSync {
            var target: View = text
            while (!target.isClickable && target.parent is View) target = target.parent as View
            assertTrue("Missing widget click target", target.performClick())
        }
        instrumentation.waitForIdleSync()
    }

    private fun shell(command: String) {
        instrumentation.uiAutomation.executeShellCommand(command).use { descriptor ->
            android.os.ParcelFileDescriptor.AutoCloseInputStream(descriptor).readBytes()
        }
    }

    @Test
    fun registeredUsageWidgetObservesPersistedLanguageAndPoolChanges() = runBlocking {
        val application = context.applicationContext as CursorApplication
        val manager = AppWidgetManager.getInstance(context)
        val host = AppWidgetHost(context, 9185)
        instrumentation.uiAutomation.adoptShellPermissionIdentity(
            "android.permission.BIND_APPWIDGET"
        )
        try {
            application.settings.language("en")
            application.repository.disconnect()
            ActivityScenario.launch(WidgetQaActivity::class.java).use { scenario ->
                val component = ComponentName(context, UsageWidgetReceiver::class.java)
                val info = manager.installedProviders.single { it.provider == component }
                val id = host.allocateAppWidgetId()
                assertTrue(manager.bindAppWidgetIdIfAllowed(id, component))
                lateinit var view: AppWidgetHostView
                scenario.onActivity { activity ->
                    activity.heading("Registered Usage provider · signed out")
                    host.startListening()
                    view = host.createView(activity, id, info)
                    val density = activity.resources.displayMetrics.density
                    activity.content.addView(
                        view,
                        ViewGroup.LayoutParams((320 * density).toInt(), (180 * density).toInt()),
                    )
                    view.updateAppWidgetSize(Bundle(), 320, 180, 320, 180)
                }
                app.cursor.android.widget.WidgetUpdates.updateAll(context)
                waitForWidgetText(view, "Connect web session")
                screenshot("registered-usage-signed-out")
                application.settings.language("zh-CN")
                waitForWidgetText(view, "连接网页会话")
                application.settings.boolean("cursor", false)
                application.settings.boolean("other", false)
                waitForWidgetText(view, "模型用量已隐藏")
                screenshot("registered-usage-chinese-hidden")
                host.deleteAppWidgetId(id)
            }
        } finally {
            host.stopListening()
            host.deleteHost()
            instrumentation.uiAutomation.dropShellPermissionIdentity()
            application.settings.language("en")
            application.settings.boolean("cursor", true)
            application.settings.boolean("other", true)
        }
    }

    private fun waitForWidgetText(host: View, text: String) {
        val deadline = System.currentTimeMillis() + 15_000
        var found = false
        while (!found && System.currentTimeMillis() < deadline) {
            instrumentation.runOnMainSync {
                found =
                    descendants(host).filterIsInstance<TextView>().any {
                        it.text.toString() == text
                    }
            }
            if (!found) Thread.sleep(100)
        }
        assertTrue("Registered widget never showed $text", found)
    }

    private suspend fun render(
        scenario: ActivityScenario<WidgetQaActivity>,
        widget: CursorWidget,
        width: Int,
        height: Int,
        state: WidgetState,
        title: String,
        renderContext: android.content.Context = context,
    ): List<TextView> {
        val composition =
            GlanceRemoteViews().compose(renderContext, size = DpSize(width.dp, height.dp)) {
                widget.Content(state)
            }
        lateinit var host: AppWidgetHostView
        scenario.onActivity { activity ->
            activity.content.removeAllViews()
            activity.heading(title)
            host = AppWidgetHostView(activity)
            val density = activity.resources.displayMetrics.density
            host.setPadding(0, 0, 0, 0)
            activity.content.addView(
                host,
                ViewGroup.LayoutParams((width * density).toInt(), (height * density).toInt()),
            )
            host.updateAppWidget(composition.remoteViews)
        }
        instrumentation.waitForIdleSync()
        Thread.sleep(250)
        screenshot("last-render")
        return descendants(host).filterIsInstance<TextView>()
    }

    private fun descendants(view: View): List<View> =
        listOf(view) +
            if (view is ViewGroup)
                (0 until view.childCount).flatMap { descendants(view.getChildAt(it)) }
            else emptyList()

    private fun assertTextFits(views: List<TextView>, required: Set<String>) {
        instrumentation.runOnMainSync {
            views
                .filter { it.text.toString() in required }
                .forEach { view ->
                    assertTrue("Clipped ${view.text}", view.layout.height <= view.height)
                    var root: View = view
                    while (root !is AppWidgetHostView && root.parent is View) root =
                        root.parent as View
                    val hostBounds = android.graphics.Rect()
                    assertTrue(
                        "Widget host detached before layout assertions",
                        root.isAttachedToWindow,
                    )
                    assertTrue(
                        "Widget host outside the test viewport",
                        root.getGlobalVisibleRect(hostBounds),
                    )
                    assertEquals("Test viewport clips widget width", root.width, hostBounds.width())
                    assertEquals(
                        "Test viewport clips widget height",
                        root.height,
                        hostBounds.height(),
                    )
                    val bounds = android.graphics.Rect()
                    assertTrue("Hidden ${view.text}", view.getGlobalVisibleRect(bounds))
                    assertTrue("Cropped ${view.text}", bounds.height() >= view.layout.height)
                    assertEquals("Horizontally cropped ${view.text}", view.width, bounds.width())
                    if (
                        view.text.toString().contains("Refresh") ||
                            view.text.toString().contains("刷新")
                    ) {
                        var target: View = view
                        while (!target.isClickable && target.parent is View) target =
                            target.parent as View
                        val tapBounds = android.graphics.Rect()
                        target.getGlobalVisibleRect(tapBounds)
                        assertTrue(
                            "Clipped refresh tap target: ${tapBounds.height()}px own=${target.height} " +
                                "type=${target.javaClass.simpleName} density=${view.resources.displayMetrics.density}",
                            tapBounds.height() >=
                                (48 * view.resources.displayMetrics.density).toInt(),
                        )
                    }
                    for (line in 0 until view.layout.lineCount) {
                        assertEquals(
                            "Ellipsized ${view.text}",
                            0,
                            view.layout.getEllipsisCount(line),
                        )
                    }
                }
        }
    }

    private fun screenshot(name: String) {
        instrumentation.waitForIdleSync()
        Thread.sleep(500)
        val folder = File(context.getExternalFilesDir(null), "widgets-qa").apply { mkdirs() }
        instrumentation.uiAutomation.takeScreenshot()?.let { bitmap ->
            File(folder, "$name.png").outputStream().use {
                bitmap.compress(Bitmap.CompressFormat.PNG, 100, it)
            }
            bitmap.recycle()
            shell("mkdir -p /sdcard/cursor-android-widgets-qa")
            shell("cp ${folder.path}/$name.png /sdcard/cursor-android-widgets-qa/$name.png")
        }
    }
}
