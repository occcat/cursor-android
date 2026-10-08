package app.cursor.android.system

import android.content.Context
import androidx.hilt.work.HiltWorker
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import androidx.work.workDataOf
import app.cursor.android.CursorApplication
import app.cursor.android.data.ApiFailure
import app.cursor.android.widget.WidgetUpdates
import dagger.assisted.Assisted
import dagger.assisted.AssistedInject
import java.io.IOException
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.flow.first

/** Inexact background snapshots; no second-based polling or foreground keepalive. */
@HiltWorker
class UsageSyncWorker
@AssistedInject
constructor(@Assisted context: Context, @Assisted parameters: WorkerParameters) :
    CoroutineWorker(context, parameters) {
    override suspend fun doWork(): Result {
        val container = applicationContext as CursorApplication
        val preferences = container.settings.preferences.first()
        val manual = inputData.getBoolean("manual", false)
        if (preferences.paused && !manual) {
            WidgetUpdates.updateAll(applicationContext)
            return Result.success()
        }
        var retry = false
        val now = System.currentTimeMillis()
        val usageAge = now - (container.repository.usage.first()?.fetchedAt ?: 0)
        if (container.repository.webConnected && (!manual || usageAge >= 30_000)) {
            try {
                container.repository.refreshUsage()
                UsageNotifications.update(
                    applicationContext,
                    container.repository.usage.first(),
                    preferences,
                )
            } catch (failure: IOException) {
                if (failure is ApiFailure && failure.status == 401) {
                    UsageNotifications.cancel(applicationContext)
                }
                retry = failure !is ApiFailure || failure.status !in listOf(401, 403)
            }
        }
        val agentsAge = now - (container.repository.agentSnapshot.first()?.updatedAt ?: 0)
        if (
            container.repository.connected &&
                WidgetUpdates.hasAgents(applicationContext) &&
                (!manual || agentsAge >= 30_000)
        ) {
            try {
                container.repository.refreshAgents()
            } catch (failure: IOException) {
                retry = retry || failure !is ApiFailure || failure.status !in listOf(401, 403)
            }
        }
        WidgetUpdates.updateAll(applicationContext)
        return if (retry && runAttemptCount < 3) Result.retry() else Result.success()
    }

    companion object {
        fun refresh(context: Context) {
            val request =
                OneTimeWorkRequestBuilder<UsageSyncWorker>()
                    .setInputData(workDataOf("manual" to true))
                    .setConstraints(
                        Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build()
                    )
                    .build()
            WorkManager.getInstance(context)
                .enqueueUniqueWork("cursor_manual_refresh", ExistingWorkPolicy.KEEP, request)
        }

        fun schedule(context: Context) {
            val request =
                PeriodicWorkRequestBuilder<UsageSyncWorker>(15, TimeUnit.MINUTES)
                    .setConstraints(
                        Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build()
                    )
                    .build()
            WorkManager.getInstance(context)
                .enqueueUniquePeriodicWork("cursor_usage", ExistingPeriodicWorkPolicy.KEEP, request)
        }
    }
}
