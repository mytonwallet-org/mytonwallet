package org.mytonwallet.app_air.uicomponents.glass

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.RectF
import android.graphics.drawable.Drawable
import android.os.Build
import android.view.View
import android.view.ViewGroup
import android.view.ViewTreeObserver
import kotlin.math.roundToInt
import org.mytonwallet.app_air.blur3.BlurredBackgroundWithFadeDrawable
import org.mytonwallet.app_air.blur3.compat.Blur3Settings
import org.mytonwallet.app_air.blur3.drawable.BlurredBackgroundDrawable
import org.mytonwallet.app_air.blur3.drawable.BlurredBackgroundDrawableRenderNode
import org.mytonwallet.app_air.blur3.drawable.color.BlurredBackgroundColorProvider
import org.mytonwallet.app_air.blur3.source.BlurredBackgroundSourceColor
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color

/**
 * A glass surface: blurred and refracted background, tint, specular rim and shadow, all drawn by
 * one Telegram-style drawable. Set the blur root with [setupWith]; below API 31 the background is
 * blurred in software through [GlassRootBitmap], and without a root (or with blur disabled) the
 * same drawable renders a solid tinted pill with the rim and shadow.
 *
 * Two ways to place it:
 * - as a child filling a container (shelves, backdrops), with [glassPadding] 0;
 * - as a halo sibling under a pill via [attachTo]: the view is inset by [glassPadding] around the
 *   target and mirrors its position, scale, alpha and visibility, so the rim and shadow can extend
 *   past the target's own clip.
 */
@SuppressLint("ViewConstructor")
class WGlassView(context: Context) :
    View(context),
    WThemedView {

    enum class FadeSide { TOP, BOTTOM }

    enum class Style { PILL, PANEL }

    var flavor = GlassFlavor.GLASS
        set(value) {
            if (field == value) return
            field = value
            rebuildDrawable()
        }

    var fadeSide: FadeSide? = null
        set(value) {
            if (field == value) return
            field = value
            rebuildDrawable()
        }

    /** Refraction on the edge; off keeps a plain blur regardless of the app setting. */
    var liquidGlass = true
        set(value) {
            if (field == value) return
            field = value
            rebuildDrawable()
        }

    /**
     * Marks this glass as floating over its root's own content rather than the window
     * background: the root's backstop color turns transparent, so it cannot ring the pill at
     * the outline's anti-aliased edge. Affects the whole root; set before the view attaches.
     */
    var transparentBackstop = false

    /**
     * Extra content captured around the pill, in px, so that neighbours bleed into the blur
     * instead of the blur clamping at the pill's own edge.
     */
    var captureExpand = 0f

    var style = Style.PILL
        set(value) {
            if (field == value) return
            field = value
            applyStrokeWidths()
        }

    /** Space kept around the pill for the rim and shadow, in px. */
    var glassPadding = 0
        set(value) {
            if (field == value) return
            field = value
            pill?.setPadding(value)
            syncSizeFromTarget()
        }

    private var root: ViewGroup? = null
    private var glassRoot: GlassRoot? = null
    private var bitmapRoot: GlassRootBitmap? = null
    private var colorSource: BlurredBackgroundSourceColor? = null
    private var baseProvider: BlurredBackgroundColorProvider = GlassProviders.pill(
        WColor.Background
    )
    private var tintProvider: GlassProvider? = null
    private var pill: BlurredBackgroundDrawable? = null
    private var drawn: Drawable? = null
    private val radii = FloatArray(4)
    private var thickness = 0
    private var intensity: Float? = null
    private var bottomInset = 0f
    private var targetRect: RectF? = null

    internal var target: View? = null
        private set
    private var drawInFront = false
    private val targetLayoutListener = OnLayoutChangeListener { _, _, _, _, _, _, _, _, _ ->
        syncSizeFromTarget()
        syncFromTarget()
    }
    private val preDrawListener = ViewTreeObserver.OnPreDrawListener {
        syncFromTarget()
        true
    }

    internal val renderNodeDrawable: BlurredBackgroundDrawableRenderNode?
        get() = pill as? BlurredBackgroundDrawableRenderNode

    internal val blurDrawable: BlurredBackgroundDrawable?
        get() = pill

    init {
        id = generateViewId()
        setWillNotDraw(false)
        rebuildDrawable()
    }

    // ── Configuration ────────────────────────────────────────────────────────

    /** Blurs [root]; `null` renders a solid pill. Re-targets when called again. */
    fun setupWith(root: ViewGroup?) {
        if (this.root === root && pill != null) return
        this.root = root
        rebuildDrawable()
    }

    fun setProvider(provider: BlurredBackgroundColorProvider) {
        baseProvider = provider
        applyProvider()
    }

    fun setOverlayColor(color: WColor, alpha: Float? = null) {
        val provider = when (alpha) {
            null -> GlassProviders.pill(color)
            else -> GlassProvider({ color.color }, { alpha })
        }
        setProvider(provider)
    }

    /** A raw color overriding the provider (NFT palettes); `null` restores it. */
    fun setTintOverlayColor(color: Int?) {
        tintProvider = color?.let { tint ->
            (baseProvider as? GlassProvider)?.withColor(tint) ?: GlassProviders.pill(tint)
        }
        applyProvider()
    }

    fun setRadius(radius: Float) {
        setRadius(radius, radius, radius, radius)
    }

    fun setRadius(topLeft: Float, topRight: Float, bottomRight: Float, bottomLeft: Float) {
        radii[0] = topLeft
        radii[1] = topRight
        radii[2] = bottomRight
        radii[3] = bottomLeft
        pill?.setRadius(topLeft, topRight, bottomRight, bottomLeft)
        invalidate()
    }

    /** Shrinks the pill from the bottom, for targets whose lower part is covered. */
    fun setBottomInset(inset: Float) {
        if (bottomInset == inset) return
        bottomInset = inset
        applyBounds()
    }

    /** Bevel depth of the refraction edge in px; 0 keeps the default. */
    fun setThickness(px: Int) {
        thickness = px
        pill?.setThickness(px)
        invalidate()
    }

    fun setIntensity(value: Float) {
        intensity = value
        pill?.setIntensity(value)
        invalidate()
    }

    /** Manual placement in this view's coordinates, for pills driven by an animation. */
    fun setTargetRect(left: Float, top: Float, right: Float, bottom: Float, cornerRadius: Float) {
        val rect = targetRect ?: RectF().also { targetRect = it }
        rect.set(left, top, right, bottom)
        setRadius(cornerRadius)
        applyBounds()
    }

    // ── Drawable ─────────────────────────────────────────────────────────────

    private fun rebuildDrawable() {
        detachFromRoot()
        colorSource = null

        val root = root
        val newPill: BlurredBackgroundDrawable
        if (root != null && Blur3Settings.isRenderNodeGlassAvailable() &&
            Blur3Settings.isBlurEnabled()
        ) {
            val glassRoot = GlassRoot.of(root)
            this.glassRoot = glassRoot
            newPill = glassRoot.factory(flavor, liquidGlass).create(this, activeProvider(), true)
            if (isAttachedToWindow) glassRoot.attach(this)
        } else if (root != null && Blur3Settings.isBlurEnabled()) {
            val bitmapRoot = GlassRootBitmap.of(root)
            this.bitmapRoot = bitmapRoot
            newPill = bitmapRoot.source.createDrawable()
            newPill.setColorProvider(activeProvider())
            if (isAttachedToWindow) bitmapRoot.attach(this)
        } else {
            val source = BlurredBackgroundSourceColor().apply { color = fallbackSourceColor() }
            colorSource = source
            newPill = source.createDrawable()
            newPill.setColorProvider(activeProvider())
        }

        newPill.setRadius(radii[0], radii[1], radii[2], radii[3])
        newPill.setPadding(glassPadding)
        if (thickness > 0) newPill.setThickness(thickness)
        intensity?.let { newPill.setIntensity(it) }
        newPill.callback = this
        pill = newPill
        applyStrokeWidths()

        val side = fadeSide
        drawn = if (side != null && ViewConstants.TOOLBAR_RADIUS != 0f) {
            BlurredBackgroundWithFadeDrawable(newPill).apply {
                setFadeHeight(
                    if (side ==
                        FadeSide.TOP
                    ) {
                        FADE_HEIGHT_DP.dp
                    } else {
                        -FADE_HEIGHT_DP.dp
                    },
                    false
                )
                callback = this@WGlassView
            }
        } else {
            newPill
        }
        drawn?.alpha = (alpha * 255).roundToInt()
        applyBounds()
        invalidate()
    }

    private fun activeProvider(): BlurredBackgroundColorProvider = tintProvider ?: baseProvider

    private fun fallbackSourceColor(): Int =
        if (Color.alpha(activeProvider().backgroundColor) == 0) {
            Color.TRANSPARENT
        } else {
            WColor.Background.color
        }

    private fun applyProvider() {
        pill?.setColorProvider(activeProvider())
        invalidate()
    }

    private fun applyStrokeWidths() {
        val pill = pill ?: return
        when (style) {
            Style.PILL -> pill.setStrokeWidth(1f.dp, (2 / 3f).dp)
            Style.PANEL -> pill.setStrokeWidth(0.55f.dp, 0.55f.dp)
        }
        invalidate()
    }

    private fun applyBounds() {
        val drawn = drawn ?: return
        val rect = targetRect
        if (rect != null) {
            drawn.setBounds(
                (rect.left - glassPadding).roundToInt(),
                (rect.top - glassPadding).roundToInt(),
                (rect.right + glassPadding).roundToInt(),
                (rect.bottom + glassPadding - bottomInset).roundToInt()
            )
        } else {
            drawn.setBounds(0, 0, width, (height - bottomInset).roundToInt())
        }
        invalidate()
    }

    private fun detachFromRoot() {
        withGlassRoot { it.detach(this) }
        glassRoot = null
        bitmapRoot?.detach(this)
        bitmapRoot = null
    }

    /** [glassRoot] is only ever non-null on API 31+, but lint needs to see the check. */
    private inline fun withGlassRoot(block: (GlassRoot) -> Unit) {
        val glassRoot = glassRoot ?: return
        if (Blur3Settings.isRenderNodeGlassAvailable()) block(glassRoot)
    }

    /**
     * True when the engine no longer matches the settings, or is no longer the registry's live
     * instance for [root]. Attaching to a superseded instance would run two capture engines on
     * one root, each excluding only its own consumers — the other's capture then records this
     * view's blur chain and the display lists form a cycle.
     */
    private fun rootIsStale(): Boolean {
        val root = root
        val blurs = root != null && Blur3Settings.isBlurEnabled()
        val wantsNode = blurs && Blur3Settings.isRenderNodeGlassAvailable()
        val wantsBitmap = blurs && !Blur3Settings.isRenderNodeGlassAvailable()
        if ((glassRoot != null) != wantsNode || (bitmapRoot != null) != wantsBitmap) return true
        if (root == null) return false
        var stale = false
        withGlassRoot { stale = GlassRoot.of(root) !== it }
        bitmapRoot?.let { stale = stale || GlassRootBitmap.of(root) !== it }
        return stale
    }

    // ── View ─────────────────────────────────────────────────────────────────

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        applyBounds()
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        if (rootIsStale()) {
            rebuildDrawable()
        } else {
            withGlassRoot { it.attach(this) }
            bitmapRoot?.attach(this)
        }
        target?.let {
            it.addOnLayoutChangeListener(targetLayoutListener)
            viewTreeObserver.addOnPreDrawListener(preDrawListener)
            syncSizeFromTarget()
            syncFromTarget()
        }
    }

    override fun onDetachedFromWindow() {
        target?.let {
            it.removeOnLayoutChangeListener(targetLayoutListener)
            viewTreeObserver.removeOnPreDrawListener(preDrawListener)
        }
        withGlassRoot { it.detach(this) }
        bitmapRoot?.detach(this)
        super.onDetachedFromWindow()
    }

    override fun onDraw(canvas: Canvas) {
        if (GlassCapture.capturing) {
            postInvalidateOnAnimation()
            return
        }
        val drawn = drawn ?: return
        if (drawInFront) {
            val path = pill?.path ?: return
            canvas.save()
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                canvas.clipOutPath(path)
            } else {
                @Suppress("DEPRECATION")
                canvas.clipPath(path, android.graphics.Region.Op.DIFFERENCE)
            }
            drawn.draw(canvas)
            canvas.restore()
        } else {
            drawn.draw(canvas)
        }
    }

    override fun hasOverlappingRendering(): Boolean = false

    override fun onSetAlpha(alpha: Int): Boolean {
        drawn?.alpha = alpha
        return true
    }

    override fun verifyDrawable(who: Drawable): Boolean =
        who === drawn || who === pill || super.verifyDrawable(who)

    override fun updateTheme() {
        (baseProvider as? GlassProvider)?.updateColors()
        tintProvider?.updateColors()
        colorSource?.color = fallbackSourceColor()

        if (rootIsStale()) {
            rebuildDrawable()
        } else {
            pill?.updateColors()
            withGlassRoot { it.updateTheme() }
            invalidate()
        }
    }

    // ── Halo mode ────────────────────────────────────────────────────────────

    private fun syncSizeFromTarget() {
        val target = target ?: return
        val w = target.width
        val h = target.height
        if (w == 0 || h == 0) return
        val lp = layoutParams ?: return
        val needW = w + glassPadding * 2
        val needH = h + glassPadding * 2
        if (lp.width != needW || lp.height != needH) {
            lp.width = needW
            lp.height = needH
            layoutParams = lp
        }
    }

    internal fun syncFromTarget() {
        val target = target ?: return
        if (target.parent !== parent) return
        x = target.x - glassPadding
        y = target.y - glassPadding
        pivotX = glassPadding + target.pivotX
        pivotY = glassPadding + target.pivotY
        scaleX = target.scaleX
        scaleY = target.scaleY
        alpha = target.alpha
        visibility = target.visibility
    }

    companion object {
        const val GLASS_PADDING_DP = 6
        private const val FADE_HEIGHT_DP = 10

        /**
         * Places a glass halo under [target] (or over it, punched out, with [drawInFront]) and
         * keeps it in sync with the target's bounds, transform, alpha and visibility.
         */
        fun attachTo(
            target: View,
            cornerRadius: Float,
            provider: BlurredBackgroundColorProvider,
            root: ViewGroup?,
            flavor: GlassFlavor = GlassFlavor.GLASS,
            drawInFront: Boolean = false
        ): WGlassView {
            val parent = target.parent as? ViewGroup
                ?: throw IllegalStateException("target must be attached to a ViewGroup")
            val view = WGlassView(target.context).apply {
                this.target = target
                this.drawInFront = drawInFront
                this.flavor = flavor
                glassPadding = GLASS_PADDING_DP.dp
                setRadius(cornerRadius)
                setProvider(provider)
            }
            val targetIndex = parent.indexOfChild(target)
            val insertIndex = (if (drawInFront) targetIndex + 1 else targetIndex).coerceAtLeast(0)
            parent.addView(
                view,
                insertIndex,
                target.layoutParams?.let { ViewGroup.LayoutParams(it) }
                    ?: ViewGroup.LayoutParams(0, 0)
            )
            view.setupWith(root)
            view.syncSizeFromTarget()
            view.syncFromTarget()
            return view
        }
    }
}
