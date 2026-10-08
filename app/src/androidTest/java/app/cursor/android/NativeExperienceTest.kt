package app.cursor.android

import android.Manifest
import android.app.NotificationManager
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import androidx.appcompat.app.AppCompatDelegate
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.core.content.ContextCompat
import androidx.test.platform.app.InstrumentationRegistry
import app.cursor.android.data.CacheEntry
import app.cursor.android.data.Preferences
import app.cursor.android.domain.UsageSnapshot
import app.cursor.android.system.UsageNotifications
import app.cursor.android.system.UsageOverlayService
import dagger.hilt.android.EntryPointAccessors
import java.io.File
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

class NativeExperienceTest {
    @get:Rule val compose = createAndroidComposeRule<MainActivity>()
    private val instrumentation
        get() = InstrumentationRegistry.getInstrumentation()

    private val context
        get() = instrumentation.targetContext

    @Test
    fun independentUsageConnectionAndLanguageSurviveRecreation() {
        compose.onNodeWithText("Usage").performClick()
        compose.onNodeWithText("Connect a web session in Settings to view usage.").assertExists()
        screenshot("usage-signed-out")
        shell("input keyevent KEYCODE_BACK")
        compose.onNodeWithText("Settings").performClick()
        compose.onNodeWithText("Connect web session").performScrollTo().assertExists()
        screenshot("settings-connections")
        compose.onNodeWithText("简体中文").performScrollTo().performClick()
        compose.waitUntil(5_000) {
            AppCompatDelegate.getApplicationLocales().toLanguageTags() == "zh-CN"
        }
        compose.activityRule.scenario.recreate()
        compose.waitForIdle()
        assertEquals("zh-CN", AppCompatDelegate.getApplicationLocales().toLanguageTags())
        screenshot("settings-chinese")
        compose.onNodeWithText("English").performScrollTo().performClick()
        compose.waitUntil(5_000) {
            AppCompatDelegate.getApplicationLocales().toLanguageTags() == "en"
        }
    }

    @Test
    fun permissionDenialAndUserStartedOverlayRemainSafe() = runBlocking {
        val usage =
            UsageSnapshot(
                cursorUsed = 32.0,
                otherUsed = 61.0,
                fetchedAt = System.currentTimeMillis(),
            )
        val preferences = Preferences(notifications = true)
        if (
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) !=
                PackageManager.PERMISSION_GRANTED
        ) {
            UsageNotifications.update(context, usage, preferences)
            assertTrue(
                context
                    .getSystemService(NotificationManager::class.java)
                    .activeNotifications
                    .isEmpty()
            )
        }
        shell("appops set app.cursor.android SYSTEM_ALERT_WINDOW deny")
        compose.runOnIdle {
            ContextCompat.startForegroundService(
                context,
                Intent(context, UsageOverlayService::class.java),
            )
        }
        compose.waitForIdle()
        compose.onNodeWithText("Your work.\nWithin reach.").assertExists()
        screenshot("onboarding")
        val cache =
            EntryPointAccessors.fromApplication(context, QaCacheEntryPoint::class.java).cache()
        try {
            (context.applicationContext as CursorApplication)
                .settings
                .boolean("notifications", true)
            cache.put(CacheEntry("usage", Json.encodeToString(usage), System.currentTimeMillis()))
            shell("pm grant app.cursor.android android.permission.POST_NOTIFICATIONS")
            shell("appops set app.cursor.android SYSTEM_ALERT_WINDOW allow")
            compose.runOnIdle {
                ContextCompat.startForegroundService(
                    context,
                    Intent(context, UsageOverlayService::class.java),
                )
            }
            compose.waitForIdle()
            UsageNotifications.update(context, usage, preferences)
            compose.waitUntil(5_000) {
                context.getSystemService(NotificationManager::class.java).activeNotifications.any {
                    it.id == UsageNotifications.overlayId
                }
            }
            Thread.sleep(1_000)
            shell("cmd statusbar expand-notifications")
            Thread.sleep(600)
            screenshot("notification-fixture")
            shell("cmd statusbar collapse")
            shell("input keyevent KEYCODE_HOME")
            Thread.sleep(600)
            screenshot("overlay-fixture")
        } finally {
            context.stopService(Intent(context, UsageOverlayService::class.java))
            UsageNotifications.cancel(context)
            cache.clear()
            (context.applicationContext as CursorApplication)
                .settings
                .boolean("notifications", false)
            shell("appops set app.cursor.android SYSTEM_ALERT_WINDOW deny")
        }
    }

    private fun shell(command: String) {
        instrumentation.uiAutomation.executeShellCommand(command).use { descriptor ->
            android.os.ParcelFileDescriptor.AutoCloseInputStream(descriptor).readBytes()
        }
    }

    private fun screenshot(name: String) {
        compose.waitForIdle()
        val folder = File(context.getExternalFilesDir(null), "qa").apply { mkdirs() }
        instrumentation.uiAutomation.takeScreenshot()?.let { bitmap ->
            File(folder, "$name.png").outputStream().use {
                bitmap.compress(Bitmap.CompressFormat.PNG, 100, it)
            }
            bitmap.recycle()
            shell("mkdir -p /sdcard/cursor-android-qa-v2")
            shell("cp ${folder.path}/$name.png /sdcard/cursor-android-qa-v2/$name.png")
        }
    }
}
