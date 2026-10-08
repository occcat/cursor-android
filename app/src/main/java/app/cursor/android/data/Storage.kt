package app.cursor.android.data

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.intPreferencesKey
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import androidx.room.Dao
import androidx.room.Database
import androidx.room.Entity
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.PrimaryKey
import androidx.room.Query
import androidx.room.RoomDatabase
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

/** Key material stays in Android Keystore; encrypted payloads are excluded from backups. */
interface Credentials {
    fun read(name: String): String?

    fun write(name: String, value: String?)
}

class CredentialStore(context: Context) : Credentials {
    private val preferences = context.getSharedPreferences("credentials", Context.MODE_PRIVATE)
    private val alias = "cursor.android.credentials.v1"
    private val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }

    @Synchronized
    override fun read(name: String): String? =
        preferences.getString(name, null)?.let { encoded ->
            runCatching {
                    val parts = encoded.split(':')
                    val cipher = Cipher.getInstance("AES/GCM/NoPadding")
                    cipher.init(
                        Cipher.DECRYPT_MODE,
                        key(),
                        GCMParameterSpec(128, Base64.decode(parts[0], Base64.NO_WRAP)),
                    )
                    String(cipher.doFinal(Base64.decode(parts[1], Base64.NO_WRAP)), Charsets.UTF_8)
                }
                .getOrNull()
        }

    @Synchronized
    override fun write(name: String, value: String?) {
        if (value == null) {
            check(preferences.edit().remove(name).commit())
            return
        }
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key())
        val iv = Base64.encodeToString(cipher.iv, Base64.NO_WRAP)
        val encrypted =
            Base64.encodeToString(cipher.doFinal(value.toByteArray(Charsets.UTF_8)), Base64.NO_WRAP)
        check(preferences.edit().putString(name, "$iv:$encrypted").commit())
    }

    private fun key(): SecretKey {
        val existing = store.getKey(alias, null) as? SecretKey
        if (existing != null) return existing
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
            .apply {
                init(
                    KeyGenParameterSpec.Builder(
                            alias,
                            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
                        )
                        .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                        .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                        .build()
                )
            }
            .generateKey()
    }
}

@Entity(tableName = "cache")
data class CacheEntry(@PrimaryKey val key: String, val json: String, val updatedAt: Long)

@Dao
interface CacheDao {
    @Query("SELECT * FROM cache WHERE `key` = :key") fun observe(key: String): Flow<CacheEntry?>

    @Query("SELECT * FROM cache WHERE `key` = :key") suspend fun get(key: String): CacheEntry?

    @Insert(onConflict = OnConflictStrategy.REPLACE) suspend fun put(entry: CacheEntry)

    @Query("DELETE FROM cache") suspend fun clear()
}

@Database(entities = [CacheEntry::class], version = 1, exportSchema = true)
abstract class CursorDatabase : RoomDatabase() {
    abstract fun cache(): CacheDao
}

private val Context.settingsDataStore by preferencesDataStore("settings")

data class Preferences(
    val remaining: Boolean = true,
    val cursor: Boolean = true,
    val other: Boolean = true,
    val pace: Boolean = true,
    val paused: Boolean = false,
    val notifications: Boolean = false,
    val intervalSeconds: Int = 60,
    val language: String = "en",
)

interface UserPreferences {
    val preferences: Flow<Preferences>

    suspend fun boolean(name: String, value: Boolean)

    suspend fun interval(seconds: Int)

    suspend fun language(language: String)
}

class SettingsStore(context: Context) : UserPreferences {
    private val store = context.settingsDataStore
    override val preferences =
        store.data.map { data ->
            Preferences(
                remaining = data[booleanPreferencesKey("remaining")] ?: true,
                cursor = data[booleanPreferencesKey("cursor")] ?: true,
                other = data[booleanPreferencesKey("other")] ?: true,
                pace = data[booleanPreferencesKey("pace")] ?: true,
                paused = data[booleanPreferencesKey("paused")] ?: false,
                notifications = data[booleanPreferencesKey("notifications")] ?: false,
                intervalSeconds = data[intPreferencesKey("interval")] ?: 60,
                language = data[stringPreferencesKey("language")] ?: "en",
            )
        }

    override suspend fun boolean(name: String, value: Boolean) {
        require(name in listOf("remaining", "cursor", "other", "pace", "paused", "notifications"))
        store.edit { it[booleanPreferencesKey(name)] = value }
    }

    override suspend fun interval(seconds: Int) {
        require(seconds in listOf(30, 60, 120, 300))
        store.edit { it[intPreferencesKey("interval")] = seconds }
    }

    override suspend fun language(language: String) {
        require(language in listOf("en", "zh-CN"))
        store.edit { it[stringPreferencesKey("language")] = language }
    }
}
