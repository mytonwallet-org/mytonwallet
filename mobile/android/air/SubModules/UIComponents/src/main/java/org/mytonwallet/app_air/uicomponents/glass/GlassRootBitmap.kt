package org.mytonwallet.app_air.uicomponents.glass

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Matrix
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.view.View
import android.view.ViewGroup
import android.view.ViewTreeObserver
import java.lang.ref.WeakReference
import java.util.WeakHashMap
import kotlin.math.max
import org.mytonwallet.app_air.blur3.source.BlurredBackgroundSourceBitmap
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color

/**
 * Software blur source for [WGlassView] where RenderEffect is unavailable (API < 31): the root is
 * drawn into a downscaled bitmap on the UI thread, box-blurred on a shared background thread and
 * republished through [source]'s BitmapShader — Telegram's pre-RenderNode chat blur scheme. A
 * capture starts only when the root's content hash changes, and never while a blur is in
 * flight, so animations settle to the blur thread's own cadence. Published
 * bitmaps are triple-buffered: a buffer is reused for capture only once nothing can still be
 * rendering it.
 */
internal class GlassRootBitmap private constructor(root: ViewGroup) :
    ViewTreeObserver.OnPreDrawListener,
    View.OnAttachStateChangeListener {

    val source = BlurredBackgroundSourceBitmap()

    /** Maps the downscaled bitmap back to root coordinates. `setBitmap` resets the source's
     * matrix (its center-crop path expects a parent size nothing sets here), so this is
     * re-applied on every publish. */
    private val sourceMatrix = Matrix()

    private val rootRef = WeakReference(root)
    private val consumers = ArrayList<WGlassView>()
    private val excluded = HashSet<View>()
    private val rootLocation = IntArray(2)
    private val viewLocation = IntArray(2)
    private val localOffset = FloatArray(2)
    private var observer: ViewTreeObserver? = null
    private var lastHash = 0L
    private var blurInFlight = false
    private var retiredBitmap: Bitmap? = null
    private var freeBitmap: Bitmap? = null

    // ── Consumers ────────────────────────────────────────────────────────────

    fun attach(consumer: WGlassView) {
        if (consumers.contains(consumer)) return
        consumers.add(consumer)
        if (consumers.size == 1) {
            val root = rootRef.get() ?: return
            root.addOnAttachStateChangeListener(this)
            if (root.isAttachedToWindow) listen(root)
        }
    }

    fun detach(consumer: WGlassView) {
        if (!consumers.remove(consumer) || consumers.isNotEmpty()) return
        unlisten()
        source.setBitmap(null)
        retiredBitmap?.recycle()
        retiredBitmap = null
        freeBitmap?.recycle()
        freeBitmap = null
        val root = rootRef.get() ?: return
        root.removeOnAttachStateChangeListener(this)
        synchronized(registry) {
            if (registry[root] === this) registry.remove(root)
        }
    }

    // ── Root lifecycle ───────────────────────────────────────────────────────

    override fun onViewAttachedToWindow(v: View) {
        listen(v)
    }

    override fun onViewDetachedFromWindow(v: View) {
        unlisten()
    }

    private fun listen(root: View) {
        val vto = root.viewTreeObserver
        if (!vto.isAlive || vto === observer) return
        unlisten()
        vto.addOnPreDrawListener(this)
        observer = vto
    }

    private fun unlisten() {
        observer?.let { if (it.isAlive) it.removeOnPreDrawListener(this) }
        observer = null
    }

    // ── Per-frame driver ─────────────────────────────────────────────────────

    override fun onPreDraw(): Boolean {
        val root = rootRef.get() ?: return true
        if (root.viewTreeObserver !== observer) listen(root)
        if (consumers.isEmpty() || root.width == 0 || root.height == 0) return true
        update(root)
        return true
    }

    private fun update(root: ViewGroup) {
        root.getLocationInWindow(rootLocation)
        excluded.clear()
        for (consumer in consumers) {
            consumer.syncFromTarget()
            collectGlassExcluded(root, consumer, excluded)
            consumer.target?.let { collectGlassExcluded(root, it, excluded) }
            if (!consumer.isAttachedToWindow || !consumer.isShown || consumer.alpha <= 0f) continue
            val pill = consumer.blurDrawable ?: continue
            if (resolveGlassLocalOffset(root, consumer, localOffset)) {
                pill.setSourceOffset(localOffset[0], localOffset[1])
            } else {
                consumer.getLocationInWindow(viewLocation)
                pill.setSourceOffset(
                    (viewLocation[0] - rootLocation[0]).toFloat(),
                    (viewLocation[1] - rootLocation[1]).toFloat()
                )
            }
        }
        if (blurInFlight) return
        val hash = contentHash(root)
        if (hash == lastHash && source.bitmap != null) return
        lastHash = hash
        capture(root)
    }

    private fun contentHash(root: ViewGroup): Long {
        var h = -0x61c8864680b583ebL
        fun mix(v: Long) {
            h = (h xor v) * 0x100000001b3L
        }
        mix(root.width.toLong())
        mix(root.height.toLong())
        mix(root.scrollX.toLong())
        mix(root.scrollY.toLong())
        mix(WColor.Background.color.toLong())
        for (i in 0 until root.childCount) {
            val child = root.getChildAt(i)
            if (child.visibility != View.VISIBLE || child in excluded) continue
            mix(System.identityHashCode(child).toLong())
            mix(child.left.toLong())
            mix(child.top.toLong())
            mix(child.translationX.toRawBits().toLong())
            mix(child.translationY.toRawBits().toLong())
            mix(child.scaleX.toRawBits().toLong())
            mix((child.alpha * 255).toLong())
        }
        return h
    }

    // ── Capture and blur ─────────────────────────────────────────────────────

    private fun capture(root: ViewGroup) {
        val bw = max(1, (root.width / DOWN_SCALE).toInt())
        val bh = max(1, (root.height / DOWN_SCALE).toInt())
        var bitmap = freeBitmap
        freeBitmap = null
        if (bitmap == null || bitmap.width != bw || bitmap.height != bh) {
            bitmap?.recycle()
            bitmap = Bitmap.createBitmap(bw, bh, Bitmap.Config.ARGB_8888)
        }
        bitmap.eraseColor(WColor.Background.color)
        sourceMatrix.setScale(root.width / bw.toFloat(), root.height / bh.toFloat())
        val canvas = Canvas(bitmap)
        canvas.scale(bw / root.width.toFloat(), bh / root.height.toFloat())
        val host = root as? GlassCaptureHost
        val drawingTime = root.drawingTime
        GlassCapture.capturing = true
        try {
            root.background?.draw(canvas)
            canvas.translate(-root.scrollX.toFloat(), -root.scrollY.toFloat())
            for (i in 0 until root.childCount) {
                val child = root.getChildAt(i)
                if (child.visibility != View.VISIBLE || child in excluded) continue
                if (host != null) {
                    host.glassDrawChild(canvas, child, drawingTime)
                } else {
                    canvas.save()
                    canvas.translate(
                        child.left + child.translationX,
                        child.top + child.translationY
                    )
                    child.draw(canvas)
                    canvas.restore()
                }
            }
        } finally {
            GlassCapture.capturing = false
        }
        blurInFlight = true
        val radius = max(4, max(bw, bh) / 12)
        blurHandler.post {
            boxBlur(bitmap, radius)
            mainHandler.post { publish(bitmap) }
        }
    }

    private fun publish(bitmap: Bitmap) {
        blurInFlight = false
        if (consumers.isEmpty()) {
            bitmap.recycle()
            return
        }
        val previous = source.bitmap
        source.setBitmap(bitmap)
        source.matrix = sourceMatrix
        freeBitmap = retiredBitmap
        retiredBitmap = previous
        for (consumer in consumers) consumer.invalidate()
    }

    companion object {
        private const val DOWN_SCALE = 12f

        private val registry = WeakHashMap<ViewGroup, GlassRootBitmap>()

        fun of(root: ViewGroup): GlassRootBitmap = synchronized(registry) {
            registry[root] ?: GlassRootBitmap(root).also { registry[root] = it }
        }

        private val mainHandler = Handler(Looper.getMainLooper())
        private val blurHandler by lazy {
            Handler(HandlerThread("GlassBlur").apply { start() }.looper)
        }

        /** Three box passes per axis approximate a gaussian; runs on the blur thread only. */
        private fun boxBlur(bitmap: Bitmap, radius: Int) {
            val w = bitmap.width
            val h = bitmap.height
            val pixels = IntArray(w * h)
            val scratch = IntArray(w * h)
            bitmap.getPixels(pixels, 0, w, 0, 0, w, h)
            repeat(3) {
                boxBlurPass(pixels, scratch, w, h, radius)
                boxBlurPass(scratch, pixels, h, w, radius)
            }
            bitmap.setPixels(pixels, 0, w, 0, 0, w, h)
        }

        /** Blurs each row of [src] ([w]x[h]) and writes it transposed into [dst] ([h]x[w]). */
        private fun boxBlurPass(src: IntArray, dst: IntArray, w: Int, h: Int, radius: Int) {
            val div = 2 * radius + 1
            for (y in 0 until h) {
                val row = y * w
                var r = 0
                var g = 0
                var b = 0
                for (i in -radius..radius) {
                    val c = src[row + i.coerceIn(0, w - 1)]
                    r += (c shr 16) and 0xFF
                    g += (c shr 8) and 0xFF
                    b += c and 0xFF
                }
                for (x in 0 until w) {
                    dst[x * h + y] = (0xFF shl 24) or
                        ((r / div) shl 16) or ((g / div) shl 8) or (b / div)
                    val add = src[row + (x + radius + 1).coerceAtMost(w - 1)]
                    val sub = src[row + (x - radius).coerceAtLeast(0)]
                    r += ((add shr 16) and 0xFF) - ((sub shr 16) and 0xFF)
                    g += ((add shr 8) and 0xFF) - ((sub shr 8) and 0xFF)
                    b += (add and 0xFF) - (sub and 0xFF)
                }
            }
        }
    }
}
