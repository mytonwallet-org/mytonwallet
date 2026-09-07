package org.mytonwallet.app_air.uicomponents.glass

import android.graphics.Canvas
import android.graphics.Color
import android.graphics.RectF
import android.os.Build
import android.view.View
import android.view.ViewGroup
import android.view.ViewTreeObserver
import androidx.annotation.RequiresApi
import java.lang.ref.WeakReference
import java.util.WeakHashMap
import kotlin.math.max
import org.mytonwallet.app_air.blur3.BlurredBackgroundDrawableViewFactory
import org.mytonwallet.app_air.blur3.DownscaleScrollableNoiseSuppressor
import org.mytonwallet.app_air.blur3.capture.IBlur3Capture
import org.mytonwallet.app_air.blur3.capture.IBlur3Hash
import org.mytonwallet.app_air.blur3.compat.Blur3Settings
import org.mytonwallet.app_air.blur3.source.BlurredBackgroundSource
import org.mytonwallet.app_air.blur3.source.BlurredBackgroundSourceColor
import org.mytonwallet.app_air.blur3.source.BlurredBackgroundSourceRenderNode
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.walletbasecontext.theme.ThemeManager
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color

/**
 * The blur source behind every [WGlassView] that targets the same root ViewGroup.
 *
 * One capture per root per frame, regardless of how many glass views sit over it: each frame the
 * root's direct children under each pill are recorded once into the noise suppressor's RenderNode
 * chain (weak blur + saturation for glass, strong blur for frosted), and every pill's drawable
 * references that chain. Children that contain a glass view or its content target are skipped,
 * which is what stops a RenderNode from referencing itself.
 *
 * Positions are root-relative and derived from window coordinates, so a glass view may be a
 * sibling of the root, a descendant of it, or anywhere else in the same window.
 */
@RequiresApi(Build.VERSION_CODES.S)
class GlassRoot private constructor(root: ViewGroup) :
    ViewTreeObserver.OnPreDrawListener,
    View.OnAttachStateChangeListener,
    IBlur3Capture {

    val liquidGlass = Blur3Settings.isLiquidGlassEnabled()

    private val rootRef = WeakReference(root)
    private val suppressor = DownscaleScrollableNoiseSuppressor(false, false)
    private val colorSource = BlurredBackgroundSourceColor().apply {
        color = WColor.Background.color
    }
    private val glassSource = createSource(DownscaleScrollableNoiseSuppressor.DRAW_GLASS)
    private val frostedSource = createSource(DownscaleScrollableNoiseSuppressor.DRAW_FROSTED_GLASS)
    private val frostedPlainSource =
        createSource(DownscaleScrollableNoiseSuppressor.DRAW_FROSTED_GLASS_NO_SATURATION)
    private val glassFactory = createFactory(glassSource, liquidGlass)
    private val frostedFactory = createFactory(frostedSource, liquidGlass)
    private val glassFactoryFlat = createFactory(glassSource, false)
    private val frostedFactoryFlat = createFactory(frostedSource, false)
    private val frostedPlainFactory = createFactory(frostedPlainSource, liquidGlass)
    private val frostedPlainFactoryFlat = createFactory(frostedPlainSource, false)

    private val consumers = ArrayList<WGlassView>()
    private val positions = ArrayList<RectF>()
    private val partConsumers = ArrayList<ArrayList<WGlassView>>()
    private val excluded = HashSet<View>()
    private val rootLocation = IntArray(2)
    private val viewLocation = IntArray(2)
    private val localOffset = FloatArray(2)
    private var observer: ViewTreeObserver? = null

    private fun createSource(flavor: Int): BlurredBackgroundSourceRenderNode =
        BlurredBackgroundSourceRenderNode(colorSource).apply {
            setScrollableNoiseSuppressor(suppressor, flavor)
            setUnderSource(colorSource)
        }

    private fun createFactory(
        source: BlurredBackgroundSource,
        refraction: Boolean
    ): BlurredBackgroundDrawableViewFactory = BlurredBackgroundDrawableViewFactory(source).apply {
        setLiquidGlassEffectAllowed(refraction)
    }

    /** [refraction] false gives a blur-only surface even while liquid glass is on. */
    fun factory(flavor: GlassFlavor, refraction: Boolean): BlurredBackgroundDrawableViewFactory {
        if (flavor == GlassFlavor.FROSTED_PLAIN) suppressor.setPlainBlurEnabled(true)
        return when {
            flavor == GlassFlavor.GLASS && refraction -> glassFactory
            flavor == GlassFlavor.GLASS -> glassFactoryFlat
            flavor == GlassFlavor.FROSTED_PLAIN && refraction -> frostedPlainFactory
            flavor == GlassFlavor.FROSTED_PLAIN -> frostedPlainFactoryFlat
            refraction -> frostedFactory
            else -> frostedFactoryFlat
        }
    }

    fun updateTheme() {
        colorSource.color = backstopColor()
        glassSource.invalidateDisplayListForDrawables()
        frostedSource.invalidateDisplayListForDrawables()
        frostedPlainSource.invalidateDisplayListForDrawables()
    }

    /**
     * A consumer floating over the root's own content (a card pill) makes the backstop
     * transparent: the backstop is a window-background stand-in drawn under every blur, and its
     * color leaks into the outline's anti-aliased edge, ringing pills that sit mid-content.
     */
    private var transparentBackstop = false

    private fun backstopColor(): Int =
        if (transparentBackstop) Color.TRANSPARENT else WColor.Background.color

    // ── Consumers ────────────────────────────────────────────────────────────

    fun attach(consumer: WGlassView) {
        if (consumers.contains(consumer)) return
        consumers.add(consumer)
        if (consumer.transparentBackstop && !transparentBackstop) {
            transparentBackstop = true
            colorSource.color = backstopColor()
            glassSource.invalidateDisplayListForDrawables()
            frostedSource.invalidateDisplayListForDrawables()
            frostedPlainSource.invalidateDisplayListForDrawables()
        }
        if (consumers.size == 1) {
            val root = rootRef.get() ?: return
            root.addOnAttachStateChangeListener(this)
            if (root.isAttachedToWindow) listen(root)
        }
    }

    fun detach(consumer: WGlassView) {
        if (!consumers.remove(consumer) || consumers.isNotEmpty()) return
        unlisten()
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
        partConsumers.clear()
        excluded.clear()

        for (consumer in consumers) {
            consumer.syncFromTarget()
            collectExcluded(root, consumer)
            consumer.target?.let { collectExcluded(root, it) }
        }

        var count = 0
        for (consumer in consumers) {
            if (!consumer.isAttachedToWindow || !consumer.isShown || consumer.alpha <= 0f) continue
            val pill = consumer.renderNodeDrawable ?: continue

            if (resolveLocalOffset(root, consumer)) {
                pill.setSourceOffset(localOffset[0], localOffset[1])
            } else {
                consumer.getLocationInWindow(viewLocation)
                pill.setSourceOffset(
                    (viewLocation[0] - rootLocation[0]).toFloat(),
                    (viewLocation[1] - rootLocation[1]).toFloat()
                )
            }

            val rect = positions.getOrNull(count) ?: RectF().also { positions.add(it) }
            pill.getPositionRelativeSource(rect)
            if (rect.isEmpty) continue
            val expand = max(partExpand, consumer.captureExpand)
            rect.inset(-expand, -expand)

            count++
            partConsumers.add(arrayListOf(consumer))
        }
        if (count == 0) return

        count = mergeOverlapping(count)
        suppressor.setupRenderNodes(positions, count)
        val changed = suppressor.invalidateResultRenderNodes(this, root.width, root.height)
        if (changed) {
            glassSource.invalidateDisplayListForDrawables()
            frostedSource.invalidateDisplayListForDrawables()
            frostedPlainSource.invalidateDisplayListForDrawables()
            for (group in partConsumers) for (consumer in group) consumer.invalidate()
        }
    }

    /**
     * Each part is blurred on its own, edges clamped, so two overlapping parts would show a seam
     * where one is drawn over the other. Overlapping rects are unioned into one part.
     */
    private fun mergeOverlapping(initialCount: Int): Int {
        var count = initialCount
        var merged = true
        while (merged) {
            merged = false
            var i = 0
            outer@ while (i < count) {
                var j = i + 1
                while (j < count) {
                    if (RectF.intersects(positions[i], positions[j])) {
                        positions[i].union(positions[j])
                        partConsumers[i].addAll(partConsumers[j])
                        val last = count - 1
                        if (j != last) {
                            positions[j].set(positions[last])
                            partConsumers[j] = partConsumers[last]
                        }
                        partConsumers.removeAt(last)
                        count = last
                        merged = true
                        break@outer
                    }
                    j++
                }
                i++
            }
        }
        return count
    }

    private fun resolveLocalOffset(root: ViewGroup, consumer: WGlassView): Boolean =
        resolveGlassLocalOffset(root, consumer, localOffset)

    private fun collectExcluded(root: ViewGroup, view: View) =
        collectGlassExcluded(root, view, excluded)

    // ── Capture ──────────────────────────────────────────────────────────────

    override fun capture(canvas: Canvas, position: RectF) {
        val root = rootRef.get() ?: return
        val host = root as? GlassCaptureHost
        val drawingTime = root.drawingTime
        GlassCapture.capturing = true
        try {
            canvas.drawColor(colorSource.color)
            root.background?.draw(canvas)
            canvas.save()
            canvas.translate(-root.scrollX.toFloat(), -root.scrollY.toFloat())
            for (i in 0 until root.childCount) {
                val child = root.getChildAt(i)
                if (!isCaptured(root, child, position)) continue
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
            canvas.restore()
        } finally {
            GlassCapture.capturing = false
        }
    }

    override fun captureCalculateHash(builder: IBlur3Hash, position: RectF) {
        val root = rootRef.get()
        if (root == null) {
            builder.unsupported()
            return
        }
        builder.addF(position.left)
        builder.addF(position.top)
        builder.addF(position.right)
        builder.addF(position.bottom)
        builder.add(root.width.toLong())
        builder.add(root.height.toLong())
        builder.add(colorSource.color.toLong())
        builder.add(ThemeManager.isDark)
        builder.add(root.scrollX.toLong())
        builder.add(root.scrollY.toLong())
        for (i in 0 until root.childCount) {
            val child = root.getChildAt(i)
            if (!isCaptured(root, child, position)) continue
            builder.add(child)
            builder.add(child.visibility.toLong())
        }
    }

    private fun isCaptured(root: ViewGroup, child: View, position: RectF): Boolean {
        if (child.visibility != View.VISIBLE || child in excluded) return false
        val left = child.left + child.translationX - root.scrollX
        val top = child.top + child.translationY - root.scrollY
        val right = left + child.width
        val bottom = top + child.height
        return right > position.left && left < position.right && bottom > position.top &&
            top < position.bottom
    }

    companion object {
        private val partExpand get() = 6f.dp

        private val registry = WeakHashMap<ViewGroup, GlassRoot>()

        fun of(root: ViewGroup): GlassRoot = synchronized(registry) {
            registry[root]?.takeIf { it.liquidGlass == Blur3Settings.isLiquidGlassEnabled() }
                ?: GlassRoot(root).also { registry[root] = it }
        }
    }
}

/**
 * Offset of [view]'s origin into [out], in [root]'s content coordinates. The capture draws in
 * those coordinates, so the offset must not include transforms applied above the root (window
 * locations bake in an ancestor's scale, sampling a shifted region). Only works for descendants
 * of the root; returns false otherwise.
 */
internal fun resolveGlassLocalOffset(root: ViewGroup, view: View, out: FloatArray): Boolean {
    var x = 0f
    var y = 0f
    var current: View = view
    while (true) {
        val parent = current.parent as? View ?: return false
        x += current.x - parent.scrollX
        y += current.y - parent.scrollY
        if (parent === root) {
            out[0] = x
            out[1] = y
            return true
        }
        current = parent
    }
}

/** Marks the direct child of [root] that contains [view], so capture never draws it. */
internal fun collectGlassExcluded(root: ViewGroup, view: View, out: MutableSet<View>) {
    var current: View = view
    while (true) {
        val parent = current.parent as? View ?: return
        if (parent === root) {
            out.add(current)
            return
        }
        current = parent
    }
}
