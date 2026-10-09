package app.cursor.android

import android.app.Application
import android.content.Context
import androidx.hilt.work.HiltWorkerFactory
import androidx.room.Room
import androidx.work.Configuration
import app.cursor.android.data.CacheDao
import app.cursor.android.data.CredentialStore
import app.cursor.android.data.Credentials
import app.cursor.android.data.CursorApi
import app.cursor.android.data.CursorDatabase
import app.cursor.android.data.CursorRepository
import app.cursor.android.data.PreferenceSessionMigration
import app.cursor.android.data.SessionMigration
import app.cursor.android.data.SettingsStore
import app.cursor.android.data.UserPreferences
import app.cursor.android.data.WebSessionStore
import app.cursor.android.system.UsageNotifications
import app.cursor.android.system.UsageSyncWorker
import app.cursor.android.widget.WidgetUpdates
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.HiltAndroidApp
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

@HiltAndroidApp
class CursorApplication : Application(), Configuration.Provider {
    @Inject lateinit var repository: CursorRepository
    @Inject lateinit var settings: SettingsStore
    @Inject lateinit var workerFactory: HiltWorkerFactory

    private val appScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    override val workManagerConfiguration: Configuration
        get() = Configuration.Builder().setWorkerFactory(workerFactory).build()

    override fun onCreate() {
        super.onCreate()
        UsageNotifications.createChannels(this)
        UsageSyncWorker.schedule(this)
        WidgetUpdates.observe(this)
        appScope.launch {
            try {
                repository.restore()
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (_: Exception) {
                // A failed cold start must not kill the process.
            }
        }
    }
}

@Module
@InstallIn(SingletonComponent::class)
object ApplicationModule {
    @Provides
    @Singleton
    fun credentials(@ApplicationContext context: Context): Credentials = CredentialStore(context)

    @Provides
    @Singleton
    fun cache(@ApplicationContext context: Context): CacheDao =
        Room.databaseBuilder(context, CursorDatabase::class.java, "cursor.db").build().cache()

    @Provides
    @Singleton
    fun api(credentials: Credentials): CursorApi = CursorApi({ credentials.read("cookie") })

    @Provides
    @Singleton
    fun migration(@ApplicationContext context: Context): SessionMigration =
        PreferenceSessionMigration(context)

    @Provides
    @Singleton
    fun repository(
        api: CursorApi,
        cache: CacheDao,
        credentials: Credentials,
        migration: SessionMigration,
    ): CursorRepository =
        CursorRepository(api, cache, credentials, migration, WebSessionStore::clear)

    @Provides fun userPreferences(settings: SettingsStore): UserPreferences = settings

    @Provides
    @Singleton
    fun settings(@ApplicationContext context: Context): SettingsStore = SettingsStore(context)
}
