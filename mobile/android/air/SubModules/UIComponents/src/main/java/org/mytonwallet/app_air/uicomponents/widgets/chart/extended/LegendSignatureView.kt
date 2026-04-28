package org.mytonwallet.app_air.uicomponents.widgets.chart.extended

import android.animation.Animator
import android.animation.AnimatorListenerAdapter
import android.content.Context
import android.graphics.drawable.LayerDrawable
import android.os.Build
import android.transition.ChangeBounds
import android.transition.Fade
import android.transition.TransitionManager
import android.transition.TransitionSet
import android.util.TypedValue
import android.view.Gravity
import android.view.MotionEvent
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.typeface
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.getDrawableCompat
import java.text.DecimalFormat
import java.text.DecimalFormatSymbols
import java.util.Locale

open class LegendSignatureView(
    context: Context
) : FrameLayout(context) {

    var style: ChartStyle = ChartStyle.default()

    private val contentTopMargin = 22.dp
    private val footerTopMargin = 12.dp
    private val chevronSize = 18.dp
    private val chevronTextSpacing = 8.dp
    private val tooltipShadowInset = 3.dp
    private val scrollView: ScrollView = object : ScrollView(context) {
        override fun dispatchTouchEvent(ev: MotionEvent): Boolean {
            updateParentTouchInterception(ev)
            return super.dispatchTouchEvent(ev)
        }

        override fun onTouchEvent(ev: MotionEvent): Boolean {
            updateParentTouchInterception(ev)
            return super.onTouchEvent(ev)
        }

        private fun updateParentTouchInterception(event: MotionEvent) {
            if (!canScrollVertically(1) && !canScrollVertically(-1)) {
                if (event.actionMasked == MotionEvent.ACTION_UP || event.actionMasked == MotionEvent.ACTION_CANCEL) {
                    parent?.requestDisallowInterceptTouchEvent(false)
                }
                return
            }

            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN,
                MotionEvent.ACTION_MOVE -> parent?.requestDisallowInterceptTouchEvent(true)

                MotionEvent.ACTION_UP,
                MotionEvent.ACTION_CANCEL -> parent?.requestDisallowInterceptTouchEvent(false)
            }
        }
    }

    var isTopHourChart = false
    private val headerRow: LinearLayout = LinearLayout(context)
    private val headerTextContainer: FrameLayout = FrameLayout(context)
    private val headerEndSlot: FrameLayout = FrameLayout(context)
    protected val content: LinearLayout = LinearLayout(context)
    protected lateinit var holders: Array<Holder>
    protected val time: TextView = TextView(context)
    protected val hourTime: TextView = TextView(context)
    private val footer: LinearLayout = LinearLayout(context)
    private val footerLabelView: TextView = TextView(context)
    private val footerValueView: TextView = TextView(context)
    var chevron: ImageView = ImageView(context)
    private val chevronDrawable by lazy {
        context.getDrawableCompat(
            org.mytonwallet.app_air.icons.R.drawable.ic_arrow_right_24
        )?.mutate()
    }
    private val tooltipBackgroundDrawable by lazy {
        context.getDrawableCompat(
            org.mytonwallet.app_air.uicomponents.R.drawable.bg_stats_tooltip
        )?.mutate()
    }
    private val progressView: RadialProgressView = RadialProgressView(context)
    private var maxChartHeight = 0

    private var useWeekRange = false
    var useHour = false
    var showPercentage = false
    var zoomEnabled = false
    var canGoZoom = true
    var valuePrefix: String? = null
    var valueFormatter: ChartValueFormatter? = null
    var useCompactValueFormatting = true
    var percentageFormatter: ((Float) -> CharSequence)? = null
    var footerLabel: String? = null
        set(value) {
            field = value
            footerLabelView.text = value
            updateFooterVisibility()
        }

    private val showProgressRunnable = Runnable {
        chevron.animate().setDuration(120).alpha(0f)
        progressView.animate().setListener(null).start()
        if (progressView.visibility != VISIBLE) {
            progressView.visibility = VISIBLE
            progressView.alpha = 0f
        }
        progressView.animate().setDuration(120).alpha(1f).start()
    }

    init {
        setPadding(8.dp, 8.dp, 8.dp, 8.dp)
        content.orientation = LinearLayout.VERTICAL

        time.setTextSize(TypedValue.COMPLEX_UNIT_DIP, 14f)
        time.typeface = WFont.DemiBold.typeface
        hourTime.setTextSize(TypedValue.COMPLEX_UNIT_DIP, 14f)
        hourTime.typeface = WFont.DemiBold.typeface
        footerLabelView.setTextSize(TypedValue.COMPLEX_UNIT_DIP, 14f)
        footerLabelView.typeface = WFont.DemiBold.typeface
        footerValueView.setTextSize(TypedValue.COMPLEX_UNIT_DIP, 14f)
        footerValueView.typeface = WFont.DemiBold.typeface

        chevron.setImageDrawable(chevronDrawable)

        progressView.setSize(12.dp)
        progressView.setStrokeWidth(0.5f.dp)
        progressView.visibility = GONE

        headerRow.apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        headerTextContainer.apply {
            addView(
                time,
                LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT).apply {
                    gravity = Gravity.START or Gravity.CENTER_VERTICAL
                    marginStart = 4.dp
                    marginEnd = 4.dp
                }
            )
            addView(
                hourTime,
                LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT).apply {
                    gravity = Gravity.END or Gravity.CENTER_VERTICAL
                    marginStart = 4.dp
                    marginEnd = 4.dp
                }
            )
        }
        headerEndSlot.apply {
            addView(
                chevron,
                LayoutParams(chevronSize, chevronSize).apply {
                    gravity = Gravity.CENTER
                }
            )
            addView(
                progressView,
                LayoutParams(chevronSize, chevronSize).apply {
                    gravity = Gravity.CENTER
                }
            )
        }
        headerRow.addView(
            headerTextContainer,
            LinearLayout.LayoutParams(0, LayoutParams.WRAP_CONTENT, 1f)
        )
        headerRow.addView(
            headerEndSlot,
            LinearLayout.LayoutParams(chevronSize, chevronSize).apply {
                marginStart = chevronTextSpacing
                topMargin = 2.dp
            }
        )

        footer.apply {
            orientation = LinearLayout.HORIZONTAL
            visibility = GONE
            setPadding(4.dp, 0, 4.dp, 0)
            addView(
                footerLabelView,
                LinearLayout.LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT)
                    .apply {
                        marginEnd = 20.dp
                    }
            )
            addView(
                footerValueView,
                LinearLayout.LayoutParams(0, LayoutParams.WRAP_CONTENT, 1f)
            )
        }
        footerValueView.gravity = Gravity.END

        scrollView.apply {
            visibility = GONE
            overScrollMode = OVER_SCROLL_ALWAYS
            isVerticalScrollBarEnabled = false
            addView(
                content,
                LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT)
            )
        }

        addView(
            scrollView,
            LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT).apply {
                topMargin = contentTopMargin
            }
        )
        addView(
            headerRow,
            LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT).apply {
                gravity = Gravity.START or Gravity.TOP
            }
        )
        addView(
            footer,
            LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT).apply {
                gravity = Gravity.START or Gravity.BOTTOM
            }
        )

        recolor()
    }

    open fun recolor() {
        time.setTextColor(style.primaryTextColor)
        hourTime.setTextColor(style.primaryTextColor)
        footerLabelView.setTextColor(style.primaryTextColor)
        footerValueView.setTextColor(style.primaryTextColor)
        chevronDrawable?.setTint(style.chevronColor)
        progressView.setProgressColor(style.chevronColor)
        val tooltipBackground = style.createTooltipBackground(4f.dp)
        val tooltipShadow = tooltipBackgroundDrawable
        background = if (tooltipShadow != null) {
            LayerDrawable(arrayOf(tooltipShadow, tooltipBackground)).apply {
                setLayerInset(
                    1,
                    tooltipShadowInset,
                    tooltipShadowInset,
                    tooltipShadowInset,
                    tooltipShadowInset
                )
            }
        } else {
            tooltipBackground
        }
    }

    open fun setSize(n: Int) {
        content.removeAllViews()
        scrollView.visibility = if (n > 0) VISIBLE else GONE
        holders = Array(n) { Holder() }
        holders.forEach {
            content.addView(
                it.root,
                LinearLayout.LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT)
            )
        }
    }

    fun setMaxChartHeight(maxHeight: Int) {
        val normalizedHeight = maxHeight.coerceAtLeast(0)
        if (maxChartHeight == normalizedHeight) {
            return
        }
        maxChartHeight = normalizedHeight
        requestLayout()
    }

    fun setData(
        index: Int,
        date: Long,
        lines: ArrayList<LineViewData>,
        animateChanges: Boolean,
        formatter: Int,
        k: Float,
    ) {
        val n = holders.size
        if (animateChanges && Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT) {
            val transition = TransitionSet()
                .addTransition(Fade(Fade.OUT).setDuration(150))
                .addTransition(ChangeBounds().setDuration(150))
                .addTransition(Fade(Fade.IN).setDuration(150))
            transition.ordering = TransitionSet.ORDERING_TOGETHER
            TransitionManager.beginDelayedTransition(this, transition)
        }

        if (isTopHourChart) {
            time.text = String.format(Locale.ENGLISH, "%02d:00", date)
        } else {
            time.text = if (useWeekRange) {
                String.format(
                    "%s — %s",
                    ChartFormatters.formatDate("d MMM", date),
                    ChartFormatters.formatDate("d MMM yyyy", date + 86400000L * 7),
                )
            } else {
                formatData(date)
            }
            if (useHour) {
                hourTime.text = " " + ChartFormatters.formatDate("HH:mm", date)
            }
        }

        var sum = 0L
        for (line in lines) {
            if (line.enabled) {
                sum += line.line.y[index]
            }
        }

        for (i in 0 until n) {
            val holder = holders[i]
            val formatterIndex = i % 2
            val line =
                lines[if (formatter == ChartData.FORMATTER_TON || formatter == ChartData.FORMATTER_XTR) i / 2 else i]
            if (!line.enabled) {
                holder.root.visibility = GONE
                continue
            }

            if (holder.root.measuredHeight == 0) {
                holder.root.requestLayout()
            }
            holder.root.visibility = VISIBLE
            holder.value.text =
                formatWholeNumber(line.line.y[index], formatter, formatterIndex, holder.value, k)
            holder.signature.text = line.line.name
            holder.value.setTextColor(style.resolveLineColor(line.line))
            holder.signature.setTextColor(style.primaryTextColor)

            if (showPercentage && holder.percentage != null) {
                holder.percentage!!.visibility = VISIBLE
                holder.percentage!!.setTextColor(style.primaryTextColor)
                val v = line.line.y[index] / sum.toFloat()
                holder.percentage!!.text =
                    percentageFormatter?.invoke(v) ?: if (v < 0.1f && v != 0f) {
                        String.format(Locale.ENGLISH, "%.1f%s", 100f * v, "%")
                    } else {
                        String.format(Locale.ENGLISH, "%d%s", Math.round(100 * v), "%")
                    }
            }
        }
        updateFooter(sum, formatter, k)

        if (zoomEnabled) {
            canGoZoom = sum > 0
            chevron.visibility = if (sum > 0) VISIBLE else GONE
        } else {
            canGoZoom = false
            chevron.visibility = GONE
        }
    }

    override fun requestLayout() {
        val suppressHiddenLayout =
            visibility != VISIBLE &&
                width == 0 &&
                height == 0 &&
                measuredWidth == 0 &&
                measuredHeight == 0
        if (suppressHiddenLayout) {
            return
        }
        super.requestLayout()
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val widthMode = MeasureSpec.getMode(widthMeasureSpec)
        val availableContentWidth =
            (MeasureSpec.getSize(widthMeasureSpec) - paddingLeft - paddingRight)
                .coerceAtLeast(0)
        val contentWidthSpec = if (widthMode == MeasureSpec.UNSPECIFIED) {
            MeasureSpec.makeMeasureSpec(0, MeasureSpec.UNSPECIFIED)
        } else {
            MeasureSpec.makeMeasureSpec(
                availableContentWidth,
                MeasureSpec.AT_MOST
            )
        }
        val unspecifiedHeightSpec = MeasureSpec.makeMeasureSpec(0, MeasureSpec.UNSPECIFIED)

        headerRow.measure(contentWidthSpec, unspecifiedHeightSpec)
        content.measure(contentWidthSpec, unspecifiedHeightSpec)
        if (footer.visibility == VISIBLE) {
            footer.measure(contentWidthSpec, unspecifiedHeightSpec)
        }

        var bodyWidth = maxOf(
            headerRow.measuredWidth,
            content.measuredWidth,
            if (footer.visibility == VISIBLE) footer.measuredWidth else 0
        )
        if (widthMode != MeasureSpec.UNSPECIFIED) {
            bodyWidth = bodyWidth.coerceAtMost(availableContentWidth)
        }
        val exactBodyWidthSpec = MeasureSpec.makeMeasureSpec(bodyWidth, MeasureSpec.EXACTLY)

        headerRow.measure(exactBodyWidthSpec, unspecifiedHeightSpec)
        content.measure(exactBodyWidthSpec, unspecifiedHeightSpec)
        if (footer.visibility == VISIBLE) {
            footer.measure(exactBodyWidthSpec, unspecifiedHeightSpec)
        }

        scrollView.measure(exactBodyWidthSpec, unspecifiedHeightSpec)

        val footerHeight =
            if (footer.visibility == VISIBLE) footer.measuredHeight + footerTopMargin else 0
        val headerHeight = headerRow.measuredHeight + paddingTop + paddingBottom
        val contentHeight =
            scrollView.measuredHeight + contentTopMargin + paddingTop + paddingBottom
        var requiredHeight = maxOf(headerHeight, contentHeight) + footerHeight

        val availableHeight = maxChartHeight
        if (availableHeight > 0 && requiredHeight > availableHeight && scrollView.visibility == VISIBLE) {
            val constrainedScrollHeight =
                (availableHeight - paddingTop - paddingBottom - contentTopMargin - footerHeight).coerceAtLeast(
                    0
                )
            scrollView.measure(
                exactBodyWidthSpec,
                MeasureSpec.makeMeasureSpec(constrainedScrollHeight, MeasureSpec.AT_MOST)
            )
            requiredHeight = maxOf(
                headerHeight,
                scrollView.measuredHeight + contentTopMargin + paddingTop + paddingBottom
            ) + footerHeight
        }

        setMeasuredDimension(
            bodyWidth + paddingLeft + paddingRight,
            if (availableHeight > 0) minOf(availableHeight, requiredHeight) else requiredHeight
        )
    }

    private fun formatData(timestamp: Long): String {
        if (useHour) {
            return capitalize(ChartFormatters.formatDate("MMM dd", timestamp))
        }
        return capitalize(ChartFormatters.formatDate("E, ", timestamp)) +
            capitalize(ChartFormatters.formatDate("MMM dd", timestamp))
    }

    private fun capitalize(value: String): String {
        return if (value.isNotEmpty()) Character.toUpperCase(value[0]) + value.substring(1) else value
    }

    private var formatterTON: DecimalFormat? = null

    fun formatWholeNumber(
        v: Long,
        formatter: Int,
        formatterIndex: Int,
        textView: TextView,
        k: Float,
    ): CharSequence {
        if (formatter == ChartData.FORMATTER_TON) {
            if (formatterIndex == 0) {
                if (formatterTON == null) {
                    val symbols = DecimalFormatSymbols(Locale.US).apply {
                        decimalSeparator = '.'
                    }
                    formatterTON = DecimalFormat("#.##", symbols).apply {
                        minimumFractionDigits = 2
                        maximumFractionDigits = 6
                        isGroupingUsed = false
                    }
                }
                formatterTON!!.maximumFractionDigits = if (v > 1_000_000_000) 2 else 6
                return ChannelMonetizationLayout.replaceTON(
                    "TON " + formatterTON!!.format(v / 1_000_000_000.0),
                    textView.paint,
                    .82f,
                    plain = false,
                )
            }
            return "≈" + ChartFormatters.formatCurrency((v / k).toLong(), "USD")
        }
        if (formatter == ChartData.FORMATTER_XTR) {
            if (formatterIndex == 0) {
                return "XTR " + ChartFormatters.formatNumber(v)
            }
            return "≈" + ChartFormatters.formatCurrency((v / k).toLong(), "USD")
        }
        if (valueFormatter != null) {
            return valueFormatter!!.formatLegendValue(v, textView.paint)
        }
        val formattedValue = if (useCompactValueFormatting) {
            ChartFormatters.compactWholeNumber(v)
        } else {
            v.toString()
        }
        return if (valuePrefix.isNullOrEmpty()) formattedValue else valuePrefix + formattedValue
    }

    fun showProgress(show: Boolean, force: Boolean) {
        if (show) {
            removeCallbacks(showProgressRunnable)
            postDelayed(showProgressRunnable, 300)
        } else {
            removeCallbacks(showProgressRunnable)
            if (force) {
                progressView.visibility = GONE
            } else {
                chevron.animate().setDuration(80).alpha(1f).start()
                if (progressView.visibility == VISIBLE) {
                    progressView.animate().setDuration(80).alpha(0f)
                        .setListener(object : AnimatorListenerAdapter() {
                            override fun onAnimationEnd(animation: Animator) {
                                progressView.visibility = GONE
                            }
                        }).start()
                }
            }
        }
    }

    fun setUseWeek(useWeek: Boolean) {
        useWeekRange = useWeek
    }

    private fun updateFooter(sum: Long, formatter: Int, k: Float) {
        if (footerLabel.isNullOrEmpty()) {
            footer.visibility = GONE
            return
        }
        footerValueView.text = formatWholeNumber(
            v = sum,
            formatter = formatter,
            formatterIndex = 0,
            textView = footerValueView,
            k = k,
        )
        updateFooterVisibility()
    }

    private fun updateFooterVisibility() {
        footer.visibility = if (footerLabel.isNullOrEmpty()) GONE else VISIBLE
    }

    inner class Holder {
        val value: WLabel
        val signature: TextView
        var percentage: TextView? = null
        val root: LinearLayout = LinearLayout(context)

        init {
            root.setPadding(4.dp, 2.dp, 4.dp, 2.dp)
            root.orientation = LinearLayout.HORIZONTAL
            root.gravity = Gravity.CENTER_VERTICAL

            if (showPercentage) {
                percentage = TextView(context).apply {
                    layoutParams = LinearLayout.LayoutParams(36.dp, LayoutParams.WRAP_CONTENT)
                    visibility = GONE
                    gravity = Gravity.START
                    typeface = WFont.DemiBold.typeface
                    setTextSize(TypedValue.COMPLEX_UNIT_DIP, 13f)
                }
                root.addView(percentage)
            }

            signature = TextView(context)
            root.addView(
                signature,
                LinearLayout.LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT)
                    .apply {
                        marginEnd = 20.dp
                    }
            )
            value = WLabel(context)
            root.addView(
                value,
                LinearLayout.LayoutParams(0, LayoutParams.WRAP_CONTENT, 1f)
            )

            signature.gravity = Gravity.START
            value.gravity = Gravity.END
            value.typeface = WFont.DemiBold.typeface
            value.setTextSize(TypedValue.COMPLEX_UNIT_DIP, 13f)
            signature.setTextSize(TypedValue.COMPLEX_UNIT_DIP, 13f)
        }
    }
}
