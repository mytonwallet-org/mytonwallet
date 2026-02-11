package org.mytonwallet.app_air.uiassets.viewControllers.token.cells

import android.animation.AnimatorSet
import android.animation.ObjectAnimator
import android.annotation.SuppressLint
import android.graphics.Color
import android.graphics.PorterDuff
import android.graphics.drawable.GradientDrawable
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.ImageView
import androidx.appcompat.widget.AppCompatImageView
import androidx.core.animation.doOnCancel
import androidx.core.animation.doOnEnd
import androidx.core.view.isVisible
import androidx.core.view.setPadding
import androidx.dynamicanimation.animation.FloatValueHolder
import androidx.dynamicanimation.animation.SpringAnimation
import androidx.dynamicanimation.animation.SpringForce
import com.github.mikephil.charting.data.Entry
import com.github.mikephil.charting.data.LineData
import com.github.mikephil.charting.data.LineDataSet
import com.github.mikephil.charting.highlight.Highlight
import org.mytonwallet.app_air.uiassets.viewControllers.token.helpers.DatasetHelpers
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.drawable.RoundProgressDrawable
import org.mytonwallet.app_air.uicomponents.extensions.asImage
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WFrameLayout
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WRecyclerView
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.chart.WChartTimeLineView
import org.mytonwallet.app_air.uicomponents.widgets.chart.WLineChartView
import org.mytonwallet.app_air.uicomponents.widgets.fadeIn
import org.mytonwallet.app_air.uicomponents.widgets.fadeInObjectAnimator
import org.mytonwallet.app_air.uicomponents.widgets.fadeOut
import org.mytonwallet.app_air.uicomponents.widgets.fadeOutObjectAnimator
import org.mytonwallet.app_air.uicomponents.widgets.segmentedControlGroup.WSegmentedControlGroup
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.models.MBaseCurrency
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.MHistoryTimePeriod
import org.mytonwallet.app_air.walletbasecontext.utils.formatDateAndTime
import org.mytonwallet.app_air.walletbasecontext.utils.signSpace
import org.mytonwallet.app_air.walletbasecontext.utils.smartDecimalsCount
import org.mytonwallet.app_air.walletbasecontext.utils.toBigInteger
import org.mytonwallet.app_air.walletbasecontext.utils.toString
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.helpers.TaskManager
import org.mytonwallet.app_air.walletcontext.utils.AnimUtils.Companion.lerp
import org.mytonwallet.app_air.walletcontext.utils.colorWithAlpha
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.models.MToken
import java.lang.Float.max
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlin.math.min
import kotlin.math.roundToInt

@SuppressLint("ViewConstructor")
class TokenChartCell(
    recyclerView: WRecyclerView,
    var activePeriod: MHistoryTimePeriod,
    var onSelectedPeriodChanged: ((MHistoryTimePeriod) -> Unit)?,
    private var onHeightChange: ((isExpanding: Boolean, height: Int) -> Unit)?
) : WCell(recyclerView.context, LayoutParams(MATCH_PARENT, WRAP_CONTENT)),
    WThemedView {

    private var percentChange: Double? = null
    private var pendingAnimationToConfigure = false
    private var isAnimating = false
        set(value) {
            field = value
            if (value) {
                containerView.setBackgroundColor(
                    WColor.Background.color,
                    ViewConstants.BLOCK_RADIUS.dp
                )
            } else {
                containerView.addRippleEffect(
                    WColor.SecondaryBackground.color,
                    ViewConstants.BLOCK_RADIUS.dp
                )
                if (!isChangingPeriod && pendingAnimationToConfigure) {
                    pendingAnimationToConfigure = false
                    setupLineChart()
                }
            }
        }
    private var isExpanded = false
    private var isChangingPeriod = false
        set(value) {
            field = value
            if (!value && !isAnimating && pendingAnimationToConfigure) {
                pendingAnimationToConfigure = false
                setupLineChart()
            }
        }

    private val titleLabel: WLabel by lazy {
        val lbl = WLabel(context)
        lbl.text = LocaleController.getString("Price")
        lbl.setStyle(14f)
        lbl
    }

    private val priceLabel: WLabel by lazy {
        val lbl = WLabel(context)
        lbl.setStyle(16f, WFont.Medium)
        lbl
    }

    private val priceChangeLabel: WLabel by lazy {
        val lbl = WLabel(context)
        lbl.setStyle(14f)
        lbl
    }

    private val arrowIcon = AppCompatImageView(context).apply {
        id = generateViewId()
        layoutParams = LayoutParams(24.dp, 24.dp)
        setImageResource(org.mytonwallet.app_air.icons.R.drawable.ic_arrow_right_24)
        setColorFilter(WColor.SecondaryText.color, PorterDuff.Mode.SRC_IN)
        rotation = 90f
    }

    private val collapsedChartView = WLineChartView(context, false).apply {
        setTouchEnabled(false)
        alpha = 0f
    }
    private val expandedChartView = WLineChartView(context, true).apply {
        visibility = INVISIBLE
        alpha = 0f
    }
    private var areChartsFadeOut = true

    private val collapsedChartImageView = AppCompatImageView(context).apply {
        id = generateViewId()
    }
    private val expandedChartImageView = AppCompatImageView(context).apply {
        id = generateViewId()
    }

    private val chartTimeLineView = WChartTimeLineView(context, startPercentageChanged = {
        startPercentage = it
        setupLineChart()
    }, endPercentageChanged = {
        endPercentage = it
        setupLineChart()
    }).apply {
        alpha = 0f
        visibility = INVISIBLE
    }

    private val noDataLabelWidth: Int
    private val noDataLabelHeight: Int
    private var noDataMaxX = Float.MAX_VALUE
    private val noDataLabel = WLabel(context).apply {
        setStyle(14f, WFont.Regular)
        setTextColor(WColor.SecondaryText)
        text = LocaleController.getString("No price data")
        noDataLabelWidth = paint.measureText(text.toString()).roundToInt()
        noDataLabelHeight = paint.fontMetrics.run { bottom - top }.roundToInt()
        alpha = 0f
        visibility = GONE
    }

    private val segmentedControlGroup = WSegmentedControlGroup(context).apply {
        setBackgroundColor(WColor.SecondaryBackground.color, 15f.dp)
        MHistoryTimePeriod.allPeriods.map { period ->
            addView(
                WLabel(context).apply {
                    layoutParams = LayoutParams(0, MATCH_PARENT)
                    setStyle(14f)
                    text = period.localized
                    gravity = Gravity.CENTER
                }
            )
        }
        setOnSelectedOptionChangeCallback {
            activePeriod = MHistoryTimePeriod.allPeriods[it]
            startPercentage = 0f
            endPercentage = 1f
            if (!areChartsFadeOut) {
                isChangingPeriod = true
                configure(token!!, null, activePeriod)
            }
            onSelectedPeriodChanged?.invoke(activePeriod)
        }
        setSelectedIndex(MHistoryTimePeriod.allPeriods.indexOf(activePeriod))
    }

    private val segmentedControlGroupContainer = WFrameLayout(context).apply {
        setPadding(8.dp, 4.dp, 8.dp, 12.dp)
        addView(segmentedControlGroup, ViewGroup.LayoutParams(MATCH_PARENT, MATCH_PARENT))
        setOnClickListener {}
        visibility = INVISIBLE
    }

    private val roundDrawable = RoundProgressDrawable(12.dp, 0.5f.dp)

    private val progressViewWidth = 24.dp
    private val progressView = AppCompatImageView(context).apply {
        id = generateViewId()
        layoutParams = LayoutParams(progressViewWidth, progressViewWidth)
        setPadding(2.dp)
        setImageDrawable(roundDrawable)
        scaleType = ImageView.ScaleType.CENTER_INSIDE
        alpha = 0f
        visibility = GONE
    }
    private val progressTaskManager = TaskManager()

    private val containerView = WView(context).apply {
        addView(titleLabel)
        addView(priceLabel)
        addView(priceChangeLabel)
        addView(arrowIcon, LayoutParams(24.dp, 24.dp))
        addView(collapsedChartView, LayoutParams(119.dp, 24.dp))
        addView(expandedChartView, LayoutParams(0, 0))
        addView(collapsedChartImageView, LayoutParams(0, 0))
        addView(expandedChartImageView, LayoutParams(0, 0))
        addView(progressView)
        addView(noDataLabel)
        addView(chartTimeLineView, LayoutParams(MATCH_PARENT, 36.dp))
        addView(segmentedControlGroupContainer, LayoutParams(0, 46.dp))
        setConstraints {
            toTop(titleLabel, 10f)
            toStart(titleLabel, 20f)
            toTop(priceLabel, 30f)
            toStart(priceLabel, 20f)
            centerYToCenterY(priceChangeLabel, priceLabel)
            startToEnd(priceChangeLabel, priceLabel, 4f)
            toTop(arrowIcon, 20f)
            toEnd(arrowIcon, 16f)
            toTop(collapsedChartView, 20f)
            toEnd(collapsedChartView, 60f)
            toTop(expandedChartView, 52f) // overlaps header by 12dp
            toCenterX(expandedChartView)
            bottomToTop(chartTimeLineView, segmentedControlGroupContainer, 8f)
            toCenterX(segmentedControlGroupContainer, 12f)
            toBottom(segmentedControlGroupContainer)
        }
        post {
            progressView.x =
                collapsedChartView.x + (collapsedChartView.width - progressViewWidth)
            progressView.y = 20f.dp
            noDataLabel.x =
                collapsedChartView.x + (collapsedChartView.width - noDataLabelWidth)
            noDataLabel.y =
                collapsedChartView.y + (collapsedChartView.height - noDataLabelHeight) / 2f
            noDataMaxX = noDataLabel.x
            if (historyData.isNullOrEmpty())
                progressTaskManager.startTask({
                    progressView.visibility = VISIBLE
                    progressView.fadeIn()
                }, 1000)
        }
    }

    private var token: MToken? = null
    private var historyData: Array<Array<Double>>? = null
    private var highlightedHistoryData: Array<Array<Double>>? = null
    private var startPercentage = 0f
    private var endPercentage = 1f
    private var highlight: Highlight? = null

    init {
        addView(containerView, LayoutParams(MATCH_PARENT, 64.dp))

        setConstraints {
            toTop(containerView)
            toBottom(containerView, ViewConstants.GAP.toFloat())
            toCenterX(containerView)
        }

        // Collapse
        containerView.setOnClickListener { // Expand
            // Collapse
            if (isAnimating)
                return@setOnClickListener
            isAnimating = true
            collapsedChartImageView.setImageBitmap(collapsedChartView.asImage())
            expandedChartImageView.setImageBitmap(expandedChartView.asImage())
            val rotation = ObjectAnimator.ofFloat(
                arrowIcon,
                "rotation",
                arrowIcon.rotation,
                arrowIcon.rotation + 180
            )
            rotation.setDuration(300)
            rotation.start()// Expand
            // Collapse
            if (isExpanded) {
                // Collapse
                val startValue = containerView.height.toFloat()
                val endValue = 64.dp.toFloat()
                startSpringAnimation(startValue, endValue)
            } else {
                // Expand
                val startValue = 64.dp.toFloat()
                val endValue =
                    182.dp + ((width - 20.dp) * 79 / 392).toFloat()
                startSpringAnimation(startValue, endValue)
            }
        }

        expandedChartView.onHighlightChange = { highlight ->
            this.highlight = highlight
            setupTexts()
        }
    }

    override fun setupViews() {
        super.setupViews()

        expandedChartView.layoutParams = expandedChartView.layoutParams.apply {
            height = (((parent as ViewGroup).width.toFloat() - 20.dp) * 79f / 392f).toInt() + 28.dp
        }
    }

    override val isTinted = true
    override fun updateTheme() {
        setBackgroundColor(WColor.SecondaryBackground.color)
        containerView.setBackgroundColor(WColor.Background.color, ViewConstants.BLOCK_RADIUS.dp)
        if (!isAnimating) {
            containerView.addRippleEffect(
                WColor.SecondaryBackground.color,
                ViewConstants.BLOCK_RADIUS.dp
            )
        }
        titleLabel.setTextColor(WColor.SecondaryText.color)
        priceLabel.setTextColor(WColor.PrimaryText.color)
        roundDrawable.color = WColor.Tint.color
        updatePriceChangeLabelColor()
    }

    private fun updatePriceChangeLabelColor() {
        priceChangeLabel.setTextColor(
            if (highlight != null || percentChange == 0.0) WColor.SecondaryText.color else if ((percentChange
                    ?: 0.0) > 0.0
            ) WColor.Green.color else WColor.Red.color
        )
    }

    private fun renderChartAnimationFrame(isExpanding: Boolean, fraction: Float, height: Float) {
        val containerLayoutParams = containerView.layoutParams
        containerLayoutParams.height = height.roundToInt()
        containerView.layoutParams = containerLayoutParams
        onHeightChange?.invoke(isExpanding, containerLayoutParams.height)

        collapsedChartImageView.alpha = min(1 - fraction, collapsedChartView.alpha)
        expandedChartImageView.alpha = min(fraction, expandedChartView.alpha)
        val chartLayoutParams = collapsedChartImageView.layoutParams
        chartLayoutParams.width =
            collapsedChartView.width + (((expandedChartView.width - 20.dp) - collapsedChartView.width) * fraction).roundToInt()
        chartLayoutParams.height =
            collapsedChartView.height + (((expandedChartView.height - 16.dp) - collapsedChartView.height) * fraction).roundToInt()
        collapsedChartImageView.layoutParams = chartLayoutParams
        collapsedChartImageView.x = (1 - fraction) * collapsedChartView.x
        collapsedChartImageView.y =
            collapsedChartView.y + (expandedChartView.y - collapsedChartView.y) * fraction
        val expandedChartLayoutParams = expandedChartImageView.layoutParams
        val expandFraction = (chartLayoutParams.width / (expandedChartView.width - 20f.dp))
        expandedChartLayoutParams.width =
            chartLayoutParams.width + (20.dp * expandFraction).roundToInt()
        expandedChartLayoutParams.height =
            chartLayoutParams.height + (16.dp * expandFraction).roundToInt()
        expandedChartImageView.layoutParams = expandedChartLayoutParams
        expandedChartImageView.x = collapsedChartImageView.x
        expandedChartImageView.y = collapsedChartImageView.y
        renderProgressView(collapsedChartImageView, fraction)
        renderNoDataLabel(collapsedChartImageView, fraction)

        segmentedControlGroupContainer.alpha = max(0f, fraction - 0.7f) * 5
        chartTimeLineView.alpha = max(0f, fraction - 0.6f) * 5 / 2
        segmentedControlGroupContainer.visibility =
            if (segmentedControlGroupContainer.alpha > 0) VISIBLE else INVISIBLE
    }

    private fun renderProgressView(chartView: View, expandProgress: Float) {
        if (chartView.width == 0)
            return
        progressView.x =
            chartView.x + (chartView.width - progressViewWidth) / (1 + expandProgress) + (expandProgress * 10.dp)
        progressView.y =
            chartView.y + (chartView.height - progressViewWidth) / 2 - 4.dp + (31.dp * expandProgress)
    }

    private fun renderNoDataLabel(chartView: View, expandProgress: Float) {
        if (chartView.width == 0)
            return
        noDataLabel.x =
            lerp(
                noDataMaxX,
                chartView.x + (chartView.width - noDataLabelWidth) / 2 + 10.dp,
                expandProgress
            )
        noDataLabel.y =
            chartView.y + (chartView.height - noDataLabelHeight) / 2 + (27.dp * expandProgress)
    }

    private fun startSpringAnimation(startValue: Float, endValue: Float) {
        val isExpanding = endValue > startValue
        val springAnimation = SpringAnimation(FloatValueHolder()).apply {
            setStartValue(startValue)
            spring = SpringForce(endValue).apply {
                dampingRatio = SpringForce.DAMPING_RATIO_NO_BOUNCY
                stiffness = 500f
            }
            addUpdateListener { _, value, _ ->
                val fraction = (value - startValue) / (endValue - startValue)
                renderChartAnimationFrame(
                    isExpanding,
                    if (endValue - startValue > 0f) fraction else 1 - fraction,
                    value
                )
            }
            addEndListener { _, _, value, _ ->
                WGlobalStorage.decDoNotSynchronize()
                renderChartAnimationFrame(isExpanding, if (isExpanding) 1f else 0f, value)
                collapsedChartImageView.alpha = 0f
                expandedChartImageView.alpha = 0f
                collapsedChartView.visibility = if (isExpanding) INVISIBLE else VISIBLE
                expandedChartView.visibility = if (isExpanding) VISIBLE else INVISIBLE
                isExpanded = isExpanding
                isAnimating = false
            }
        }

        collapsedChartView.visibility = INVISIBLE
        expandedChartView.visibility = INVISIBLE
        WGlobalStorage.incDoNotSynchronize()
        springAnimation.start()
    }

    @SuppressLint("SetTextI18n")
    fun configure(
        token: MToken,
        historyData: Array<Array<Double>>?,
        activePeriod: MHistoryTimePeriod
    ) {
        this.token = token
        this.historyData = historyData
        this.activePeriod = activePeriod
        if (!isAnimating && (!isChangingPeriod || historyData == null)) {
            setupLineChart()
        } else {
            pendingAnimationToConfigure = true
        }
        updateTheme()
    }

    private fun setupTexts() {
        val baseCurrencySign =
            if (token?.symbol != WalletCore.baseCurrency.currencyCode)
                WalletCore.baseCurrency.sign
            else
                MBaseCurrency.USD.sign
        val price = if (highlightedHistoryData.isNullOrEmpty()) {
            token!!.price
        } else {
            highlightedHistoryData!!.last()[1]
        }
        val firstPrice = (highlightedHistoryData ?: historyData)?.firstOrNull {
            it[1] != 0.0
        }?.get(1)
        if (highlight == null) {
            val priceBigInt = price?.toBigInteger(9)
            priceLabel.text = priceBigInt?.toString(
                9,
                baseCurrencySign,
                priceBigInt.smartDecimalsCount(9).coerceAtLeast(2),
                false,
                forceCurrencyToRight = false
            )
            if (token?.price != null) {
                percentChange = firstPrice?.let { firstPriceInChart ->
                    ((price!! - firstPriceInChart) / firstPriceInChart * 10000)
                }?.let {
                    kotlin.math.round(it) / 100
                }
                if (percentChange != null) {
                    if (priceChangeLabel.alpha == 0f)
                        priceChangeLabel.fadeIn()
                    priceChangeLabel.text =
                        (if (percentChange!! > 0) "+$signSpace" else if (percentChange!! < 0) "-$signSpace" else "").plus(
                            kotlin.math.abs(percentChange!!).toString().plus("%")
                        )
                    priceChangeLabel.setTextColor(if (percentChange!! > 0) WColor.Green.color else if (percentChange!! < 0) WColor.Red.color else WColor.SecondaryText.color)
                } else {
                    priceChangeLabel.alpha = 0f
                    priceChangeLabel.text = null
                }
            } else {
                priceChangeLabel.alpha = 0f
                priceChangeLabel.text = null
            }
        } else {
            val decimals = token?.decimals ?: 9
            val priceBigInt = highlight!!.y.toDouble().toBigInteger(decimals)!!
            priceLabel.text = priceBigInt.toString(
                decimals,
                baseCurrencySign,
                (priceBigInt.smartDecimalsCount(decimals) + 2).coerceAtMost(decimals),
                false,
                forceCurrencyToRight = false
            )
            priceChangeLabel.text =
                Date(highlight!!.x.toLong() * 1000).formatDateAndTime(activePeriod)
        }
        updatePriceChangeLabelColor()
    }

    private fun setupLineChart() {
        val entries = mutableListOf<Entry>()

        highlightedHistoryData =
            DatasetHelpers.getHistoryDataInRange(this.historyData, startPercentage, endPercentage)
        highlightedHistoryData?.forEach { pair ->
            val timestamp = pair[0].toFloat()
            val value = pair[1].toFloat()
            entries.add(Entry(timestamp, value))
        }
        setupTexts()

        val dataSet = LineDataSet(entries, "")
        dataSet.lineWidth = 2.0f
        dataSet.color = WColor.Tint.color
        dataSet.setDrawCircles(false)
        dataSet.setDrawValues(false)
        dataSet.setDrawHorizontalHighlightIndicator(false)
        dataSet.setDrawVerticalHighlightIndicator(false)
        dataSet.setDrawFilled(true)
        val gradient = GradientDrawable(
            GradientDrawable.Orientation.TOP_BOTTOM,
            intArrayOf(WColor.Tint.color.colorWithAlpha(51), Color.TRANSPARENT)
        )
        gradient.setGradientType(GradientDrawable.LINEAR_GRADIENT)
        dataSet.fillDrawable = gradient
        dataSet.mode = LineDataSet.Mode.CUBIC_BEZIER

        val lineData = LineData(dataSet)

        fun setDataSet() {
            collapsedChartView.data = lineData
            collapsedChartView.invalidate()
            expandedChartView.data = lineData
            expandedChartView.invalidate()
            expandedChartView.dateFormat =
                SimpleDateFormat(
                    when (activePeriod) {
                        MHistoryTimePeriod.DAY -> {
                            "HH:mm"
                        }

                        MHistoryTimePeriod.ALL -> {
                            "MMM d, yyyy"
                        }

                        else -> {
                            "MMM d"
                        }
                    }, Locale(WGlobalStorage.getLangCode())
                )
            when (activePeriod) {
                MHistoryTimePeriod.ALL -> {
                    expandedChartView.xAxis.labelCount = 3
                }

                else -> {
                    expandedChartView.xAxis.labelCount = 5
                }
            }
            chartTimeLineView.configure(this.historyData)

        }
        if (highlightedHistoryData == null) {
            if (!areChartsFadeOut) {
                areChartsFadeOut = true
                var animation1: ObjectAnimator? = null
                if (collapsedChartView.isVisible)
                    animation1 = collapsedChartView.fadeOutObjectAnimator()
                else if (expandedChartView.isVisible) {
                    animation1 = expandedChartView.fadeOutObjectAnimator()
                }
                val animation2 =
                    if (chartTimeLineView.isVisible) chartTimeLineView.fadeOutObjectAnimator() else null
                val animation3 =
                    if (noDataLabel.isVisible) noDataLabel.fadeOutObjectAnimator() else null
                arrayOf(animation1, animation2, animation3).filterNotNull().let { animations ->
                    fun onEnd() {
                        isChangingPeriod = false
                        if (this@TokenChartCell.historyData.isNullOrEmpty()) {
                            progressTaskManager.startTaskIfEmpty({
                                progressView.visibility = VISIBLE
                                progressView.fadeIn()
                                chartTimeLineView.periodChanged()
                                if (areChartsFadeOut)
                                    chartTimeLineView.visibility = INVISIBLE
                            }, 1000)
                            setDataSet()
                        }
                    }
                    if (animations.isEmpty()) {
                        onEnd()
                        return
                    }
                    AnimatorSet().apply {
                        duration = AnimationConstants.VERY_VERY_QUICK_ANIMATION
                        playTogether(animations)
                        fun cleanup() {
                            WGlobalStorage.decDoNotSynchronize()
                            onEnd()
                        }
                        doOnEnd { cleanup() }
                        doOnCancel { cleanup() }
                        WGlobalStorage.incDoNotSynchronize()
                        start()
                    }
                }
            } else {
                setDataSet()
            }
        } else {
            progressTaskManager.cancelWork()
            progressView.fadeOut {
                progressView.visibility = GONE
            }
            setDataSet()
            if (areChartsFadeOut) {
                areChartsFadeOut = false
                var animation1: ObjectAnimator? = null
                var animation2: ObjectAnimator? = null
                var animation3: ObjectAnimator? = null
                if (collapsedChartView.isVisible) {
                    collapsedChartView.alpha = 0f
                    chartTimeLineView.isVisible = historyData?.isNotEmpty() == true
                    animation1 = collapsedChartView.fadeInObjectAnimator()
                } else
                    collapsedChartView.alpha = 1f
                if (expandedChartView.isVisible) {
                    expandedChartView.alpha = 0f
                    animation1 = expandedChartView.fadeInObjectAnimator()
                    chartTimeLineView.isVisible = historyData?.isNotEmpty() == true
                    if (chartTimeLineView.isVisible)
                        animation2 = chartTimeLineView.fadeInObjectAnimator()
                } else {
                    expandedChartView.alpha = 1f
                }
                noDataLabel.isVisible = historyData?.isEmpty() == true
                if (noDataLabel.isVisible)
                    animation3 = noDataLabel.fadeInObjectAnimator()
                arrayOf(animation1, animation2, animation3).filterNotNull().let { animations ->
                    if (animations.isEmpty())
                        return
                    AnimatorSet().apply {
                        duration = AnimationConstants.VERY_VERY_QUICK_ANIMATION
                        playTogether(animations)
                        doOnEnd {
                            WGlobalStorage.decDoNotSynchronize()
                        }
                        doOnCancel {
                            WGlobalStorage.decDoNotSynchronize()
                        }
                        WGlobalStorage.incDoNotSynchronize()
                        start()
                    }
                }
            }
        }
    }

    fun onDestroy() {
        onSelectedPeriodChanged = null
        onHeightChange = null
    }
}
