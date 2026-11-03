package org.mytonwallet.app_air.uicomponents.widgets.chart.extended

import android.animation.Animator
import android.animation.AnimatorListenerAdapter
import android.animation.ValueAnimator
import android.content.Context
import android.graphics.drawable.Drawable
import android.text.TextUtils
import android.view.Gravity
import android.view.View
import android.widget.FrameLayout
import androidx.core.view.isGone
import androidx.core.view.isInvisible
import androidx.core.view.isVisible
import kotlin.math.max
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.drawable.WRippleDrawable
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.setMarginsDp
import org.mytonwallet.app_air.uicomponents.helpers.CubicBezierInterpolator
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.hideImmediately
import org.mytonwallet.app_air.uicomponents.widgets.showImmediately
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.getDrawableCompat
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage

class ChartHeaderView(context: Context, private val showsControlsRow: Boolean = false) :
    FrameLayout(context),
    WThemedView {
    private enum class DatesAnimationDirection {
        TOP_TO_BOTTOM,
        BOTTOM_TO_TOP
    }

    val dates: WLabel by lazy {
        WLabel(context).apply {
            setStyle(14f, WFont.Regular)
            setTextColor(WColor.SecondaryText)
            lineHeight = 24.dp
            gravity = Gravity.START or Gravity.CENTER_VERTICAL
            if (showsControlsRow) {
                isSingleLine = true
                ellipsize = TextUtils.TruncateAt.END
            }
        }
    }

    val datesTmp: WLabel by lazy {
        WLabel(context).apply {
            setStyle(14f, WFont.Regular)
            setTextColor(WColor.SecondaryText)
            lineHeight = 24.dp
            gravity = Gravity.START or Gravity.CENTER_VERTICAL
            if (showsControlsRow) {
                isSingleLine = true
                ellipsize = TextUtils.TruncateAt.END
            }
            visibility = GONE
        }
    }

    private val title: WLabel by lazy {
        WLabel(context).apply {
            setStyle(14f, WFont.Medium)
            setTextColor(WColor.Tint)
            lineHeight = 24.dp
            setLineSpacing(0f, 0.85f)
            gravity = Gravity.START or Gravity.CENTER_VERTICAL
            maxLines = 2
            ellipsize = TextUtils.TruncateAt.END
        }
    }

    var zoomOutText: CharSequence = LocaleController.getString("Zoom Out")
        set(value) {
            field = value
            if (backLazy.isInitialized()) backLazy.value.text = value
        }

    private val backLazy = lazy {
        object : WLabel(context) {
            private val ripple = WRippleDrawable.create(20f.dp)

            init {
                background = ripple
            }

            override fun updateTheme() {
                super.updateTheme()
                ripple.rippleColor = WColor.TintRipple.color
                zoomIcon?.setTint(WColor.Tint.color)
            }
        }.apply {
            lineHeight = 24.dp
            gravity = Gravity.START or Gravity.CENTER_VERTICAL
            setStyle(14f, WFont.Medium)
            setTextColor(WColor.Tint)
            text = zoomOutText
            setCompoundDrawablesWithIntrinsicBounds(zoomIcon, null, null, null)
            compoundDrawablePadding = 4.dp
            setPadding(8.dp, 2.dp, 8.dp, 2.dp)
            alpha = 0f
            isInvisible = true
        }
    }
    val back: WLabel by backLazy

    val today: WLabel = object : WLabel(context) {
        private val ripple = WRippleDrawable.create(20f.dp)

        init {
            background = ripple
        }

        override fun updateTheme() {
            super.updateTheme()
            ripple.rippleColor = WColor.TintRipple.color
        }
    }.apply {
        lineHeight = 24.dp
        gravity = Gravity.END or Gravity.CENTER_VERTICAL
        setStyle(14f, WFont.Medium)
        setTextColor(WColor.Tint)
        text = LocaleController.getString("Today")
        setPadding(8.dp, 2.dp, 8.dp, 2.dp)
        alpha = 0f
        isInvisible = true
    }

    private val zoomIcon: Drawable? by lazy {
        context.getDrawableCompat(org.mytonwallet.app_air.icons.R.drawable.ic_zoom_out_22)
    }

    private var isZoomedIn = false
    private var isTodayVisible = false
    private var backFraction = 0f
    private var backAnimator: ValueAnimator? = null
    private var titleRowHeight = 0
    private var datesAnimationTarget: CharSequence? = null
    private var deferredDatesText: CharSequence? = null
    private var lastMeasuredTotalWidth = -1

    var datesSuppressed = false

    var onDatesChanged: (() -> Unit)? = null

    init {
        addView(
            title,
            LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT).apply {
                gravity = Gravity.START
                setMarginsDp(20, 14, 8, 0)
            }
        )
        addView(
            back,
            LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT).apply {
                gravity = Gravity.START
                setMarginsDp(10, 0, 8, 0)
            }
        )
        addView(
            today,
            LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT).apply {
                gravity = Gravity.END
                setMarginsDp(8, 0, 12, 0)
            }
        )
        addView(dates, datesLayoutParams())
        addView(datesTmp, datesLayoutParams())

        datesTmp.addOnLayoutChangeListener { _, _, _, _, _, _, _, _, _ ->
            datesTmp.pivotX = datesTmp.measuredWidth * 0.7f
            dates.pivotX = dates.measuredWidth * 0.7f
        }

        updateTheme()
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val total = MeasureSpec.getSize(widthMeasureSpec)
        if (total > 0) {
            val screenSizeChanged = total != lastMeasuredTotalWidth
            lastMeasuredTotalWidth = total
            val trailing = when {
                showsControlsRow -> null
                datesTmp.isVisible -> datesTmp
                dates.isVisible -> dates
                else -> null
            }
            val trailingWidth = if (trailing != null) {
                measureChildWithMargins(trailing, widthMeasureSpec, 0, heightMeasureSpec, 0)
                val lp = trailing.layoutParams as MarginLayoutParams
                trailing.measuredWidth + lp.leftMargin + lp.rightMargin
            } else {
                0
            }
            val titleLp = title.layoutParams as MarginLayoutParams
            val maxTitleWidth =
                (total - paddingLeft - paddingRight - titleLp.leftMargin - trailingWidth)
                    .coerceAtLeast(0)
            if (maxTitleWidth != title.maxWidth &&
                (screenSizeChanged || maxTitleWidth < title.maxWidth)
            ) {
                title.maxWidth = maxTitleWidth
            }
        }
        super.onMeasure(widthMeasureSpec, heightMeasureSpec)
        titleRowHeight = max(
            TITLE_ROW_MIN_HEIGHT.dp,
            (title.layoutParams as MarginLayoutParams).topMargin + title.measuredHeight + 2.dp
        )
        val height = titleRowHeight + if (showsControlsRow) CONTROLS_ROW_HEIGHT.dp else 0
        setMeasuredDimension(measuredWidth, resolveSize(height, heightMeasureSpec))
        if (showsControlsRow) measureControlsRowDates(heightMeasureSpec)
    }

    private fun measureControlsRowDates(heightMeasureSpec: Int) {
        val inset = CONTROLS_ROW_INSET.dp
        val minX = inset + ((controlsRowBackMaxX() - inset) * backFraction).toInt()
        val available = (controlsRowMaxX(measuredWidth) - minX).coerceAtLeast(0)
        listOf(dates, datesTmp).forEach { view ->
            if (view.isGone || view.measuredWidth <= available) return@forEach
            view.measure(
                MeasureSpec.makeMeasureSpec(available, MeasureSpec.AT_MOST),
                getChildMeasureSpec(heightMeasureSpec, 0, view.layoutParams.height)
            )
        }
    }

    private fun controlsRowTodayX(rowWidth: Int) =
        rowWidth - CONTROLS_ROW_INSET.dp + today.paddingRight - today.measuredWidth

    private fun controlsRowMaxX(rowWidth: Int) = if (isTodayVisible) {
        controlsRowTodayX(rowWidth) + today.paddingLeft - CONTROLS_SPACING.dp
    } else {
        rowWidth - CONTROLS_ROW_INSET.dp
    }

    private fun controlsRowBackX() = CONTROLS_ROW_INSET.dp - back.paddingLeft

    private fun controlsRowBackMaxX() =
        controlsRowBackX() + back.measuredWidth - back.paddingRight + CONTROLS_SPACING.dp

    override fun onLayout(changed: Boolean, left: Int, top: Int, right: Int, bottom: Int) {
        super.onLayout(changed, left, top, right, bottom)
        if (showsControlsRow) layoutControlsRow()
    }

    private fun layoutControlsRow() {
        val inset = CONTROLS_ROW_INSET.dp
        place(back, controlsRowBackX())
        place(today, controlsRowTodayX(width))
        val maxX = controlsRowMaxX(width)
        val backMaxX = controlsRowBackMaxX()
        listOf(dates, datesTmp).forEach { view ->
            val textWidth = view.measuredWidth
            fun centered(lower: Int) =
                (width / 2 - textWidth / 2).coerceAtMost(maxX - textWidth).coerceAtLeast(lower)
            val withoutBack = if (isTodayVisible) inset else centered(inset)
            val withBack = centered(backMaxX)
            place(view, (withoutBack + (withBack - withoutBack) * backFraction).toInt())
        }
        back.alpha = backFraction
        back.visibility = if (backFraction > 0f) VISIBLE else INVISIBLE
    }

    private fun place(view: View, x: Int) {
        val rowTop = titleRowHeight + (CONTROLS_ROW_HEIGHT.dp - view.measuredHeight) / 2
        val left = if (layoutDirection ==
            LAYOUT_DIRECTION_RTL
        ) {
            width - x - view.measuredWidth
        } else {
            x
        }
        view.layout(left, rowTop, left + view.measuredWidth, rowTop + view.measuredHeight)
    }

    override fun updateTheme() {
        dates.updateTheme()
        datesTmp.updateTheme()
        title.updateTheme()
        back.updateTheme()
        today.updateTheme()
    }

    fun setTitle(text: CharSequence) {
        title.text = text
    }

    fun setTodayState(visible: Boolean, enabled: Boolean, animated: Boolean) {
        today.isEnabled = enabled
        today.setTextColor(if (enabled) WColor.Tint else WColor.SecondaryText)
        if (isTodayVisible == visible) return
        isTodayVisible = visible
        setActionVisible(today, visible, animated)
        requestLayout()
    }

    fun showTitleOnly() {
        setZoomedIn(false, animated = false)
        setTodayState(visible = false, enabled = false, animated = false)
        dates.animate().cancel()
        datesTmp.animate().cancel()
        if (datesAnimationTarget != null) {
            dates.text = datesAnimationTarget
        }
        datesAnimationTarget = null
        deferredDatesText = null
        dates.isGone = true
        datesTmp.isGone = true
    }

    fun setDates(start: Long, end: Long, animated: Boolean = false) {
        setDates(start, end, animated, DatesAnimationDirection.BOTTOM_TO_TOP)
        onDatesChanged?.invoke()
    }

    private fun setDates(
        start: Long,
        end: Long,
        animated: Boolean,
        direction: DatesAnimationDirection
    ) {
        if (datesSuppressed || start <= 0) return

        val newText = if (end - start >= 86400000L) {
            ChartFormatters.formatDate("d MMM yyyy", start) +
                " — " +
                ChartFormatters.formatDate("d MMM yyyy", end)
        } else {
            ChartFormatters.formatDate("d MMM yyyy", start)
        }

        if (!animated) {
            when {
                datesAnimationTarget == newText -> {
                    deferredDatesText = null
                    return
                }

                datesAnimationTarget != null && dates.text == newText -> {
                    return
                }

                datesAnimationTarget != null -> {
                    deferredDatesText = newText
                    return
                }

                else -> {
                    applyDatesImmediately(newText)
                    return
                }
            }
        }

        completeDatesAnimation()
        if (dates.text == newText && dates.isVisible) return
        if (!shouldAnimate(true) || !dates.isVisible || dates.text.isNullOrEmpty()) {
            applyDatesImmediately(newText)
            return
        }

        val (incomingOffset, outgoingOffset) = when (direction) {
            DatesAnimationDirection.TOP_TO_BOTTOM ->
                HEADER_TRANSITION_OFFSET.dp to -HEADER_TRANSITION_OFFSET.dp

            DatesAnimationDirection.BOTTOM_TO_TOP ->
                -HEADER_TRANSITION_OFFSET.dp to HEADER_TRANSITION_OFFSET.dp
        }

        datesAnimationTarget = newText
        deferredDatesText = null
        datesTmp.text = newText
        transitionViews(
            incoming = datesTmp,
            outgoing = dates,
            incomingOffset = incomingOffset,
            outgoingOffset = outgoingOffset,
            animated = true,
            finishOutgoingVisibility = GONE,
            onEnd = {
                completeDatesAnimation()
                deferredDatesText?.let { deferredText ->
                    deferredDatesText = null
                    if (deferredText != dates.text) {
                        applyDatesImmediately(deferredText)
                    }
                }
            }
        )
    }

    fun zoomTo(d: Long, animate: Boolean) {
        setDates(
            start = d,
            end = d,
            animated = animate,
            direction = DatesAnimationDirection.TOP_TO_BOTTOM
        )
        setZoomedIn(true, animate)
    }

    fun zoomOut(chartView: BaseChartView<*, *>, animated: Boolean) {
        zoomOut(chartView.getStartDate(), chartView.getEndDate(), animated)
    }

    fun zoomOut(start: Long, end: Long, animated: Boolean) {
        setDates(
            start = start,
            end = end,
            animated = animated,
            direction = DatesAnimationDirection.BOTTOM_TO_TOP
        )
        setZoomedIn(false, animated)
    }

    private fun datesLayoutParams(): LayoutParams =
        LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT).apply {
            gravity = Gravity.END
            setMarginsDp(16, 14, 20, 0)
        }

    private fun setZoomedIn(zoomedIn: Boolean, animated: Boolean) {
        isZoomedIn = zoomedIn
        val target = if (zoomedIn) 1f else 0f
        if (backAnimator == null && backFraction == target) return
        backAnimator?.cancel()
        if (!shouldAnimate(animated)) {
            backFraction = target
            requestLayout()
            return
        }
        backAnimator = ValueAnimator.ofFloat(backFraction, target).apply {
            duration = AnimationConstants.QUICK_ANIMATION
            interpolator = CubicBezierInterpolator.EASE_BOTH
            addUpdateListener {
                backFraction = it.animatedValue as Float
                requestLayout()
            }
            addListener(object : AnimatorListenerAdapter() {
                override fun onAnimationEnd(animation: Animator) {
                    if (backAnimator === animation) backAnimator = null
                }
            })
            start()
        }
    }

    private fun setActionVisible(view: View, visible: Boolean, animated: Boolean) {
        if (!shouldAnimate(animated)) {
            if (visible) view.showImmediately() else view.hideImmediately()
            return
        }
        view.animate().cancel()
        view.visibility = VISIBLE
        view.animate()
            .alpha(if (visible) 1f else 0f)
            .setDuration(AnimationConstants.QUICK_ANIMATION)
            .setInterpolator(CubicBezierInterpolator.EASE_BOTH)
            .withEndAction { if (!visible) view.visibility = INVISIBLE }
            .start()
    }

    private fun transitionViews(
        incoming: View,
        outgoing: View,
        incomingOffset: Float,
        outgoingOffset: Float,
        animated: Boolean,
        finishOutgoingVisibility: Int = INVISIBLE,
        onEnd: (() -> Unit)? = null
    ) {
        if (!shouldAnimate(animated)) {
            incoming.showImmediately()
            outgoing.hideImmediately(finishOutgoingVisibility)
            onEnd?.invoke()
            return
        }

        incoming.animate().cancel()
        outgoing.animate().cancel()

        incoming.apply {
            visibility = VISIBLE
            alpha = 0f
            translationY = incomingOffset
            animate()
                .alpha(1f)
                .translationY(0f)
                .setDuration(AnimationConstants.QUICK_ANIMATION)
                .setInterpolator(CubicBezierInterpolator.EASE_BOTH)
                .start()
        }

        outgoing.apply {
            visibility = VISIBLE
            animate()
                .alpha(0f)
                .translationY(outgoingOffset)
                .setDuration(AnimationConstants.QUICK_ANIMATION)
                .setInterpolator(CubicBezierInterpolator.EASE_BOTH)
                .withEndAction {
                    hideImmediately(finishOutgoingVisibility)
                    onEnd?.invoke()
                }
                .start()
        }
    }

    private fun applyDatesImmediately(text: CharSequence) {
        datesAnimationTarget = null
        deferredDatesText = null
        dates.animate().cancel()
        datesTmp.animate().cancel()
        dates.text = text
        dates.showImmediately()
        datesTmp.hideImmediately(GONE)
    }

    private fun completeDatesAnimation() {
        val target = datesAnimationTarget ?: return
        dates.animate().cancel()
        datesTmp.animate().cancel()
        dates.text = target
        dates.showImmediately()
        datesTmp.hideImmediately(GONE)
        datesAnimationTarget = null
    }

    private fun shouldAnimate(animated: Boolean): Boolean =
        animated && WGlobalStorage.getAreAnimationsActive()

    private companion object {
        const val HEADER_TRANSITION_OFFSET = 8f
        const val TITLE_ROW_MIN_HEIGHT = 40
        const val CONTROLS_ROW_HEIGHT = 36
        const val CONTROLS_ROW_INSET = 20
        const val CONTROLS_SPACING = 8
    }
}
