package app.cursor.android.system

import android.content.Context
import androidx.hilt.work.HiltWorker
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.NetworkType
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import app.cursor.android.CursorApplication
import app.cursor.android.data.ApiFailure
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
        if (
            !container.repository.webConnected ||
                (preferences.paused && !inputData.getBoolean("manual", false))
        )
            return Result.success()
        return try {
            container.repository.refreshUsage()
            UsageNotifications.update(
                applicationContext,
                container.repository.usage.first(),
                preferences,
            )
            Result.success()
        } catch (failure: IOException) {
            if (failure is ApiFailure && failure.status in listOf(401, 403)) {
                if (failure.status == 401) UsageNotifications.cancel(applicationContext)
                Result.failure()
            } else if (runAttemptCount < 3) Result.retry() else Result.failure()
        }
    }

    companion object {
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
