package org.mytonwallet.app_air.uireceive

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.drawable.BitmapDrawable
import android.util.Base64
import androidx.core.graphics.drawable.toDrawable
import com.facebook.cache.common.SimpleCacheKey
import com.facebook.cache.disk.FileCache
import com.facebook.imagepipeline.core.ImagePipelineFactory
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.mytonwallet.app_air.uicomponents.base.WNavigationBar
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.walletbasecontext.utils.ApplicationContextHolder
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.models.blockchain.MBlockchain
import org.mytonwallet.app_air.walletcore.moshi.api.ApiMethod
import java.io.ByteArrayOutputStream
import kotlin.math.roundToInt

object ReceiveBackgroundCache {
    private data class CacheKey(val chain: MBlockchain, val width: Int, val height: Int)

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val mainScope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private val cache = mutableMapOf<CacheKey, BitmapDrawable>()
    private val pending = mutableMapOf<CacheKey, MutableList<(BitmapDrawable?) -> Unit>>()
    private val queue = Channel<CacheKey>(Channel.UNLIMITED)

    init {
        scope.launch {
            for (key in queue) {
                try {
                    runRender(key)
                } catch (_: Exception) {
                    try {
                        dispatchPending(key, null)
                    } catch (_: Exception) {
                    }
                }
            }
        }
    }

    fun precache(statusBarTop: Int, prioritizedChains: List<MBlockchain> = emptyList()) {
        val width = ApplicationContextHolder.screenWidth
        val height = statusBarTop + WNavigationBar.DEFAULT_HEIGHT.dp + QRCodeVC.HEIGHT.dp
        val ordered =
            prioritizedChains + MBlockchain.supportedChains.filter { it !in prioritizedChains }
        for (chain in ordered) {
            render(chain, width, height, null)
        }
    }

    fun render(
        chain: MBlockchain,
        width: Int,
        height: Int,
        callback: ((BitmapDrawable?) -> Unit)?
    ) {
        val key = CacheKey(chain, width, height)

        synchronized(cache) { cache[key] }?.let { cached ->
            if (callback != null) {
                mainScope.launch { callback(cached) }
            }
            return
        }

        val isFirst = synchronized(pending) {
            val existing = pending[key]
            if (existing != null) {
                if (callback != null) existing.add(callback)
                false
            } else {
                pending[key] = mutableListOf<(BitmapDrawable?) -> Unit>().apply {
                    if (callback != null) add(callback)
                }
                true
            }
        }
        if (isFirst) {
            queue.trySend(key)
        }
    }

    private fun diskKey(key: CacheKey) =
        SimpleCacheKey("receive_bg_${key.chain.name}")

    private fun fileCache(): FileCache? = try {
        ImagePipelineFactory.getInstance().diskCachesStoreSupplier.get().mainFileCache
    } catch (_: Exception) {
        null
    }

    private fun loadFromDisk(key: CacheKey): BitmapDrawable? {
        val resource = try {
            fileCache()?.getResource(diskKey(key))
        } catch (_: Exception) {
            null
        } ?: return null
        val bytes = try {
            resource.read()
        } catch (_: Exception) {
            return null
        }
        val bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size) ?: return null
        return bitmap.toDrawable(ApplicationContextHolder.applicationContext.resources)
    }

    private fun writeToDisk(key: CacheKey, bitmap: Bitmap) {
        try {
            val baos = ByteArrayOutputStream()
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, baos)
            val bytes = baos.toByteArray()
            fileCache()?.insert(diskKey(key)) { os -> os.write(bytes) }
        } catch (_: Exception) {
        }
    }

    private suspend fun runRender(key: CacheKey) {
        synchronized(cache) { cache[key] }?.let {
            dispatchPending(key, it)
            return
        }
        loadFromDisk(key)?.let {
            synchronized(cache) { cache[key] = it }
            dispatchPending(key, it)
            return
        }
        val drawable = try {
            val result = WalletCore.call(
                ApiMethod.Other.RenderBlurredReceiveBg(
                    chain = key.chain,
                    options = ApiMethod.Other.RenderBlurredReceiveBg.Options(
                        width = key.width,
                        height = key.height,
                        blurPx = (key.width / ApplicationContextHolder.density / 2f)
                            .roundToInt()
                            .coerceAtLeast(100),
                        overlay = "rgba(28, 28, 30, 0.25)"
                    )
                )
            )
            val base64 = result.substringAfter("base64,")
            val bytes = Base64.decode(base64, Base64.DEFAULT)
            BitmapFactory.decodeByteArray(bytes, 0, bytes.size)?.let { bitmap ->
                writeToDisk(key, bitmap)
                bitmap.toDrawable(
                    ApplicationContextHolder.applicationContext.resources
                ).also {
                    synchronized(cache) { cache[key] = it }
                }
            }
        } catch (_: Throwable) {
            null
        }
        dispatchPending(key, drawable)
    }

    private suspend fun dispatchPending(key: CacheKey, drawable: BitmapDrawable?) {
        val callbacks = synchronized(pending) { pending.remove(key) } ?: return
        if (callbacks.isEmpty()) return
        withContext(Dispatchers.Main) {
            callbacks.forEach { callback ->
                runCatching { callback(drawable) }
            }
        }
    }
}
