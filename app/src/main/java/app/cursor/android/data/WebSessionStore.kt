package app.cursor.android.data

import android.webkit.CookieManager
import android.webkit.WebStorage
import kotlin.coroutines.resume
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext

object WebSessionStore {
    suspend fun clear() =
        withContext(Dispatchers.Main.immediate) {
            WebStorage.getInstance().deleteAllData()
            suspendCancellableCoroutine { continuation ->
                CookieManager.getInstance().removeAllCookies {
                    CookieManager.getInstance().flush()
                    continuation.resume(Unit)
                }
            }
        }
}
