package org.mytonwallet.app_air.uicomponents.viewControllers.mediaViewer

import android.animation.AnimatorSet
import android.animation.ObjectAnimator
import android.animation.ValueAnimator
import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.drawable.GradientDrawable
import android.os.SystemClock
import android.text.TextPaint
import android.util.TypedValue
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.FrameLayout
import android.widget.ImageView
import androidx.core.widget.NestedScrollView
import java.util.Calendar
import java.util.Date
import kotlin.math.max
import kotlin.math.min
import org.mytonwallet.app_air.icons.R
import org.mytonwallet.app_air.uicomponents.base.WNavigationBar
import org.mytonwallet.app_air.uicomponents.drawable.WRippleDrawable
import org.mytonwallet.app_air.uicomponents.drawable.counter.Counter
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.getLtrBaselineSpacingOffset
import org.mytonwallet.app_air.uicomponents.helpers.CubicBezierInterpolator
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.spans.ExtraHitLinkMovementMethod
import org.mytonwallet.app_air.uicomponents.helpers.typeface
import org.mytonwallet.app_air.uicomponents.widgets.WImageButton
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.utils.getDrawableCompat

private const val BAR_COLOR = 0x7F000000
private const val BUTTON_RIPPLE_COLOR = 0x40FFFFFF
private const val CAPTION_HIGHLIGHT_COLOR = 0x33FFFFFF

const val MEDIA_VIEWER_CAPTION_LINK_COLOR = 0xFF79C4FC.toInt()
const val MEDIA_VIEWER_CAPTION_CODE_COLOR = 0x33FFFFFF

/** In dp */
internal const val MEDIA_VIEWER_BAR_HEIGHT = WNavigationBar.DEFAULT_HEIGHT

/** [formatDay] adds the year when it differs from [now]'s. */
fun formatMediaViewerDate(
    date: Date,
    now: Date,
    formatTime: (Date) -> String,
    formatDay: (date: Date, withYear: Boolean) -> String
): String {
    val calendar = Calendar.getInstance().apply { time = date }
    val today = Calendar.getInstance().apply { time = now }
    val yesterday = Calendar.getInstance().apply {
        time = now
        add(Calendar.DAY_OF_YEAR, -1)
    }
    val day = when {
        calendar.isSameDay(today) -> LocaleController.getString("Today")
        calendar.isSameDay(yesterday) -> LocaleController.getString("Yesterday")
        else -> formatDay(date, calendar.get(Calendar.YEAR) != today.get(Calendar.YEAR))
    }
    return LocaleController.getStringWithKeyValues(
        "\$media_viewer_date_at_time",
        listOf("%date%" to day, "%time%" to formatTime(date))
    )
}

private fun Calendar.isSameDay(other: Calendar): Boolean =
    get(Calendar.YEAR) == other.get(Calendar.YEAR) &&
        get(Calendar.DAY_OF_YEAR) == other.get(Calendar.DAY_OF_YEAR)

internal data class MediaViewerCountText(
    val prefix: String,
    val middle: String,
    val suffix: String
) {
    companion object {
        fun from(format: String): MediaViewerCountText {
            val current = format.indexOf(CURRENT)
            val total = format.indexOf(TOTAL)
            if (current < 0 || total < current) return MediaViewerCountText("", " / ", "")
            return MediaViewerCountText(
                format.substring(0, current),
                format.substring(current + CURRENT.length, total),
                format.substring(total + TOTAL.length)
            )
        }

        private const val CURRENT = "%current%"
        private const val TOTAL = "%total%"
    }
}

internal fun mediaViewerDescription(position: Int, count: Int, label: String?): String {
    val picture = LocaleController.getString("Picture")
    val name = if (count > 1) {
        val place = LocaleController.getStringWithKeyValues(
            "\$agent_wallet_page_indicator",
            listOf("%current%" to position.toString(), "%total%" to count.toString())
        )
        "$picture $place"
    } else {
        picture
    }
    return listOfNotNull(name, label?.takeIf { it.isNotBlank() }).joinToString(", ")
}

internal enum class MediaViewerTurn(val step: Int, val titleKey: String) {
    PREVIOUS(-1, "Previous"),
    NEXT(1, "Next");

    companion object {
        fun available(index: Int, count: Int): List<MediaViewerTurn> =
            entries.filter { index + it.step in 0 until count }
    }
}

private fun makeBarButton(context: Context, icon: Int) = object : WImageButton(context) {
    override fun updateTheme() {
        super.updateTheme()
        (background as? WRippleDrawable)?.rippleColor = BUTTON_RIPPLE_COLOR
        updateTintColor(Color.WHITE)
    }
}.apply {
    setImageDrawable(context.getDrawableCompat(icon))
    scaleType = ImageView.ScaleType.CENTER
    updateTheme()
}

@SuppressLint("ViewConstructor")
internal class MediaViewerActionBar(context: Context) : FrameLayout(context) {
    val backButton = makeBarButton(context, R.drawable.ic_nav_back)
    val menuButton = makeBarButton(context, R.drawable.ic_more)

    private val titleLayout = object : FrameLayout(context) {
        override fun onLayout(changed: Boolean, left: Int, top: Int, right: Int, bottom: Int) {
            super.onLayout(changed, left, top, right, bottom)
            pivotX = if (layoutDirection == LAYOUT_DIRECTION_RTL) {
                (width - TITLE_INSET.dp).toFloat()
            } else {
                TITLE_INSET.dp.toFloat()
            }
            pivotY = height.toFloat()
        }
    }

    private val titleView = MediaViewerAnimatedTextView(
        context,
        MediaViewerAnimatedTextView.Motion.HORIZONTAL
    ).apply {
        paint.typeface = WFont.Medium.typeface
        paint.textSize = TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_SP,
            TITLE_SIZE,
            resources.displayMetrics
        )
        paint.color = Color.WHITE
    }
    private val subtitleView = MediaViewerAnimatedTextView(
        context,
        MediaViewerAnimatedTextView.Motion.VERTICAL
    ).apply {
        paint.textSize = TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_DIP,
            SUBTITLE_SIZE,
            resources.displayMetrics
        )
        paint.color = Color.WHITE
        alpha = 0f
    }
    private var hasSubtitle = false
    private var subtitleAnimator: AnimatorSet? = null
    private val barHeight = MEDIA_VIEWER_BAR_HEIGHT.dp
    private var topInset = 0

    init {
        setBackgroundColor(BAR_COLOR)
        addView(backButton, LayoutParams(BACK_SIZE.dp, BACK_SIZE.dp, Gravity.TOP or Gravity.START))
        addView(menuButton, LayoutParams(MENU_WIDTH.dp, barHeight, Gravity.TOP or Gravity.END))
        titleLayout.setPaddingRelative(TITLE_INSET.dp, 0, 0, 0)
        titleLayout.clipToPadding = false
        titleLayout.addView(
            titleView,
            LayoutParams(MATCH_PARENT, WRAP_CONTENT, Gravity.START or Gravity.CENTER_VERTICAL)
        )
        addView(titleLayout, LayoutParams(MATCH_PARENT, barHeight, Gravity.TOP))
        addView(subtitleView, LayoutParams(MATCH_PARENT, SUBTITLE_HEIGHT.dp, Gravity.TOP))
        updateLayoutParamsForInsets()
    }

    val contentHeight: Int get() = barHeight

    fun setInsets(top: Int, start: Int, end: Int) {
        val isSame = top == topInset && paddingStart == start && paddingEnd == end
        if (isSame) return
        topInset = top
        setPaddingRelative(start, 0, end, 0)
        updateLayoutParamsForInsets()
        setSubtitleLayout(hasSubtitle)
    }

    private fun updateLayoutParamsForInsets() {
        listOf(menuButton, titleLayout).forEach { child ->
            (child.layoutParams as LayoutParams).apply {
                height = barHeight
                topMargin = topInset
            }
        }
        (backButton.layoutParams as LayoutParams).apply {
            topMargin = topInset + (barHeight - BACK_SIZE.dp) / 2
            marginStart = BACK_START.dp
        }
        (titleLayout.layoutParams as LayoutParams).apply {
            marginStart = (TITLE_START - TITLE_INSET).dp
            marginEnd = MENU_WIDTH.dp
        }
        (subtitleView.layoutParams as LayoutParams).apply {
            topMargin = topInset
            marginStart = TITLE_START.dp
            marginEnd = MENU_WIDTH.dp
        }
        layoutParams?.height = topInset + barHeight
        requestLayout()
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        super.onMeasure(
            widthMeasureSpec,
            MeasureSpec.makeMeasureSpec(topInset + barHeight, MeasureSpec.EXACTLY)
        )
    }

    /** [direction]: 1 in from the end, -1 from the start, 0 at once. */
    fun setTitle(title: CharSequence, direction: Int) {
        titleView.setText(title, animated = direction != 0, direction)
    }

    fun setSubtitle(subtitle: CharSequence?, direction: Int) {
        val hasText = !subtitle.isNullOrEmpty()
        if (hasText != hasSubtitle) {
            hasSubtitle = hasText
            if (direction == 0) setSubtitleLayout(hasText) else animateSubtitleLayout(hasText)
        }
        subtitleView.setText(subtitle, animated = direction != 0)
    }

    private fun navigationBarBaselines(withSubtitle: Boolean): Pair<Float, Float> {
        val title = makeNavigationBarPaint(NAVIGATION_TITLE_SIZE)
        val subtitle = makeNavigationBarPaint(NAVIGATION_SUBTITLE_SIZE)
        val titleMetrics = title.fontMetricsInt
        val subtitleMetrics = subtitle.fontMetricsInt
        val titleHeight = titleMetrics.bottom - titleMetrics.top
        val subtitleHeight = if (withSubtitle) subtitleMetrics.bottom - subtitleMetrics.top else 0
        val top = (barHeight - titleHeight - subtitleHeight) / 2f
        val subtitleBaseline = top + titleHeight - subtitleMetrics.top +
            title.getLtrBaselineSpacingOffset(subtitle)
        return (top - titleMetrics.top) to subtitleBaseline
    }

    private fun makeNavigationBarPaint(size: Float) = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
        typeface = WFont.Medium.typeface
        textSize =
            TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_SP, size, resources.displayMetrics)
    }

    private fun centredBaseline(view: MediaViewerAnimatedTextView, height: Int): Float {
        val metrics = view.paint.fontMetricsInt
        return (height - (metrics.bottom - metrics.top)) / 2f - metrics.top
    }

    private fun titleLift(hasText: Boolean): Float {
        val (target, _) = navigationBarBaselines(hasText)
        val baseline = centredBaseline(titleView, barHeight)
        val scale = if (hasText) TITLE_SCALE else 1f
        return target - (barHeight + (baseline - barHeight) * scale)
    }

    private fun subtitleTranslation(hasText: Boolean): Float {
        val (_, target) = navigationBarBaselines(withSubtitle = true)
        val shown = target - centredBaseline(subtitleView, SUBTITLE_HEIGHT.dp)
        return if (hasText) shown else shown + SUBTITLE_HIDDEN_DROP.dp
    }

    private fun setSubtitleLayout(hasText: Boolean) {
        subtitleAnimator?.cancel()
        subtitleView.alpha = if (hasText) 1f else 0f
        subtitleView.translationY = subtitleTranslation(hasText)
        titleLayout.translationY = titleLift(hasText)
        titleLayout.scaleX = if (hasText) TITLE_SCALE else 1f
        titleLayout.scaleY = if (hasText) TITLE_SCALE else 1f
    }

    private fun animateSubtitleLayout(hasText: Boolean) {
        subtitleAnimator?.cancel()
        subtitleAnimator = AnimatorSet().apply {
            playTogether(
                ObjectAnimator.ofFloat(subtitleView, ALPHA, if (hasText) 1f else 0f),
                ObjectAnimator.ofFloat(subtitleView, TRANSLATION_Y, subtitleTranslation(hasText)),
                ObjectAnimator.ofFloat(titleLayout, TRANSLATION_Y, titleLift(hasText)),
                ObjectAnimator.ofFloat(titleLayout, SCALE_X, if (hasText) TITLE_SCALE else 1f),
                ObjectAnimator.ofFloat(titleLayout, SCALE_Y, if (hasText) TITLE_SCALE else 1f)
            )
            duration = TEXT_SWAP_MS
            interpolator = CubicBezierInterpolator.EASE_OUT_QUINT
            start()
        }
    }

    private companion object {
        const val BACK_SIZE = 40
        const val BACK_START = 8
        const val MENU_WIDTH = 48
        const val TITLE_START = 72
        const val TITLE_INSET = 16
        const val TITLE_SIZE = 20f
        const val TITLE_SCALE = 0.87f
        const val SUBTITLE_SIZE = 14f
        const val SUBTITLE_HEIGHT = 20
        const val SUBTITLE_HIDDEN_DROP = 3

        // In sp
        const val NAVIGATION_TITLE_SIZE = 22f
        const val NAVIGATION_SUBTITLE_SIZE = 12f
        const val TEXT_SWAP_MS = 320L
    }
}

@SuppressLint("ViewConstructor")
internal class MediaViewerCountView(context: Context) :
    View(context),
    Counter.Callback {
    private val textPaint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.WHITE
        textSize = TEXT_SIZE.dp.toFloat()
        typeface = WFont.Medium.typeface
    }
    private val backgroundPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = BAR_COLOR }
    private val current = Counter(textPaint, this, duration = DIGITS_MS)
    private val total = Counter(textPaint, this, duration = DIGITS_MS)
    private var text =
        MediaViewerCountText.from(LocaleController.getString("\$agent_wallet_page_indicator"))
    private val pill = RectF()
    private var isPillShown = false
    private var showProgress = 0f
    private var showAnimator: ValueAnimator? = null

    var bandTop = 0
        set(value) {
            if (field == value) return
            field = value
            requestLayout()
        }

    fun set(position: Int, count: Int, animated: Boolean) {
        current.setValue(position.toString(), animated && isPillShown)
        total.setValue(count.toString(), animated && isPillShown)
        invalidate()
    }

    fun setShown(show: Boolean, animated: Boolean) {
        if (show == isPillShown) return
        isPillShown = show
        showAnimator?.cancel()
        if (!animated) {
            showProgress = if (show) 1f else 0f
            invalidate()
            return
        }
        showAnimator = ValueAnimator.ofFloat(showProgress, if (show) 1f else 0f).apply {
            duration = SHOW_MS
            interpolator = CubicBezierInterpolator.EASE_OUT_QUINT
            addUpdateListener {
                showProgress = it.animatedValue as Float
                invalidate()
            }
            start()
        }
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        setMeasuredDimension(
            MeasureSpec.getSize(widthMeasureSpec),
            bandTop + (PILL_TOP + PILL_HEIGHT + PILL_TOP).dp
        )
    }

    override fun onDraw(canvas: Canvas) {
        if (showProgress <= 0f) return
        val prefixWidth = textPaint.measureText(text.prefix)
        val middleWidth = textPaint.measureText(text.middle)
        val suffixWidth = textPaint.measureText(text.suffix)
        val contentWidth = prefixWidth + current.getVisibleWidth() + middleWidth +
            total.getVisibleWidth() + suffixWidth
        val width = contentWidth + 2 * PILL_PADDING.dp
        val top = bandTop + PILL_TOP.dp - (1f - showProgress) * SHOW_SLIDE.dp
        pill.set((this.width - width) / 2f, top, (this.width + width) / 2f, top + PILL_HEIGHT.dp)
        backgroundPaint.alpha = (Color.alpha(BAR_COLOR) * showProgress).toInt()
        val radius = PILL_RADIUS.dp.toFloat()
        canvas.drawRoundRect(pill, radius, radius, backgroundPaint)
        val metrics = textPaint.fontMetrics
        val baseline = pill.centerY() - (metrics.ascent + metrics.descent) / 2f
        var x = pill.left + PILL_PADDING.dp
        val alpha = showProgress
        textPaint.alpha = (255 * alpha).toInt()
        canvas.drawText(text.prefix, x, baseline, textPaint)
        x += prefixWidth
        current.draw(canvas, x, baseline, alpha)
        x += current.getVisibleWidth()
        textPaint.alpha = (255 * alpha).toInt()
        canvas.drawText(text.middle, x, baseline, textPaint)
        x += middleWidth
        total.draw(canvas, x, baseline, alpha)
        x += total.getVisibleWidth()
        textPaint.alpha = (255 * alpha).toInt()
        canvas.drawText(text.suffix, x, baseline, textPaint)
    }

    override fun onCounterAppearanceChanged(counter: Counter, sizeChanged: Boolean) {
        invalidate()
    }

    private companion object {
        const val TEXT_SIZE = 14
        const val PILL_TOP = 10
        const val PILL_HEIGHT = 23
        const val PILL_RADIUS = 12
        const val PILL_PADDING = 9
        const val SHOW_SLIDE = 8
        const val SHOW_MS = 350L
        const val DIGITS_MS = 320L
    }
}

@SuppressLint("ViewConstructor")
internal class MediaViewerCaptionView(context: Context) : NestedScrollView(context) {
    private val container = FrameLayout(context)
    val textView = WLabel(context).apply {
        setTextSize(TypedValue.COMPLEX_UNIT_DIP, TEXT_SIZE)
        setTextColor(Color.WHITE)
        setLinkTextColor(MEDIA_VIEWER_CAPTION_LINK_COLOR)
        highlightColor = CAPTION_HIGHLIGHT_COLOR
        isSingleLine = false
        maxLines = Int.MAX_VALUE
        ellipsize = null
        gravity = Gravity.CENTER_VERTICAL or Gravity.START
        textAlignment = TEXT_ALIGNMENT_VIEW_START
        val side = SIDE_PADDING.dp
        val vertical = VERTICAL_PADDING.dp
        setPaddingRelative(side, vertical, side, vertical)
        movementMethod = ExtraHitLinkMovementMethod(2.dp, 2.dp)
        setOnClickListener { smoothScrollBy(0, TAP_SCROLL.dp) }
    }
    private val bandPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.BLACK }
    private var measuredFor: Triple<Int, Int, CharSequence?>? = null

    init {
        clipChildren = false
        overScrollMode = OVER_SCROLL_NEVER
        isVerticalScrollBarEnabled = false
        setFadingEdgeLength(FADING_EDGE.dp)
        isVerticalFadingEdgeEnabled = true
        setWillNotDraw(false)
        container.clipChildren = false
        container.addView(textView, FrameLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        addView(container, LayoutParams(MATCH_PARENT, WRAP_CONTENT))
    }

    val hasText: Boolean get() = !textView.text.isNullOrEmpty()

    fun setText(text: CharSequence?) {
        textView.text = text
        visibility = if (text.isNullOrEmpty()) INVISIBLE else VISIBLE
        scrollTo(0, 0)
        requestLayout()
    }

    val bandTop: Float get() = container.top - scrollY.toFloat()

    // A touch above the text goes through to the picture
    @SuppressLint("ClickableViewAccessibility")
    override fun onTouchEvent(ev: MotionEvent): Boolean {
        if (ev.actionMasked == MotionEvent.ACTION_DOWN && ev.y < bandTop) return false
        return super.onTouchEvent(ev)
    }

    override fun onInterceptTouchEvent(ev: MotionEvent): Boolean {
        if (ev.actionMasked == MotionEvent.ACTION_DOWN && ev.y < bandTop) return false
        return super.onInterceptTouchEvent(ev)
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val width = MeasureSpec.getSize(widthMeasureSpec)
        updateTopMargin(width, MeasureSpec.getSize(heightMeasureSpec))
        super.onMeasure(widthMeasureSpec, heightMeasureSpec)
    }

    // A short caption shows whole; a long one its first lines, without trailing blank ones
    private fun updateTopMargin(width: Int, height: Int) {
        if (width == 0 || height == 0) return
        val key = Triple(width, height, textView.text)
        if (key == measuredFor) return
        measuredFor = key
        textView.measure(
            MeasureSpec.makeMeasureSpec(width, MeasureSpec.EXACTLY),
            MeasureSpec.makeMeasureSpec(height, MeasureSpec.AT_MOST)
        )
        val layout = textView.layout ?: return
        val configuration = resources.configuration
        val isLandscape = configuration.screenWidthDp > configuration.screenHeightDp
        val shownLines = if (isLandscape) LANDSCAPE_LINES else PORTRAIT_LINES
        val text = textView.text
        val topMargin = if (layout.lineCount <= shownLines) {
            height - textView.measuredHeight
        } else {
            var lines = min(shownLines, layout.lineCount)
            while (lines > 1 &&
                (layout.getLineStart(lines - 1) until layout.getLineEnd(lines - 1)).all {
                    it >= text.length || Character.isWhitespace(text[it])
                }
            ) {
                lines--
            }
            height - textView.paint.getFontMetricsInt(null) * lines - VERTICAL_PADDING.dp
        }
        (container.layoutParams as LayoutParams).topMargin = max(0, topMargin)
    }

    override fun getTopFadingEdgeStrength(): Float = 1f

    override fun getBottomFadingEdgeStrength(): Float = 1f

    override fun draw(canvas: Canvas) {
        val saveCount = canvas.save()
        canvas.clipRect(0, scrollY, width, height + scrollY)
        bandPaint.alpha = BAND_ALPHA
        val bottom = (height + scrollY).toFloat()
        canvas.drawRect(0f, container.top.toFloat(), width.toFloat(), bottom, bandPaint)
        super.draw(canvas)
        canvas.restoreToCount(saveCount)
    }

    private companion object {
        const val TEXT_SIZE = 16f
        const val SIDE_PADDING = 16
        const val VERTICAL_PADDING = 8
        const val TAP_SCROLL = 64
        const val FADING_EDGE = 12
        const val PORTRAIT_LINES = 5
        const val LANDSCAPE_LINES = 2
        const val BAND_ALPHA = 127
    }
}

internal class MediaViewerPressedEdges(context: Context) : View(context) {
    private val drawables = arrayOf(
        GradientDrawable(GradientDrawable.Orientation.LEFT_RIGHT, intArrayOf(SHADE_COLOR, 0)),
        GradientDrawable(GradientDrawable.Orientation.RIGHT_LEFT, intArrayOf(SHADE_COLOR, 0))
    )
    private val isPressed = BooleanArray(2)
    private val alphas = FloatArray(2)
    private var lastFrameTime = 0L

    val isAnyPressed: Boolean get() = isPressed[0] || isPressed[1]

    /** 0: left edge, 1: right edge */
    fun press(side: Int) {
        isPressed[side] = true
        lastFrameTime = SystemClock.uptimeMillis()
        invalidate()
    }

    fun release() {
        if (!isAnyPressed) return
        isPressed[0] = false
        isPressed[1] = false
        lastFrameTime = SystemClock.uptimeMillis()
        invalidate()
    }

    override fun onDraw(canvas: Canvas) {
        val now = SystemClock.uptimeMillis()
        val dt = (now - lastFrameTime).coerceIn(0L, MAX_FRAME_MS)
        lastFrameTime = now
        var isAnimating = false
        for (side in drawables.indices) {
            if (isPressed[side] || alphas[side] != 0f) {
                drawables[side].alpha = (alphas[side] * 255).toInt()
                if (side == 0) {
                    drawables[side].setBounds(0, 0, width / 5, height)
                } else {
                    drawables[side].setBounds(width - width / 5, 0, width, height)
                }
                drawables[side].draw(canvas)
            }
            val target = if (isPressed[side]) 1f else 0f
            if (alphas[side] != target) {
                val step = dt / FADE_MS
                alphas[side] = if (target > alphas[side]) {
                    min(1f, alphas[side] + step)
                } else {
                    max(0f, alphas[side] - step)
                }
                isAnimating = true
            }
        }
        if (isAnimating) postInvalidateOnAnimation()
    }

    private companion object {
        const val SHADE_COLOR = 0x32000000
        const val FADE_MS = 180f
        const val MAX_FRAME_MS = 32L
    }
}
