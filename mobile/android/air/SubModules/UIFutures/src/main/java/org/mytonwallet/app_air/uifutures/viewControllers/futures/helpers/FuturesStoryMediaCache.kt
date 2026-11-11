package org.mytonwallet.app_air.uifutures.viewControllers.futures.helpers

import android.content.Context
import android.net.ConnectivityManager
import java.io.File
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.mytonwallet.app_air.walletcore.moshi.MApiPerpsOnboardingStory

val MApiPerpsOnboardingStory.videoUrl: String
    get() = h264Url ?: url

object FuturesStoryMediaCache {
    private const val DIRECTORY = "perps-stories-v1"
    private const val PREVIEW_MIME_TYPE = "image/webp"
    private const val VIDEO_MIME_TYPE = "video/mp4"

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var prefetchJob: Job? = null

    /** [onComplete] runs on the main thread. */
    fun prefetch(
        context: Context,
        stories: List<MApiPerpsOnboardingStory>,
        onComplete: (Boolean) -> Unit
    ) {
        val appContext = context.applicationContext
        prefetchJob?.cancel()
        prefetchJob = scope.launch {
            stories.map { async { download(appContext, it.preview, PREVIEW_MIME_TYPE) } }.awaitAll()
            if (!isDataSaverOn(appContext)) {
                for (story in stories) download(appContext, story.videoUrl, VIDEO_MIME_TYPE)
            }
            ensureActive()
            val kept = stories.flatMap {
                listOf(fileFor(appContext, it.preview), fileFor(appContext, it.videoUrl))
            }
                .mapTo(HashSet()) { it.name }
            directory(appContext).listFiles()?.filter { it.name !in kept }?.forEach { it.delete() }
            val isComplete = stories.all {
                cachedFile(appContext, it.preview) != null &&
                    cachedFile(appContext, it.videoUrl) != null
            }
            withContext(Dispatchers.Main) { onComplete(isComplete) }
        }
    }

    fun cachedFile(context: Context, url: String): File? =
        fileFor(context, url).takeIf { it.exists() && it.length() > 0 }

    // URLs are content-hashed, so a cached file never goes stale
    private fun fileFor(context: Context, url: String): File {
        val digest = MessageDigest.getInstance("SHA-256").digest(url.toByteArray())
            .take(16).joinToString("") { "%02x".format(it) }
        val extension = url.substringBefore('?').substringAfterLast('/').substringAfterLast('.', "")
        return File(directory(context), if (extension.isEmpty()) digest else "$digest.$extension")
    }

    private fun directory(context: Context) = File(context.cacheDir, DIRECTORY)

    private fun isDataSaverOn(context: Context): Boolean {
        val manager = context.getSystemService(ConnectivityManager::class.java) ?: return false
        return manager.isActiveNetworkMetered &&
            manager.restrictBackgroundStatus ==
            ConnectivityManager.RESTRICT_BACKGROUND_STATUS_ENABLED
    }

    private suspend fun download(context: Context, url: String, mimeType: String) {
        val target = fileFor(context, url)
        if (target.exists() && target.length() > 0) return
        try {
            val connection = (URL(url).openConnection() as? HttpURLConnection)?.apply {
                connectTimeout = 20_000
                readTimeout = 20_000
            } ?: throw IOException("Not an HTTP URL")
            target.parentFile?.mkdirs()
            val tmp = File.createTempFile("${target.name}.", ".part", target.parentFile)
            try {
                if (connection.responseCode != HttpURLConnection.HTTP_OK ||
                    connection.contentType?.substringBefore(';')?.trim() != mimeType
                ) {
                    throw IOException("Unexpected response")
                }
                connection.inputStream.use { input ->
                    tmp.outputStream().use { output ->
                        val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
                        while (true) {
                            currentCoroutineContext().ensureActive()
                            val count = input.read(buffer)
                            if (count < 0) break
                            output.write(buffer, 0, count)
                        }
                    }
                }
                if (tmp.length() == 0L) throw IOException("Empty file")
                if (!tmp.renameTo(target)) tmp.copyTo(target, overwrite = true)
            } finally {
                connection.disconnect()
                tmp.delete()
            }
        } catch (_: IOException) {
        }
    }
}
