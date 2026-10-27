package org.mytonwallet.app_air.uicomponents.commonViews

import android.content.Context
import android.graphics.Bitmap
import android.os.Handler
import android.os.Looper
import android.util.LruCache
import java.util.concurrent.Executors
import kotlin.math.roundToInt

internal object CardSurfaceResources {
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private val glowCache = LruCache<Int, Pair<Bitmap, Float>>(4)
    private val defaults = mutableMapOf<Boolean, CardBackgroundArtwork.Artwork>()
    private var surfaceSource: String? = null

    fun renderSurface(block: () -> Unit) {
        worker.execute(block)
    }

    fun prepare(
        context: Context,
        width: Float,
        gram: Boolean,
        completed: (CardBackgroundArtwork.Artwork, Pair<Bitmap, Float>, String) -> Unit
    ) {
        val appContext = context.applicationContext
        val key = width.roundToInt()
        worker.execute {
            val artwork = defaults.getOrPut(gram) { CardSurfaceTextures.default(appContext, gram) }
            val glow =
                glowCache.get(key)
                    ?: CardSurfaceTextures.glow(key.toFloat()).also { glowCache.put(key, it) }
            val source = surfaceSource
                ?: appContext.assets.open("card-motion/surface.agsl").bufferedReader()
                    .use { it.readText() }
                    .also { surfaceSource = it }
            main.post { completed(artwork, glow, source) }
        }
    }
}
