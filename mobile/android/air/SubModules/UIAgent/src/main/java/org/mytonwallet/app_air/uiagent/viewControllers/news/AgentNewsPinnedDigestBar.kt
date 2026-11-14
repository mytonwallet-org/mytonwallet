package org.mytonwallet.app_air.uiagent.viewControllers.news

import android.animation.Animator
import android.animation.AnimatorListenerAdapter
import android.animation.TimeInterpolator
import android.animation.ValueAnimator
import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Camera
import android.graphics.Canvas
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.RectF
import android.os.Build
import android.text.TextPaint
import android.text.TextUtils
import android.view.View
import android.view.accessibility.AccessibilityNodeInfo
import android.view.animation.PathInterpolator
import kotlin.math.ceil
import kotlin.math.max
import kotlin.math.min
import org.mytonwallet.app_air.uicomponents.drawable.WRippleDrawable
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.sp
import org.mytonwallet.app_air.uicomponents.helpers.CubicBezierInterpolator
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.typeface
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.walletbasecontext.DEBUG_MODE
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage

/**
 * The feed's daily digests as pinned messages, on the glass capsule the feed attaches under its header: a stripe of
 * one bar per digest on the leading edge, the oldest at the top and the shown one lit, the digest's day as the title
 * and its headlines as the text. As the bar shows another digest it moves as the web app's bar does, after Telegram
 * Web's `HeaderPinnedMessage`: the title rolls the characters after the part it keeps (`AnimatedCounter`) and the text
 * slides a whole line (`slideVerticalFade`), both in from below for a newer digest and from above for an older one,
 * and the lit bar slides along the stripe (`PinnedMessageNavigation`).
 */
@SuppressLint("ViewConstructor")
class AgentNewsPinnedDigestBar(context: Context) :
    View(context),
    WThemedView {
    data class Content(val title: String, val text: String, val index: Int, val count: Int)

    enum class Transition { NEWER, OLDER }

    var content: Content? = null
        private set

    // The text's slide: the text that was shown and the way the new text and title come in, 1 from below and -1 from
    // above
    private var outgoing: Content? = null
    private var slideDirection = 1f
    private var slideProgress = 1f
    private var slideAnimator: ValueAnimator? = null

    // The title's roll: the title that was shown, whose characters after the part both titles start with roll away as
    // the new ones roll in
    private var previousTitle: String? = null
    private var rollProgress = 1f
    private var rollAnimator: ValueAnimator? = null

    // The stripe: where its lit bar and track stand, and where they move from
    private var stripe: StripeLayout? = null
    private var stripeFrom: StripeLayout? = null
    private var stripeProgress = 1f
    private var stripeAnimator: ValueAnimator? = null

    private val titlePaint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
        textSize = FONT_SIZE.sp
        typeface = WFont.Medium.typeface
    }
    private val textPaint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
        textSize = FONT_SIZE.sp
        typeface = WFont.Regular.typeface
    }

    // Read again for every line drawn, so that the animations' frames don't allocate them
    private val fontMetrics = Paint.FontMetrics()
    private val trackPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val markPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val barRect = RectF()
    private val camera = Camera()
    private val charMatrix = Matrix()
    private val ripple = WRippleDrawable.create(CORNER_RADIUS.dp.toFloat())

    private val canAnimate: Boolean
        get() {
            val isSystemMotionOn = !DEBUG_MODE ||
                Build.VERSION.SDK_INT < Build.VERSION_CODES.O ||
                ValueAnimator.areAnimatorsEnabled()
            return WGlobalStorage.getAreAnimationsActive() && isSystemMotionOn
        }

    init {
        isClickable = true
        isFocusable = true
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_YES
        background = ripple
        updateTheme()
    }

    fun setContent(content: Content, transition: Transition?) {
        if (content == this.content) return
        val previous = this.content
        this.content = content
        contentDescription = "${content.title}, ${content.text}"
        // A stripe on its way moves on from where it shows, as a CSS transition does
        val shownStripe = getShownStripe()
        slideAnimator?.cancel()
        rollAnimator?.cancel()
        stripeAnimator?.cancel()
        val newStripe = layoutStripe(content.index, content.count)
        val isAnimated = transition != null && isAttachedToWindow && canAnimate
        if (!isAnimated || previous == null) {
            stripe = newStripe
            invalidate()
            return
        }
        outgoing = previous
        slideDirection = if (transition == Transition.OLDER) -1f else 1f
        slideAnimator = animate(SLIDE_DURATION_MS, SLIDE_INTERPOLATOR, { slideProgress = it }) {
            outgoing = null
        }
        if (previous.title != content.title && !LocaleController.isRTL) {
            previousTitle = previous.title
            rollAnimator = animate(ROLL_DURATION_MS, ROLL_INTERPOLATOR, { rollProgress = it }) {
                previousTitle = null
            }
        }
        stripe = newStripe
        stripeFrom = shownStripe?.takeIf { it.count == content.count }
        if (stripeFrom != null) {
            stripeAnimator =
                animate(STRIPE_DURATION_MS, STRIPE_INTERPOLATOR, { stripeProgress = it }) {
                    stripeFrom = null
                }
        }
    }

    private fun animate(
        duration: Long,
        interpolator: TimeInterpolator,
        onFrame: (Float) -> Unit,
        onEnd: () -> Unit
    ) = ValueAnimator.ofFloat(0f, 1f).apply {
        this.duration = duration
        this.interpolator = interpolator
        addUpdateListener {
            onFrame(it.animatedValue as Float)
            invalidate()
        }
        addListener(object : AnimatorListenerAdapter() {
            override fun onAnimationEnd(animation: Animator) {
                onFrame(1f)
                onEnd()
                invalidate()
            }
        })
        onFrame(0f)
        start()
    }

    override fun updateTheme() {
        titlePaint.color = WColor.Tint.color
        textPaint.color = WColor.PrimaryText.color
        val tint = WColor.Tint.color
        trackPaint.color = tint
        trackPaint.alpha = (tint ushr 24) * TRACK_ALPHA / 255
        markPaint.color = tint
        ripple.rippleColor = WColor.BackgroundRipple.color
        invalidate()
    }

    override fun onInitializeAccessibilityNodeInfo(info: AccessibilityNodeInfo) {
        super.onInitializeAccessibilityNodeInfo(info)
        info.className = android.widget.Button::class.java.name
    }

    override fun onDetachedFromWindow() {
        super.onDetachedFromWindow()
        slideAnimator?.cancel()
        rollAnimator?.cancel()
        stripeAnimator?.cancel()
    }

    override fun onDraw(canvas: Canvas) {
        val content = content ?: return
        val isRtl = LocaleController.isRTL
        val stripeX = if (isRtl) width - STRIPE_INSET.dp - STRIPE_WIDTH.dp else STRIPE_INSET.dp
        drawStripe(canvas, stripeX.toFloat())
        val textStart = (STRIPE_INSET + STRIPE_WIDTH + STRIPE_TEXT_GAP).dp
        val textWidth = max(0, width - textStart - TRAILING_INSET.dp)
        val textX = (if (isRtl) TRAILING_INSET.dp else textStart).toFloat()
        drawTitle(canvas, content.title, textX, textWidth)
        drawText(canvas, content, textX, textWidth)
    }

    // `slideVerticalFade`: the text's line clips the text as it slides by its own height
    private fun drawText(canvas: Canvas, content: Content, x: Float, width: Int) {
        val top = TEXT_TOP.dp
        val lineHeight = getLineHeight(textPaint)
        canvas.save()
        canvas.clipRect(x, top, x + width, top + lineHeight)
        val outgoing = outgoing
        if (outgoing == null) {
            drawLine(canvas, content.text, textPaint, x, width, top, 255f)
        } else {
            val progress = slideProgress
            val leavingTop = top - slideDirection * lineHeight * progress
            drawLine(canvas, outgoing.text, textPaint, x, width, leavingTop, (1f - progress) * 255f)
            val comingTop = top + slideDirection * lineHeight * (1f - progress)
            drawLine(canvas, content.text, textPaint, x, width, comingTop, progress * 255f)
        }
        canvas.restore()
    }

    /**
     * `AnimatedCounter`'s roll: the part both titles start with, as "November " of November 9 and November 10, stays,
     * and each character after it rolls in the way the text comes as the old ones roll away the other way, all turned
     * in a close perspective.
     */
    private fun drawTitle(canvas: Canvas, title: String, x: Float, width: Int) {
        val top = TITLE_TOP.dp
        val lineHeight = getLineHeight(titlePaint)
        canvas.save()
        canvas.clipRect(x, top, x + width, top + lineHeight)
        val previous = previousTitle
        if (previous == null) {
            drawLine(canvas, title, titlePaint, x, width, top, 255f)
            canvas.restore()
            return
        }
        val kept = title.commonPrefixWith(previous)
        drawLine(canvas, kept, titlePaint, x, width, top, 255f)
        val tailX = x + titlePaint.measureText(kept)
        val oldTail = previous.substring(kept.length)
        val newTail = title.substring(kept.length)
        val distance = slideDirection * ROLL_DISTANCE.dp
        val angle = slideDirection * ROLL_ANGLE
        val progress = rollProgress
        val rest = 1f - progress
        drawRolledTail(canvas, oldTail, tailX, top, lineHeight) { box, char ->
            drawRolledChar(canvas, char, box, -distance * progress, angle * progress, rest * 255f)
        }
        drawRolledTail(canvas, newTail, tailX, top, lineHeight) { box, char ->
            drawRolledChar(canvas, char, box, distance * rest, -angle * rest, progress * 255f)
        }
        canvas.restore()
    }

    private inline fun drawRolledTail(
        canvas: Canvas,
        tail: String,
        x: Float,
        top: Float,
        height: Float,
        drawChar: (CharBox, String) -> Unit
    ) {
        var charX = x
        var index = 0
        while (index < tail.length) {
            val end = index + Character.charCount(tail.codePointAt(index))
            val char = tail.substring(index, end)
            val charWidth = titlePaint.measureText(char)
            drawChar(CharBox(charX, charWidth, top, height), char)
            charX += charWidth
            index = end
        }
    }

    private class CharBox(val x: Float, val width: Float, val top: Float, val height: Float)

    // A character moved by `offsetY` and turned by `angle` about its box's middle, as CSS's
    // `perspective(10px) translateY(…) rotateX(…)`, whose positive angle turns the top away
    private fun drawRolledChar(
        canvas: Canvas,
        char: String,
        box: CharBox,
        offsetY: Float,
        angle: Float,
        alpha: Float
    ) {
        canvas.save()
        if (offsetY != 0f || angle != 0f) {
            camera.save()
            camera.setLocation(0f, 0f, -ROLL_PERSPECTIVE.dp / CAMERA_UNITS_PER_INCH)
            camera.translate(0f, -offsetY, 0f)
            camera.rotateX(-angle)
            camera.getMatrix(charMatrix)
            camera.restore()
            val centerX = box.x + box.width / 2f
            val centerY = box.top + box.height / 2f
            charMatrix.preTranslate(-centerX, -centerY)
            charMatrix.postTranslate(centerX, centerY)
            canvas.concat(charMatrix)
        }
        val color = titlePaint.color
        titlePaint.alpha = (alpha * (color ushr 24) / 255f).toInt().coerceIn(0, 255)
        canvas.drawText(char, box.x, box.top - getAscent(titlePaint), titlePaint)
        titlePaint.color = color
        canvas.restore()
    }

    private fun drawLine(
        canvas: Canvas,
        text: String,
        paint: TextPaint,
        x: Float,
        width: Int,
        top: Float,
        alpha: Float
    ) {
        val line = TextUtils.ellipsize(text, paint, width.toFloat(), TextUtils.TruncateAt.END)
        val color = paint.color
        paint.alpha = (alpha * (color ushr 24) / 255f).toInt().coerceIn(0, 255)
        val lineX = if (LocaleController.isRTL) {
            x + width - paint.measureText(line, 0, line.length)
        } else {
            x
        }
        canvas.drawText(line, 0, line.length, lineX, top - getAscent(paint), paint)
        paint.color = color
    }

    private fun getLineHeight(paint: TextPaint): Float {
        paint.getFontMetrics(fontMetrics)
        return ceil(fontMetrics.descent - fontMetrics.ascent)
    }

    private fun getAscent(paint: TextPaint): Float {
        paint.getFontMetrics(fontMetrics)
        return fontMetrics.ascent
    }

    // `PinnedMessageNavigation`: the bars in a 36 dp window, the lit one over them, and the track scrolling the window
    private fun drawStripe(canvas: Canvas, x: Float) {
        val shown = getShownStripe() ?: return
        val windowTop = (height - STRIPE_WINDOW.dp) / 2f
        val barWidth = STRIPE_WIDTH.dp.toFloat()
        val radius = STRIPE_RADIUS.dp.toFloat()
        canvas.save()
        canvas.clipRect(x, windowTop, x + barWidth, windowTop + STRIPE_WINDOW.dp)
        canvas.translate(x, windowTop - shown.trackShift.dp)
        if (shown.count <= 1) {
            barRect.set(0f, 0f, barWidth, STRIPE_WINDOW.dp.toFloat())
            canvas.drawRoundRect(barRect, radius, radius, markPaint)
            canvas.restore()
            return
        }
        shown.bars.forEach { (top, barHeight) ->
            barRect.set(0f, top.dp, barWidth, (top + barHeight).dp)
            canvas.drawRoundRect(barRect, radius, radius, trackPaint)
        }
        // The lit bar shows only where the bars are, as the track's clip path cuts it on the web
        val markTop = shown.markTop.dp
        val markBottom = (shown.markTop + shown.markHeight).dp
        shown.bars.forEach { (top, barHeight) ->
            val partTop = max(markTop, top.dp)
            val partBottom = min(markBottom, (top + barHeight).dp)
            if (partBottom <= partTop) return@forEach
            barRect.set(0f, partTop, barWidth, partBottom)
            canvas.drawRoundRect(barRect, radius, radius, markPaint)
        }
        canvas.restore()
    }

    /** The stripe as it shows now, partway between two places while its lit bar and track move */
    private fun getShownStripe(): StripeLayout? {
        val to = stripe ?: return null
        val from = stripeFrom ?: return to
        val progress = stripeProgress
        return to.copy(
            markTop = from.markTop + (to.markTop - from.markTop) * progress,
            trackShift = from.trackShift + (to.trackShift - from.trackShift) * progress
        )
    }

    /** The stripe's layout in dp: its bars' tops and heights, the lit bar's, and how far the track is scrolled */
    private data class StripeLayout(
        val count: Int,
        val bars: List<Pair<Float, Float>>,
        val markTop: Float,
        val markHeight: Float,
        val trackShift: Float
    )

    // Telegram Web's `calculateMarkup`, whose `reverseIndex` is the digest's place from the oldest
    private fun layoutStripe(index: Int, count: Int): StripeLayout {
        if (count <= 1) return StripeLayout(count, emptyList(), 0f, STRIPE_WINDOW.toFloat(), 0f)
        val barHeight = when (count) {
            2 -> 17f
            3 -> 11f
            else -> 7.5f
        }
        val bars = if (count == 3) {
            listOf(0f to 11f, 12f to 12f, 25f to 11f)
        } else {
            List(count) { (barHeight + STRIPE_SPACING) * it to barHeight }
        }
        val trackHeight = if (count <= 3) {
            STRIPE_WINDOW.toFloat()
        } else {
            barHeight * count + STRIPE_SPACING * (count - 1)
        }
        val trackShift = when {
            count <= 4 || index <= 1 -> 0f
            index >= count - 2 -> trackHeight - STRIPE_WINDOW
            else -> (barHeight + 4f) / 2f + (index - 2) * (barHeight + STRIPE_SPACING)
        }
        val mark = bars[index.coerceIn(0, count - 1)]
        return StripeLayout(count, bars, mark.first, mark.second, trackShift)
    }

    companion object {
        // In dp and sp: a glass capsule 50 high, 8 from the screen's sides and 8 under the header, the
        // floating date 9 under it; Telegram Web's stripe, 2 wide in a 36 window, 18 in; the text 10 after the stripe
        // and 14 short of the end, the title and the text in 14 sp type, 8.3 and 26.3 from the top
        const val HEIGHT = 50
        const val CORNER_RADIUS = HEIGHT / 2
        const val SIDE_INSET = 8
        const val TOP_SPACING = 8
        const val DAY_CAPSULE_SPACING = 9
        private const val STRIPE_INSET = 18
        private const val STRIPE_WIDTH = 2
        private const val STRIPE_RADIUS = 1
        private const val STRIPE_WINDOW = 36
        private const val STRIPE_SPACING = 2f
        private const val STRIPE_TEXT_GAP = 10
        private const val TRAILING_INSET = 14
        private const val TITLE_TOP = 8.3f
        private const val TEXT_TOP = 26.3f
        private const val FONT_SIZE = 14f

        // Telegram Web's motion: the text's `--slide-transition`; the counter's roll of 10 px and 30° in a 10 px
        // perspective, eased out; the stripe's 0.25 s ease-in-out; the stripe's unlit bars at a quarter
        private const val SLIDE_DURATION_MS = 300L
        private val SLIDE_INTERPOLATOR = PathInterpolator(0.25f, 1f, 0.5f, 1f)
        private const val ROLL_DURATION_MS = 200L
        private val ROLL_INTERPOLATOR = PathInterpolator(0f, 0f, 0.58f, 1f)
        private const val ROLL_DISTANCE = 10
        private const val ROLL_ANGLE = 30f
        private const val ROLL_PERSPECTIVE = 10
        private const val STRIPE_DURATION_MS = 250L
        private val STRIPE_INTERPOLATOR = CubicBezierInterpolator.EASE_BOTH
        private const val TRACK_ALPHA = 64

        // `Camera` places itself in inches of 72 units
        private const val CAMERA_UNITS_PER_INCH = 72f
    }
}
