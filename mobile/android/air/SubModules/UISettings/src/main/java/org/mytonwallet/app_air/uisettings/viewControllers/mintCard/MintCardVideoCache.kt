package org.mytonwallet.app_air.uisettings.viewControllers.mintCard

import android.content.Context
import java.io.File
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.mytonwallet.app_air.walletcore.MTW_CARDS_MINT_BASE_URL
import org.mytonwallet.app_air.walletcore.moshi.ApiMtwCardType

// Downloads the per-card intro videos to disk once, so every tab plays instantly (and works
// offline) after MintCardVC opens. Playback falls back to the remote URL until a file is ready.
object MintCardVideoCache {

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    // The request identity also prevents a download from publishing after a cache clear.
    private val inFlight = mutableMapOf<ApiMtwCardType, Any>()

    // type -> callbacks waiting for that download to finish.
    private val waiters = mutableMapOf<ApiMtwCardType, MutableList<(File) -> Unit>>()

    private fun remoteUrl(type: ApiMtwCardType): String =
        "${MTW_CARDS_MINT_BASE_URL}mtw_card_${type.name.lowercase()}.h264.mp4"

    private fun cacheFile(context: Context, type: ApiMtwCardType): File {
        val dir = File(context.cacheDir, "mint-cards")
        return File(dir, "mtw_card_${type.name.lowercase()}.h264.mp4")
    }

    suspend fun clear(context: Context): Boolean = withContext(Dispatchers.IO) {
        val dir = File(context.applicationContext.cacheDir, "mint-cards")
        synchronized(inFlight) {
            inFlight.clear()
            waiters.clear()
            !dir.exists() || dir.deleteRecursively()
        }
    }

    /** Local file if already downloaded, else null. */
    fun cachedFile(context: Context, type: ApiMtwCardType): File? =
        cacheFile(context, type).takeIf { it.exists() && it.length() > 0 }

    /** Kick off downloads for every type. Safe to call repeatedly; skips already-cached ones. */
    fun precache(context: Context, types: List<ApiMtwCardType>) {
        val appContext = context.applicationContext
        for (type in types) {
            if (cachedFile(appContext, type) != null) continue
            download(appContext, type, null)
        }
    }

    /**
     * Ensures [type] is cached, invoking [onReady] on the main thread with the local file.
     * If already cached, calls back immediately.
     */
    fun ensure(context: Context, type: ApiMtwCardType, onReady: (File) -> Unit) {
        val appContext = context.applicationContext
        cachedFile(appContext, type)?.let {
            onReady(it)
            return
        }
        download(appContext, type, onReady)
    }

    private fun download(context: Context, type: ApiMtwCardType, onReady: ((File) -> Unit)?) {
        val request = Any()
        val startNow = synchronized(inFlight) {
            if (onReady != null) {
                waiters.getOrPut(type) { mutableListOf() }.add(onReady)
            }
            if (inFlight.containsKey(type)) {
                false
            } else {
                inFlight[type] = request
                true
            }
        }
        if (!startNow) return

        scope.launch {
            val file = runCatching { downloadBlocking(context, type, request) }.getOrNull()
            val callbacks = synchronized(inFlight) {
                if (inFlight[type] !== request) {
                    emptyList()
                } else {
                    inFlight.remove(type)
                    waiters.remove(type) ?: emptyList()
                }
            }
            if (file != null && callbacks.isNotEmpty()) {
                withContext(Dispatchers.Main) {
                    callbacks.forEach { runCatching { it(file) } }
                }
            }
        }
    }

    private fun downloadBlocking(context: Context, type: ApiMtwCardType, request: Any): File {
        val target = cacheFile(context, type)
        if (target.exists() && target.length() > 0) return target

        target.parentFile?.mkdirs()
        val connection = (URL(remoteUrl(type)).openConnection() as? HttpURLConnection)?.apply {
            connectTimeout = 15_000
            readTimeout = 30_000
        } ?: throw IOException("Card video URL is not an HTTP URL")
        val tmp = File.createTempFile("${target.name}.", ".part", target.parentFile)
        try {
            connection.inputStream.use { input ->
                tmp.outputStream().use { output ->
                    input.copyTo(output)
                }
            }
            synchronized(inFlight) {
                if (inFlight[type] !== request) throw IOException("Card video cache was cleared")
                if (!tmp.renameTo(target)) {
                    tmp.copyTo(target, overwrite = true)
                }
            }
        } finally {
            connection.disconnect()
            tmp.delete()
        }
        return target
    }
}
