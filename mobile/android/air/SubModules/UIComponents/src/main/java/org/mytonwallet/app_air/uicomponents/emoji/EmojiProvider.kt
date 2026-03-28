package org.mytonwallet.app_air.uicomponents.emoji

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.Handler
import android.os.Looper
import android.util.LruCache
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import java.io.File
import java.net.HttpURLConnection
import java.net.URL

object EmojiProvider {

    private const val CDN_BASE =
        "https://raw.githubusercontent.com/korenskoy/emoji-data-ios/443f1c9/img-apple-160/"
    private const val DISK_DIR = "custom_emoji"
    private const val MEMORY_CACHE_ENTRIES = 256

    private val memoryCache = LruCache<String, Bitmap>(MEMORY_CACHE_ENTRIES)
    private lateinit var diskDir: File
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val mainHandler = Handler(Looper.getMainLooper())

    private val pendingCallbacks = mutableMapOf<String, MutableList<(Bitmap?) -> Unit>>()
    private val notFoundKeys = mutableSetOf<String>()

    fun init(context: Context) {
        if (::diskDir.isInitialized) return
        diskDir = File(context.cacheDir, DISK_DIR)
        diskDir.mkdirs()
    }

    fun get(unified: String): Bitmap? = memoryCache.get(unified)

    fun loadAsync(unified: String, onLoaded: (Bitmap?) -> Unit) {
        memoryCache.get(unified)?.let {
            onLoaded(it)
            return
        }

        if (unified in notFoundKeys) {
            onLoaded(null)
            return
        }

        synchronized(pendingCallbacks) {
            val existing = pendingCallbacks[unified]
            if (existing != null) {
                existing.add(onLoaded)
                return
            }
            pendingCallbacks[unified] = mutableListOf(onLoaded)
        }

        scope.launch {
            val bitmap = loadFromDisk(unified)
            val result = if (bitmap != null) {
                DownloadResult.Success(bitmap)
            } else {
                download(unified)
            }

            when (result) {
                is DownloadResult.Success -> memoryCache.put(unified, result.bitmap)
                is DownloadResult.NotFound -> synchronized(notFoundKeys) { notFoundKeys.add(unified) }
                is DownloadResult.NetworkError -> {}
            }

            val callbacks: List<(Bitmap?) -> Unit>
            synchronized(pendingCallbacks) {
                callbacks = pendingCallbacks.remove(unified) ?: emptyList()
            }
            val bmp = (result as? DownloadResult.Success)?.bitmap
            mainHandler.post {
                for (cb in callbacks) cb(bmp)
            }
        }
    }

    private sealed class DownloadResult {
        class Success(val bitmap: Bitmap) : DownloadResult()
        data object NotFound : DownloadResult()
        data object NetworkError : DownloadResult()
    }

    private fun loadFromDisk(unified: String): Bitmap? {
        val file = File(diskDir, "$unified.png")
        if (!file.exists()) return null
        return try {
            BitmapFactory.decodeFile(file.absolutePath)
        } catch (_: Exception) {
            file.delete()
            null
        }
    }

    private fun download(unified: String): DownloadResult {
        val urls = mutableListOf("$CDN_BASE$unified.png")
        val withoutFe0f = unified.replace("-fe0f", "")
        if (withoutFe0f != unified) urls.add("$CDN_BASE$withoutFe0f.png")
        if (!unified.contains("-fe0f")) {
            val parts = unified.split("-")
            if (parts.size == 1) urls.add("$CDN_BASE${parts[0]}-fe0f.png")
        }

        var hadNetworkError = false
        for (url in urls) {
            when (val result = downloadUrl(url)) {
                is DownloadResult.Success -> return result
                is DownloadResult.NetworkError -> hadNetworkError = true
                is DownloadResult.NotFound -> {}
            }
        }
        return if (hadNetworkError) DownloadResult.NetworkError else DownloadResult.NotFound
    }

    private fun downloadUrl(urlStr: String): DownloadResult {
        var conn: HttpURLConnection? = null
        return try {
            conn = URL(urlStr).openConnection() as HttpURLConnection
            conn.connectTimeout = 5_000
            conn.readTimeout = 5_000
            conn.instanceFollowRedirects = true
            if (conn.responseCode != 200) return DownloadResult.NotFound

            val bytes = conn.inputStream.readBytes()
            val bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
                ?: return DownloadResult.NotFound

            val unified = urlStr.substringAfterLast("/").removeSuffix(".png")
            File(diskDir, "$unified.png").outputStream().use { it.write(bytes) }

            DownloadResult.Success(bitmap)
        } catch (_: Exception) {
            DownloadResult.NetworkError
        } finally {
            conn?.disconnect()
        }
    }
}
