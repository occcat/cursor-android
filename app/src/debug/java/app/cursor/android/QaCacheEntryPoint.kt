package app.cursor.android

import app.cursor.android.data.CacheDao
import dagger.hilt.EntryPoint
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent

/** Debug-only fixture access for device tests; absent from release builds. */
@EntryPoint
@InstallIn(SingletonComponent::class)
interface QaCacheEntryPoint {
    fun cache(): CacheDao
}
