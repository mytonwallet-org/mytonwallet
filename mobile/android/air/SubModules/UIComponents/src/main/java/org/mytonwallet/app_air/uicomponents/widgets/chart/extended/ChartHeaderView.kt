package org.mytonwallet.app_air.uicomponents.widgets.chart.extended

import android.content.Context
import android.graphics.drawable.Drawable
import android.text.TextUtils
import android.view.Gravity
import android.view.View
import android.widget.FrameLayout
import androidx.core.view.isGone
import androidx.core.view.isInvisible
import androidx.core.view.isVisible
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.drawable.WRippleDrawable
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.setMarginsDp
import org.mytonwallet.app_air.uicomponents.helpers.CubicBezierInterpolator
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WBaseView
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.fadeIn
import org.mytonwallet.app_air.uicomponents.widgets.fadeOut
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.uicomponents.widgets.hideImmediately
import org.mytonwallet.app_air.uicomponents.widgets.showImmediately
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.getDrawableCompat
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage

class ChartHeaderView(context: Context) : FrameLayout(context), WThemedView {
    private enum class LeadingContentMode {
        TITLE,
        ZOOM_OUT
    }

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
        }
    }

    val datesTmp: WLabel by lazy {
        WLabel(context).apply {
            setStyle(14f, WFont.Regular)
            setTextColor(WColor.SecondaryText)
            lineHeight = 24.dp
            gravity = Gravity.START or Gravity.CENTER_VERTICAL
            visibility = GONE
        }
    }

    val datesPlaceholder: WBaseView by lazy {
        WBaseView(context).apply {
            id = generateViewId()
            visibility = GONE
        }
    }

    private val title: WLabel by lazy {
        WLabel(context).apply {
            setStyle(14f, WFont.DemiBold)
            setTextColor(WColor.Tint)
            lineHeight = 24.dp
            gravity = Gravity.START or Gravity.CENTER_VERTICAL
            setSingleLine()
            ellipsize = TextUtils.TruncateAt.END
        }
    }

    val back: WLabel by lazy {
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
            setStyle(16f, WFont.DemiBold)
            setTextColor(WColor.Tint)
            text = LocaleController.getString("Zoom Out")
            setCompoundDrawablesWithIntrinsicBounds(zoomIcon, null, null, null)
            compoundDrawablePadding = 4.dp
            setPadding(8.dp, 2.dp, 8.dp, 2.dp)
            alpha = 0f
            translationY = HEADER_TRANSITION_OFFSET.dp
            isInvisible = true
        }
    }

    private val zoomIcon: Drawable? by lazy {
        context.getDrawableCompat(org.mytonwallet.app_air.icons.R.drawable.ic_zoom_out_22)
    }

    private var leadingContentMode = LeadingContentMode.TITLE
    private var datesAnimationTarget: CharSequence? = null
    private var deferredDatesText: CharSequence? = null

    init {
        minimumHeight = 40.dp

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
                setMarginsDp(10, 14, 8, 0)
            }
        )
        addView(dates, datesLayoutParams())
        addView(datesTmp, datesLayoutParams())
        addView(
            datesPlaceholder,
            LayoutParams(200.dp, 16.dp).apply {
                gravity = Gravity.END
                setMarginsDp(16, 18, 20, 0)
            }
        )

        datesTmp.addOnLayoutChangeListener { _, _, _, _, _, _, _, _, _ ->
            datesTmp.pivotX = datesTmp.measuredWidth * 0.7f
            dates.pivotX = dates.measuredWidth * 0.7f
        }

        updateTheme()
    }

    override fun updateTheme() {
        dates.updateTheme()
        datesTmp.updateTheme()
        title.updateTheme()
        back.updateTheme()
        datesPlaceholder.setBackgroundColor(WColor.SecondaryBackground.color, 4f.dp)
    }

    fun showDatesPlaceholder(animated: Boolean = false) {
        datesPlaceholder.visibility = VISIBLE
        if (animated) {
            datesPlaceholder.animate().cancel()
            datesPlaceholder.alpha = 0f
            datesPlaceholder.fadeIn()
        } else {
            datesPlaceholder.alpha = 1f
        }
    }

    fun hideDatesPlaceholder() {
        datesPlaceholder.fadeOut { datesPlaceholder.visibility = GONE }
    }

    fun setTitle(text: CharSequence) {
        title.text = text
        if (leadingContentMode == LeadingContentMode.TITLE) {
            title.visibility = VISIBLE
            title.alpha = 1f
            title.translationY = 0f
        }
    }

    fun showTitleOnly() {
        switchLeadingContent(LeadingContentMode.TITLE, animated = false)
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
    }

    private fun setDates(
        start: Long,
        end: Long,
        animated: Boolean,
        direction: DatesAnimationDirection,
    ) {
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
        switchLeadingContent(LeadingContentMode.ZOOM_OUT, animate)
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
        switchLeadingContent(LeadingContentMode.TITLE, animated)
    }

    private fun datesLayoutParams(): LayoutParams {
        return LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT).apply {
            gravity = Gravity.END
            setMarginsDp(16, 14, 20, 0)
        }
    }

    private fun switchLeadingContent(mode: LeadingContentMode, animated: Boolean) {
        val (incoming, outgoing, incomingOffset, outgoingOffset) = when (mode) {
            LeadingContentMode.TITLE ->
                LeadingTransition(
                    title,
                    back,
                    -HEADER_TRANSITION_OFFSET.dp,
                    HEADER_TRANSITION_OFFSET.dp
                )

            LeadingContentMode.ZOOM_OUT ->
                LeadingTransition(
                    back,
                    title,
                    HEADER_TRANSITION_OFFSET.dp,
                    -HEADER_TRANSITION_OFFSET.dp
                )
        }

        if (leadingContentMode == mode) {
            incoming.showImmediately()
            outgoing.hideImmediately()
            return
        }

        leadingContentMode = mode
        transitionViews(incoming, outgoing, incomingOffset, outgoingOffset, animated)
    }

    private fun transitionViews(
        incoming: View,
        outgoing: View,
        incomingOffset: Float,
        outgoingOffset: Float,
        animated: Boolean,
        finishOutgoingVisibility: Int = INVISIBLE,
        onEnd: (() -> Unit)? = null,
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

    private fun shouldAnimate(animated: Boolean): Boolean {
        return animated && WGlobalStorage.getAreAnimationsActive()
    }

    private companion object {
        const val HEADER_TRANSITION_OFFSET = 8f
    }

    private data class LeadingTransition(
        val incoming: View,
        val outgoing: View,
        val incomingOffset: Float,
        val outgoingOffset: Float,
    )
}
