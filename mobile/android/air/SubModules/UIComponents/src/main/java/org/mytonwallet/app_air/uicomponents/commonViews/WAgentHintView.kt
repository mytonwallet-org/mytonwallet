package org.mytonwallet.app_air.uicomponents.commonViews

import android.animation.ValueAnimator
import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.ColorFilter
import android.graphics.LinearGradient
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PixelFormat
import android.graphics.Rect
import android.graphics.RectF
import android.graphics.Shader
import android.graphics.SweepGradient
import android.graphics.drawable.Drawable
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.LayerDrawable
import android.os.Build
import android.text.TextUtils
import android.view.Choreographer
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.view.animation.DecelerateInterpolator
import android.view.animation.LinearInterpolator
import android.view.animation.PathInterpolator
import android.widget.LinearLayout
import android.widget.TextView
import androidx.appcompat.widget.AppCompatImageView
import androidx.core.animation.doOnEnd
import kotlin.math.ceil
import kotlin.math.roundToInt
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WFrameLayout
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ThemeManager
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.utils.colorWithAlpha

@SuppressLint("ViewConstructor", "ClickableViewAccessibility")
class WAgentHintView(
    context: Context,
    title: CharSequence,
    contentVerticalPadding: Int = 10.dp,
    contentHorizontalPadding: Int = 16.dp,
    borderWidth: Float = 0.75f.dp,
    animatePressAlpha: Boolean = true,
    showsIcon: Boolean = true,
    titleMaxLines: Int = 2,
    /** Leads the title in place of the reply arrow, in the title's first color */
    private val leadingIconResId: Int? = null,
    onTap: () -> Unit
) : WFrameLayout(context) {

    companion object {
        private val LIGHT_TITLE_GRADIENT_COLORS = intArrayOf(
            0xFF005DAF.toInt(),
            0xFF007BA5.toInt(),
            0xFF7D2EBA.toInt()
        )
        private val DARK_TITLE_GRADIENT_COLORS = intArrayOf(
            0xFF6DADE6.toInt(),
            0xFF5EB6D4.toInt(),
            0xFFC48CEE.toInt()
        )
        private val TITLE_GRADIENT_POSITIONS = floatArrayOf(0f, 0.4f, 1f)

        // Stop alphas (20% / 50% / 20%) scaled by an overall 24% opacity.
        private val LIGHT_FILL_GRADIENT_COLORS = intArrayOf(
            0x0C0088FF,
            0x1F00BEFF,
            0x0CB656FF
        )

        // Stop alphas (40% / 60% / 40%) scaled by an overall 24% opacity.
        private val DARK_FILL_GRADIENT_COLORS = intArrayOf(
            0x180088FF,
            0x2500BEFF,
            0x18B656FF
        )

        // The pill's corner radius, in dp
        private const val CORNER_RADIUS = 22f

        private const val DARK_FADE_COLOR = 0xFF202020.toInt()

        // A placeholder's light band, as the Agent's loading placeholders draw it
        private const val SHIMMER_PERIOD_MS = 1600f
        private const val SHIMMER_BAND = 280
        private const val SHIMMER_LIGHT_PEAK = 0.7f
        private const val SHIMMER_DARK_PEAK = 0.14f
        private const val NANOS_PER_MS = 1_000_000f

        // How often a placeholder off screen looks whether it has come back into sight
        private const val OFF_SCREEN_CHECK_MS = 500L

        // As iOS turns a placeholder into its suggestion: the pill resizes in 360 ms on Telegram's curve, and the
        // title fades in over 220 ms
        private const val RESIZE_MS = 360L
        private const val CONTENT_FADE_MS = 220L
        private val RESIZE_CURVE = PathInterpolator(0.38f, 0.7f, 0.125f, 1f)

        private const val LEADING_ICON_SIZE = 16
        private const val DIMMED_CONTENT_ALPHA = 0.5f
    }

    private var titleGradientColors = LIGHT_TITLE_GRADIENT_COLORS

    private val titleLabel = HuggingLabel(context)

    /** The title, which a question sent from the card grows from into its bubble's text */
    val titleView: TextView
        get() = titleLabel

    private val iconView = AppCompatImageView(context).apply {
        if (leadingIconResId != null) {
            setImageResource(leadingIconResId)
        } else {
            setImageResource(org.mytonwallet.app_air.icons.R.drawable.ic_agent_hint_arrow)
            if (LocaleController.isRTL) scaleX = -1f
        }
    }
    private val bgDrawable = GradientDrawable().apply {
        cornerRadius = CORNER_RADIUS.dp
    }
    private val bgFadeDrawable = GradientDrawable(
        GradientDrawable.Orientation.TOP_BOTTOM,
        intArrayOf(0, 0)
    ).apply {
        cornerRadius = CORNER_RADIUS.dp
    }
    private val borderDrawable = GradientBorderDrawable(CORNER_RADIUS.dp, borderWidth)
    private val fillDrawable = GradientFillDrawable(CORNER_RADIUS.dp, LocaleController.isRTL)
    private val content = LinearLayout(context)
    private val initialAngle = (Math.random() * 360).toFloat()
    private val borderAnimator = ValueAnimator.ofFloat(0f, 360f).apply {
        duration = 12_000
        repeatCount = ValueAnimator.INFINITE
        interpolator = LinearInterpolator()
        addUpdateListener {
            val elapsed = it.animatedValue as Float
            borderDrawable.angle = initialAngle + elapsed
            invalidate()
        }
    }

    private val shimmerPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val shimmerMatrix = Matrix()
    private val shimmerClip = Path()
    private val shimmerInterpolator = DecelerateInterpolator()
    private var shimmerStartNanos = 0L
    private var isShimmerFrameScheduled = false
    private val shimmerVisibleRect = Rect()
    private val shimmerFrameCallback = Choreographer.FrameCallback {
        isShimmerFrameScheduled = false
        // A pill on a tab page laid out beside the selected one counts as shown while off screen
        if (windowVisibility != VISIBLE || !getGlobalVisibleRect(shimmerVisibleRect)) {
            scheduleShimmerFrame(OFF_SCREEN_CHECK_MS)
            return@FrameCallback
        }
        invalidate()
        scheduleShimmerFrame()
    }

    init {
        titleLabel.setStyle(16f, WFont.Medium)
        titleLabel.isSingleLine = titleMaxLines == 1
        titleLabel.maxLines = titleMaxLines
        titleLabel.ellipsize = TextUtils.TruncateAt.END
        titleLabel.useCustomEmoji = true
        titleLabel.text = title
        titleLabel.addOnLayoutChangeListener { _, _, _, _, _, _, _, _, _ ->
            updateTitleShader()
        }

        content.apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPaddingRelative(
                contentHorizontalPadding,
                contentVerticalPadding,
                contentHorizontalPadding,
                contentVerticalPadding
            )
            val hasIcon = showsIcon || leadingIconResId != null
            if (hasIcon) {
                val iconSize = if (leadingIconResId != null) LEADING_ICON_SIZE.dp else WRAP_CONTENT
                addView(iconView, LinearLayout.LayoutParams(iconSize, iconSize))
            }
            addView(
                titleLabel,
                LinearLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT).apply {
                    if (hasIcon) marginStart = 6.dp
                }
            )
        }

        isClickable = true
        isFocusable = true
        background = LayerDrawable(arrayOf(bgFadeDrawable, fillDrawable, bgDrawable))
        foreground = borderDrawable
        addView(content, LayoutParams(WRAP_CONTENT, WRAP_CONTENT, Gravity.CENTER_VERTICAL))
        updateTheme()

        setOnClickListener { onTap() }
        var isTouchAccepted = false
        setOnTouchListener { _, event ->
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    isTouchAccepted = alpha > 0f && !isPlaceholder
                    if (isTouchAccepted) {
                        val animator = animate().scaleX(0.97f).scaleY(0.97f)
                        if (animatePressAlpha) animator.alpha(0.82f)
                        animator.setStartDelay(0).setDuration(100).start()
                    }
                }

                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                    val shouldPerformClick = isTouchAccepted && alpha > 0f &&
                        event.action == MotionEvent.ACTION_UP
                    isTouchAccepted = false
                    val animator = animate().scaleX(1f).scaleY(1f)
                    if (animatePressAlpha && alpha > 0f) animator.alpha(1f)
                    animator.setStartDelay(0).setDuration(100).start()
                    if (shouldPerformClick) performClick()
                }
            }
            true
        }
    }

    /**
     * Stands in for a suggestion that is still loading: the pill alone, with the fill and the border a suggestion
     * has, and a light band crossing it inside the border. [revealContent] turns it into the suggestion.
     */
    var isPlaceholder = false
        set(value) {
            if (field == value) return
            field = value
            content.alpha = if (value) 0f else contentAlpha
            isClickable = !value
            isFocusable = !value
            invalidate()
            scheduleShimmerFrame()
        }

    /** A card that takes no taps for now shows its title and icon at half their opacity */
    var isDimmed = false
        set(value) {
            if (field == value) return
            field = value
            if (!isPlaceholder) content.alpha = contentAlpha
        }
    private val contentAlpha: Float
        get() = if (isDimmed) DIMMED_CONTENT_ALPHA else 1f

    // The size the pill resizes from as it turns from a placeholder into its suggestion, and how far it has
    private var resizeOrigin: Pair<Int, Int>? = null
    private var resizeProgress = 1f
    private var resizeAnimator: ValueAnimator? = null

    /**
     * Turns a placeholder into the suggestion [title]: the pill keeps its fill and border and resizes from the
     * placeholder's size to the title's, while the title and the arrow fade in after [contentDelay] ms
     */
    fun revealContent(title: CharSequence, contentDelay: Long) {
        val origin = width to height
        isPlaceholder = false
        setTitle(title)
        if (!WGlobalStorage.getAreAnimationsActive() || origin.first <= 0 || origin.second <= 0) {
            return
        }
        content.alpha = 0f
        content.animate().alpha(contentAlpha).setStartDelay(contentDelay)
            .setDuration(CONTENT_FADE_MS)
            .setInterpolator(LinearInterpolator())
            .start()
        resizeAnimator?.cancel()
        resizeOrigin = origin
        resizeProgress = 0f
        resizeAnimator = ValueAnimator.ofFloat(0f, 1f).apply {
            duration = RESIZE_MS
            interpolator = RESIZE_CURVE
            addUpdateListener {
                resizeProgress = it.animatedValue as Float
                requestLayout()
            }
            doOnEnd {
                if (resizeAnimator !== this) return@doOnEnd
                resizeAnimator = null
                resizeOrigin = null
                requestLayout()
            }
            start()
        }
    }

    // A pill on its way from a placeholder's size reports its size so far; its title already has its own
    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        super.onMeasure(widthMeasureSpec, heightMeasureSpec)
        val (fromWidth, fromHeight) = resizeOrigin ?: return
        setMeasuredDimension(
            (fromWidth + (measuredWidth - fromWidth) * resizeProgress).roundToInt(),
            (fromHeight + (measuredHeight - fromHeight) * resizeProgress).roundToInt()
        )
    }

    override fun dispatchDraw(canvas: Canvas) {
        super.dispatchDraw(canvas)
        if (isPlaceholder) drawShimmer(canvas)
    }

    // The band crosses the pill from its leading side, inside the border, which is drawn over it
    private fun drawShimmer(canvas: Canvas) {
        if (!isShimmerMoving || width <= 0 || height <= 0) return
        if (shimmerStartNanos == 0L) shimmerStartNanos = System.nanoTime()
        val elapsed = (System.nanoTime() - shimmerStartNanos) / NANOS_PER_MS
        val progress = shimmerInterpolator.getInterpolation(
            (elapsed % SHIMMER_PERIOD_MS) / SHIMMER_PERIOD_MS
        )
        val band = SHIMMER_BAND.dp.toFloat()
        val travel = -band + (width + band) * progress
        val offset = if (LocaleController.isRTL) width - travel - band else travel
        shimmerMatrix.setTranslate(offset, 0f)
        shimmerPaint.shader?.setLocalMatrix(shimmerMatrix)
        val inset = borderDrawable.width
        val radius = (CORNER_RADIUS.dp - inset).coerceAtLeast(0f)
        shimmerClip.rewind()
        shimmerClip.addRoundRect(
            inset,
            inset,
            width - inset,
            height - inset,
            radius,
            radius,
            Path.Direction.CW
        )
        canvas.save()
        canvas.clipPath(shimmerClip)
        canvas.drawRect(0f, 0f, width.toFloat(), height.toFloat(), shimmerPaint)
        canvas.restore()
    }

    private val isShimmerMoving: Boolean
        get() = isPlaceholder && isAttachedToWindow && isShown &&
            WGlobalStorage.getAreAnimationsActive() &&
            (Build.VERSION.SDK_INT < Build.VERSION_CODES.O || ValueAnimator.areAnimatorsEnabled())

    private fun scheduleShimmerFrame(delayMs: Long = 0L) {
        if (!isShimmerMoving || isShimmerFrameScheduled) return
        isShimmerFrameScheduled = true
        Choreographer.getInstance().postFrameCallbackDelayed(shimmerFrameCallback, delayMs)
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        updateBorderAnimation()
        scheduleShimmerFrame()
    }

    override fun onDetachedFromWindow() {
        borderAnimator.cancel()
        Choreographer.getInstance().removeFrameCallback(shimmerFrameCallback)
        isShimmerFrameScheduled = false
        // A pill that leaves while it turns into its suggestion shows the suggestion
        resizeAnimator?.end()
        content.animate().cancel()
        if (!isPlaceholder) content.alpha = contentAlpha
        super.onDetachedFromWindow()
    }

    override fun onVisibilityChanged(changedView: View, visibility: Int) {
        super.onVisibilityChanged(changedView, visibility)
        updateBorderAnimation()
        scheduleShimmerFrame()
    }

    fun updateTheme() {
        val isDark = ThemeManager.isDark
        bgDrawable.setColor(WColor.ThumbBackground.color.colorWithAlpha(41)) // 16%
        val fadeColor = if (isDark) DARK_FADE_COLOR else WColor.Background.color
        bgFadeDrawable.colors = intArrayOf(
            fadeColor,
            fadeColor.colorWithAlpha(0)
        )
        fillDrawable.setColors(
            if (isDark) DARK_FILL_GRADIENT_COLORS else LIGHT_FILL_GRADIENT_COLORS
        )
        titleGradientColors =
            if (isDark) DARK_TITLE_GRADIENT_COLORS else LIGHT_TITLE_GRADIENT_COLORS
        titleLabel.setTextColor(titleGradientColors[0])
        if (leadingIconResId != null) iconView.setColorFilter(titleGradientColors[0])
        updateTitleShader()
        val peak = Color.WHITE.colorWithAlpha(
            ((if (isDark) SHIMMER_DARK_PEAK else SHIMMER_LIGHT_PEAK) * 255).roundToInt()
        )
        shimmerPaint.shader = LinearGradient(
            0f,
            0f,
            SHIMMER_BAND.dp.toFloat(),
            0f,
            intArrayOf(Color.TRANSPARENT, peak, Color.TRANSPARENT),
            floatArrayOf(0f, 0.5f, 1f),
            Shader.TileMode.CLAMP
        )
        invalidate()
    }

    private fun updateTitleShader() {
        val width = titleLabel.width.toFloat()
        if (width <= 0f) return
        val (fromX, toX) = if (LocaleController.isRTL) width to 0f else 0f to width
        titleLabel.paint.shader = LinearGradient(
            fromX,
            0f,
            toX,
            0f,
            titleGradientColors,
            TITLE_GRADIENT_POSITIONS,
            Shader.TileMode.CLAMP
        )
        titleLabel.invalidate()
    }

    fun setTitle(title: CharSequence) {
        titleLabel.text = title
    }

    /** Draws the card's fill and border, without what is on them, as they show at [width] × [height] */
    fun drawPill(canvas: Canvas, width: Int, height: Int) {
        for (drawable in listOfNotNull(background, borderDrawable)) {
            val bounds = drawable.copyBounds()
            drawable.setBounds(0, 0, width, height)
            drawable.draw(canvas)
            drawable.bounds = bounds
        }
    }

    private fun updateBorderAnimation() {
        if (isAttachedToWindow && isShown) {
            if (!borderAnimator.isStarted) borderAnimator.start()
        } else {
            borderAnimator.cancel()
        }
    }
}

// A title that wraps is as wide as its longest line, so the pill hugs it, not the room it may take
@SuppressLint("ViewConstructor")
private class HuggingLabel(context: Context) : WLabel(context) {
    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        super.onMeasure(widthMeasureSpec, heightMeasureSpec)
        val layout = layout ?: return
        if (layout.lineCount < 2) return
        val lineWidth = (0 until layout.lineCount).maxOf { layout.getLineMax(it) }
        val width = ceil(lineWidth).toInt() + compoundPaddingLeft + compoundPaddingRight
        if (width >= measuredWidth) return
        super.onMeasure(MeasureSpec.makeMeasureSpec(width, MeasureSpec.EXACTLY), heightMeasureSpec)
    }
}

private class GradientFillDrawable(private val cornerRadius: Float, private val isRtl: Boolean) :
    Drawable() {

    private val fillPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.FILL
    }

    private var colors = intArrayOf(0, 0, 0)

    private val rectF = RectF()

    fun setColors(colors: IntArray) {
        val oriented = if (isRtl) colors.reversedArray() else colors
        if (oriented.contentEquals(this.colors)) return
        this.colors = oriented
        updateShader()
        invalidateSelf()
    }

    override fun onBoundsChange(bounds: Rect) {
        super.onBoundsChange(bounds)
        updateShader()
    }

    private fun updateShader() {
        val bounds = bounds
        fillPaint.shader = if (bounds.isEmpty) {
            null
        } else {
            LinearGradient(
                bounds.left.toFloat(),
                bounds.exactCenterY(),
                bounds.right.toFloat(),
                bounds.exactCenterY(),
                colors,
                null,
                Shader.TileMode.CLAMP
            )
        }
    }

    override fun draw(canvas: Canvas) {
        val bounds = bounds
        if (bounds.isEmpty || fillPaint.shader == null) return
        rectF.set(
            bounds.left.toFloat(),
            bounds.top.toFloat(),
            bounds.right.toFloat(),
            bounds.bottom.toFloat()
        )
        canvas.drawRoundRect(rectF, cornerRadius, cornerRadius, fillPaint)
    }

    override fun setAlpha(alpha: Int) {}
    override fun setColorFilter(colorFilter: ColorFilter?) {}

    @Suppress("OVERRIDE_DEPRECATION")
    override fun getOpacity() = PixelFormat.TRANSLUCENT
}

private class GradientBorderDrawable(
    private val cornerRadius: Float,
    private val borderWidth: Float
) : Drawable() {

    val width: Float get() = borderWidth

    var angle = 0f

    private val borderPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeWidth = borderWidth
    }

    private val colors = intArrayOf(
        0x8000BEFF.toInt(),
        0x8000BEFF.toInt(),
        0x800088FF.toInt(),
        0x80B656FF.toInt(),
        0x8000BEFF.toInt()
    )
    private val positions = floatArrayOf(
        0f,
        0.14425f,
        0.38464f,
        0.75f,
        1f
    )

    private val shaderMatrix = Matrix()
    private val rectF = RectF()
    private var cachedShader: SweepGradient? = null
    private var cachedCx = Float.NaN
    private var cachedCy = Float.NaN

    override fun onBoundsChange(bounds: Rect) {
        super.onBoundsChange(bounds)
        cachedShader = null
    }

    override fun draw(canvas: Canvas) {
        val bounds = bounds
        if (bounds.isEmpty) return

        val cx = bounds.exactCenterX()
        val cy = bounds.exactCenterY()

        val shader = cachedShader?.takeIf { cachedCx == cx && cachedCy == cy }
            ?: SweepGradient(cx, cy, colors, positions).also {
                cachedShader = it
                cachedCx = cx
                cachedCy = cy
            }

        shaderMatrix.setRotate(angle, cx, cy)
        shader.setLocalMatrix(shaderMatrix)
        borderPaint.shader = shader

        val inset = borderWidth / 2f
        rectF.set(
            bounds.left + inset,
            bounds.top + inset,
            bounds.right - inset,
            bounds.bottom - inset
        )
        canvas.drawRoundRect(rectF, cornerRadius - inset, cornerRadius - inset, borderPaint)
    }

    override fun setAlpha(alpha: Int) {}
    override fun setColorFilter(colorFilter: ColorFilter?) {}

    @Suppress("OVERRIDE_DEPRECATION")
    override fun getOpacity() = PixelFormat.TRANSLUCENT
}
