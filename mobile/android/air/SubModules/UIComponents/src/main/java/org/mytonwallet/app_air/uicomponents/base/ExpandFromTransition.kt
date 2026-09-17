package org.mytonwallet.app_air.uicomponents.base

import android.animation.ValueAnimator
import android.graphics.Canvas
import android.graphics.ColorFilter
import android.graphics.Paint
import android.graphics.PixelFormat
import android.graphics.Rect
import android.graphics.RectF
import android.graphics.drawable.Drawable
import android.view.View
import android.view.ViewGroup
import android.view.ViewOutlineProvider
import androidx.core.animation.doOnCancel
import androidx.core.animation.doOnEnd
import androidx.core.view.children
import kotlin.math.min
import kotlin.math.roundToInt
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.glass.WGlassView
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.helpers.WInterpolator

/**
 * Grows a bottom-sheet nav out of an origin view and shrinks it back (see
 * [WWindow.PresentAnimation.ExpandFrom]). The nav is scaled about a pivot inside it, translated
 * so the pivot rides from the origin to the resting frame, and clipped to a round rect that
 * morphs from the origin's shape to the sheet's. While the shape is still origin-sized the origin
 * itself, scaled onto the shape, cross-fades with the nav; a fill then hides the sheet's content
 * until it has grown.
 */
internal class ExpandFromTransition private constructor(
    private val nav: WNavigationController,
    origin: Rect,
    // Faded out as the sheet starts growing and back in as it collapses; hidden in between (or
    // until the sheet is gone, see [WWindow.forgetNav]).
    private val originView: View?,
    originCornerRadius: Float?,
    fillColor: Int?,
    private val sheetRadius: Float,
    // Where the sheet's bottom edge rests; the sheet lands flat-bottomed when that is the
    // window's bottom, otherwise it floats and keeps all four corners.
    private val sheetBottom: Float,
    private val floating: Boolean
) {
    private val width = nav.width.toFloat()
    private val height = nav.height.toFloat()
    private val restingX = nav.x
    private val restingY = nav.y
    private val originWidth = origin.width().toFloat()
    private val originHeight = origin.height().toFloat()

    private val startWidth: Float
    private val startHeight: Float
    private val startScale: Float

    init {
        val fit = min(width / originWidth, height / originHeight)
        startWidth = min(originWidth * fit, width)
        startHeight = min(originHeight * fit, height)
        startScale = (1f / fit).coerceIn(0.01f, 1f)
    }

    private val pivotX = (origin.exactCenterX() - restingX)
        .coerceIn(startWidth / 2f, width - startWidth / 2f)
    private val pivotY = (origin.exactCenterY() - restingY)
        .coerceIn(startHeight / 2f, height - startHeight / 2f)
    private val offsetX = origin.exactCenterX() - (restingX + pivotX)
    private val offsetY = origin.exactCenterY() - (restingY + pivotY)
    private val originCenterX = origin.exactCenterX()
    private val originCenterY = origin.exactCenterY()
    private var originTranslationX = 0f
    private var originTranslationY = 0f

    private val originGlass: WGlassView? = originView?.let { origin ->
        (origin.parent as? ViewGroup)?.children
            ?.filterIsInstance<WGlassView>()
            ?.firstOrNull { it.target === origin }
    }
    private val startRadius =
        (originCornerRadius ?: (min(originWidth, originHeight) / 2f)) / startScale

    private val clipRect = RectF()
    private var clipRadius = 0f

    // Covers the sheet's content with a fill in the origin's color while the shape is small.
    private val fillPaint = Paint().apply { color = fillColor ?: WColor.Tint.color }

    // Drawn through the nav's ViewOverlay: nav coordinates, above every child, no layout pass.
    private val originCover = object : Drawable() {
        override fun draw(canvas: Canvas) {
            if (fillPaint.alpha == 0) return
            canvas.drawRect(bounds, fillPaint)
        }

        override fun setAlpha(alpha: Int) {
            fillPaint.alpha = alpha
        }

        override fun setColorFilter(colorFilter: ColorFilter?) {}

        @Deprecated("Deprecated in Java")
        override fun getOpacity(): Int = PixelFormat.TRANSLUCENT
    }

    fun begin() {
        originView?.let {
            originTranslationX = it.translationX
            originTranslationY = it.translationY
        }
        originGlass?.holdsPart = true
        nav.pivotX = pivotX
        nav.pivotY = pivotY
        originCover.setBounds(0, 0, width.roundToInt(), height.roundToInt())
        nav.overlay.add(originCover)
        nav.outlineProvider = object : ViewOutlineProvider() {
            // Only rect / round-rect outlines can clip (Outline.canClip), so the flat bottom
            // is achieved by pushing the rect's bottom corners below the nav instead.
            override fun getOutline(view: View, outline: android.graphics.Outline) {
                outline.setRoundRect(
                    clipRect.left.roundToInt(),
                    clipRect.top.roundToInt(),
                    clipRect.right.roundToInt(),
                    clipRect.bottom.roundToInt(),
                    clipRadius
                )
            }
        }
        nav.clipToOutline = true
        apply(0f, 0f)
    }

    fun apply(expansion: Float, growth: Float) {
        this.expansion = expansion
        this.growth = growth
        // The spring overshoots both ends; keep the scale positive when it dips below 0.
        val scale = (startScale + (1f - startScale) * growth).coerceAtLeast(0.01f)
        nav.scaleX = scale
        nav.scaleY = scale
        nav.x = restingX + offsetX * (1f - expansion)
        // Over the last radius of its travel a non-floating nav's bottom edge is pinned to the
        // window's bottom while the bottom corners slide out of the clip, so the sheet lands
        // flat-bottomed without its own bounds ever showing a cut edge; until then it flies as a
        // rounded card. A floating sheet flies as a rounded card all the way.
        var y = restingY + offsetY * (1f - expansion)
        val gapToBottom = sheetBottom - (y + pivotY + (height - pivotY) * scale)
        val landing =
            if (floating) 0f else (1f - gapToBottom / (sheetRadius * scale)).coerceIn(0f, 1f)
        if (landing > 0f && gapToBottom > 0f) y += gapToBottom
        nav.y = y
        val halfWidth = startWidth / 2f
        val halfHeight = startHeight / 2f
        clipRadius = (startRadius + (sheetRadius - startRadius) * growth).coerceAtLeast(0f)
        // The rect grows from the start shape to the full nav; see [landing] for the bottom.
        val bottomPush = sheetRadius * landing
        clipRect.set(
            (pivotX - halfWidth) * (1f - growth),
            (pivotY - halfHeight) * (1f - growth),
            (pivotX + halfWidth) + (width - (pivotX + halfWidth)) * growth,
            (pivotY + halfHeight) + (height - (pivotY + halfHeight)) * growth + bottomPush
        )
        nav.invalidateOutline()
        // The origin is gone by 15% of the growth, well before the sheet's content shows
        // through the fill (45%), so it never appears inside the sheet.
        originCover.alpha = ((1f - growth / 0.45f).coerceIn(0f, 1f) * 255).roundToInt()
        originCover.invalidateSelf()
        val reveal = (growth / 0.15f).coerceIn(0f, 1f)
        nav.alpha = reveal
        originView?.let { origin ->
            val left = nav.x + pivotX + (clipRect.left - pivotX) * scale
            val top = y + pivotY + (clipRect.top - pivotY) * scale
            val right = nav.x + pivotX + (clipRect.right - pivotX) * scale
            val bottom = y + pivotY + (clipRect.bottom - pivotY) * scale
            origin.translationX = originTranslationX + (left + right) / 2f - originCenterX
            origin.translationY = originTranslationY + (top + bottom) / 2f - originCenterY
            origin.scaleX = (right - left) / originWidth
            origin.scaleY = (bottom - top) / originHeight
            origin.alpha = 1f - reveal
        }
    }

    // [showOrigin] brings the origin view back; only a transition that ended collapsed does so,
    // a presented sheet keeps it hidden.
    fun end(showOrigin: Boolean) {
        nav.alpha = 1f
        nav.scaleX = 1f
        nav.scaleY = 1f
        nav.x = restingX
        nav.y = restingY
        nav.pivotX = width / 2f
        nav.pivotY = height / 2f
        nav.clipToOutline = false
        nav.outlineProvider = ViewOutlineProvider.BACKGROUND
        nav.overlay.remove(originCover)
        originView?.let {
            it.translationX = originTranslationX
            it.translationY = originTranslationY
            it.scaleX = 1f
            it.scaleY = 1f
            it.alpha = if (showOrigin) 1f else 0f
        }
        originGlass?.holdsPart = false
    }

    // Runs the transition from [from] to [to] on two springs sharing one clock: the shape on a
    // stiff, well-damped one, the position on a softer one that arrives later and settles with
    // a little overshoot. [onFrame] gets the (overshooting) position value. Ends (or cancels)
    // with the nav restored to its resting state.
    var expansion = 0f
        private set
    var growth = 0f
        private set

    private var begun = false

    // Set while an animator is being handed over to [reverse]: its cancel must neither restore
    // the nav nor report a cancel, the transition keeps running.
    private var handingOver = false

    fun run(
        from: Float,
        to: Float,
        onFrame: (expansion: Float) -> Unit,
        onCancel: () -> Unit,
        onEnd: () -> Unit
    ): ValueAnimator = run(from, from, to, onFrame, onCancel, onEnd)

    private fun run(
        fromExpansion: Float,
        fromGrowth: Float,
        to: Float,
        onFrame: (expansion: Float) -> Unit,
        onCancel: () -> Unit,
        onEnd: () -> Unit
    ): ValueAnimator {
        if (!begun) {
            begun = true
            begin()
        }
        val travelSpring = WInterpolator.spring(TRAVEL_DAMPING, TRAVEL_STIFFNESS)
        val growthSpring = WInterpolator.spring(GROWTH_DAMPING, GROWTH_STIFFNESS)
        return ValueAnimator.ofFloat(0f, 1f).apply {
            duration = AnimationConstants.SLOW_ANIMATION
            interpolator = null
            addUpdateListener {
                val time = animatedValue as Float
                val expansion =
                    fromExpansion + (to - fromExpansion) * travelSpring.getInterpolation(time)
                val growth = fromGrowth + (to - fromGrowth) * growthSpring.getInterpolation(time)
                this@ExpandFromTransition.apply(expansion, growth)
                onFrame(expansion)
            }
            doOnCancel {
                removeAllListeners()
                WGlobalStorage.decDoNotSynchronize()
                if (handingOver) return@doOnCancel
                this@ExpandFromTransition.end(showOrigin = false)
                onCancel()
            }
            doOnEnd {
                this@ExpandFromTransition.end(showOrigin = to == 0f)
                WGlobalStorage.decDoNotSynchronize()
                onEnd()
            }
            WGlobalStorage.incDoNotSynchronize()
            start()
        }
    }

    // Turns a running [animator] of this transition around from wherever it is, springing back
    // to the origin; the nav keeps its current frame, nothing snaps.
    fun reverse(
        animator: ValueAnimator,
        onFrame: (expansion: Float) -> Unit,
        onCancel: () -> Unit,
        onEnd: () -> Unit
    ): ValueAnimator {
        handingOver = true
        animator.cancel()
        handingOver = false
        return run(expansion, growth, 0f, onFrame, onCancel, onEnd)
    }

    companion object {
        // Shape: quick and nearly critically damped. Position: softer, lands later with a
        // visible settle.
        private const val GROWTH_DAMPING = 0.85f
        private const val GROWTH_STIFFNESS = 14f
        private const val TRAVEL_DAMPING = 0.76f
        private const val TRAVEL_STIFFNESS = 9f

        // Builds the transition of [nav] (laid out at its resting frame) out of [animation]'s
        // origin, or null when the origin is not on screen.
        fun create(
            window: WWindow,
            nav: WNavigationController,
            animation: WWindow.PresentAnimation.ExpandFrom
        ): ExpandFromTransition? {
            val originView = animation.originView
            val origin = originRectOf(window, originView) ?: return null
            return ExpandFromTransition(
                nav,
                origin,
                originView,
                animation.cornerRadius,
                animation.fillColor,
                sheetCornerRadius(),
                sheetBottom = window.windowView.height.toFloat() - nav.floatingSheetBottomGap,
                floating = nav.floatingSheetInset > 0
            )
        }

        private fun sheetCornerRadius(): Float =
            if (ViewConstants.BLOCK_RADIUS == 0f) 24f.dp else ViewConstants.BLOCK_RADIUS.dp

        // [view]'s frame in the window view's coordinates, translations included.
        private fun originRectOf(window: WWindow, view: View): Rect? {
            if (!view.isAttachedToWindow || view.width == 0) return null
            val viewLocation = IntArray(2)
            val rootLocation = IntArray(2)
            view.getLocationInWindow(viewLocation)
            window.windowView.getLocationInWindow(rootLocation)
            val left = viewLocation[0] - rootLocation[0]
            val top = viewLocation[1] - rootLocation[1]
            return Rect(left, top, left + view.width, top + view.height)
        }
    }
}
