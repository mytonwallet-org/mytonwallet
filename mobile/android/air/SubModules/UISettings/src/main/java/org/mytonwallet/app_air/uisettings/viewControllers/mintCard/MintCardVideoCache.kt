package org.mytonwallet.app_air.uisettings.viewControllers.mintCard

import android.content.Context
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.mytonwallet.app_air.walletcore.MTW_CARDS_MINT_BASE_URL
import org.mytonwallet.app_air.walletcore.moshi.ApiMtwCardType
import java.io.File
import java.net.HttpURLConnection
import java.net.URL

// Downloads the per-card intro videos to disk once, so every tab plays instantly (and works
// offline) after MintCardVC opens. Playback falls back to the remote URL until a file is ready.
object MintCardVideoCache {

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    // Types currently being downloaded, to avoid duplicate concurrent fetches.
    private val inFlight = mutableSetOf<ApiMtwCardType>()

    // type -> callbacks waiting for that download to finish.
    private val waiters = mutableMapOf<ApiMtwCardType, MutableList<(File) -> Unit>>()

    private fun remoteUrl(type: ApiMtwCardType): String =
        "${MTW_CARDS_MINT_BASE_URL}mtw_card_${type.name.lowercase()}.h264.mp4"

    private fun cacheFile(context: Context, type: ApiMtwCardType): File {
        val dir = File(context.cacheDir, "mint-cards").apply { mkdirs() }
        return File(dir, "mtw_card_${type.name.lowercase()}.h264.mp4")
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
        val startNow = synchronized(inFlight) {
            if (onReady != null) {
                waiters.getOrPut(type) { mutableListOf() }.add(onReady)
            }
            if (inFlight.contains(type)) {
                false
            } else {
                inFlight.add(type)
                true
            }
        }
        if (!startNow) return

        scope.launch {
            val file = runCatching { downloadBlocking(context, type) }.getOrNull()
            val callbacks = synchronized(inFlight) {
                inFlight.remove(type)
                waiters.remove(type) ?: emptyList()
            }
            if (file != null && callbacks.isNotEmpty()) {
                withContext(Dispatchers.Main) {
                    callbacks.forEach { runCatching { it(file) } }
                }
            }
        }
    }

    private fun downloadBlocking(context: Context, type: ApiMtwCardType): File {
        val target = cacheFile(context, type)
        if (target.exists() && target.length() > 0) return target

        val tmp = File(target.parentFile, "${target.name}.part")
        val connection = (URL(remoteUrl(type)).openConnection() as HttpURLConnection).apply {
            connectTimeout = 15_000
            readTimeout = 30_000
        }
        try {
            connection.inputStream.use { input ->
                tmp.outputStream().use { output ->
                    input.copyTo(output)
                }
            }
            if (!tmp.renameTo(target)) {
                tmp.copyTo(target, overwrite = true)
                tmp.delete()
            }
        } finally {
            connection.disconnect()
        }
        return target
    }
}