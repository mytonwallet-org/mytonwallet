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
import androidx.constraintlayout.widget.ConstraintLayout.LayoutParams.MATCH_CONSTRAINT
import androidx.constraintlayout.widget.ConstraintSet
import androidx.core.animation.doOnCancel
import androidx.core.animation.doOnEnd
import androidx.core.view.OneShotPreDrawListener
import androidx.core.view.doOnPreDraw
import androidx.core.view.isVisible
import androidx.core.view.setPadding
import androidx.core.view.updateLayoutParams
import androidx.dynamicanimation.animation.FloatValueHolder
import androidx.dynamicanimation.animation.SpringAnimation
import androidx.dynamicanimation.animation.SpringForce
import com.github.mikephil.charting.data.Entry
import com.github.mikephil.charting.data.LineData
import com.github.mikephil.charting.data.LineDataSet
import com.github.mikephil.charting.highlight.Highlight
import java.lang.Float.max
import java.util.Date
import kotlin.math.min
import kotlin.math.roundToInt
import org.mytonwallet.app_air.uiassets.viewControllers.token.helpers.DatasetHelpers
import org.mytonwallet.app_air.uiassets.viewControllers.token.helpers.TokenPriceInsight
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.commonViews.WAgentHintView
import org.mytonwallet.app_air.uicomponents.drawable.RoundProgressDrawable
import org.mytonwallet.app_air.uicomponents.extensions.asImage
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.adaptiveFontSize
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WFrameLayout
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WRecyclerView
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.chart.WChartTimeLineView
import org.mytonwallet.app_air.uicomponents.widgets.chart.WLineChartView
import org.mytonwallet.app_air.uicomponents.widgets.fadeIn
import org.mytonwallet.app_air.uicomponents.widgets.fadeOut
import org.mytonwallet.app_air.uicomponents.widgets.segmentedControlGroup.WSegmentedControlGroup
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.models.MBaseCurrency
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.MHistoryTimePeriod
import org.mytonwallet.app_air.walletbasecontext.utils.WDateFormatter
import org.mytonwallet.app_air.walletbasecontext.utils.formatDateAndTime
import org.mytonwallet.app_air.walletbasecontext.utils.signSpace
import org.mytonwallet.app_air.walletbasecontext.utils.smartDecimalsCount
import org.mytonwallet.app_air.walletbasecontext.utils.toBigInteger
import org.mytonwallet.app_air.walletbasecontext.utils.toString
import org.mytonwallet.app_air.walletbasecontext.utils.withLocalizedNumbers
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.helpers.TaskManager
import org.mytonwallet.app_air.walletcontext.utils.AnimUtils.Companion.lerp
import org.mytonwallet.app_air.walletcontext.utils.colorWithAlpha
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.models.MToken

@SuppressLint("ViewConstructor")
class TokenChartCell(
    recyclerView: WRecyclerView,
    var activePeriod: MHistoryTimePeriod,
    var onSelectedPeriodChanged: ((MHistoryTimePeriod) -> Unit)?,
    private var onAgentPrompt: ((String) -> Unit)?,
    private var onHeightChange: ((isExpanding: Boolean, height: Int) -> Unit)?
) : WCell(recyclerView.context, LayoutParams(MATCH_PARENT, WRAP_CONTENT)),
    WThemedView {

    companion object {
        private const val PRICE_INSIGHT_FADE_START_PROGRESS = 0.66f
        private const val PRICE_INSIGHT_HEIGHT_DP = 35
        private const val PRICE_INSIGHT_BOTTOM_MARGIN_DP = 19f
        private const val PRICE_INSIGHT_VERTICAL_SPACING_DP = 27
    }

    private var percentChange: Double? = null
    private var priceInsight: TokenPriceInsight? = null
    private var priceInsightHeightSpring: SpringAnimation? = null
    private var priceInsightPreDrawListener: OneShotPreDrawListener? = null
    private var chartFadeAnimator: AnimatorSet? = null
    private val priceInsightExpiryRunnable = Runnable { updatePriceInsight() }
    private var pendingAnimationToConfigure = false
    private var pendingPriceInsightUpdate = false
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
    private var isExpanded = WGlobalStorage.getIsTokenChartExpanded()
    private var isChangingPeriod = false
        set(value) {
            field = value
            if (!value) {
                if (pendingPriceInsightUpdate) {
                    pendingPriceInsightUpdate = false
                    updatePriceInsight()
                }
                if (!isAnimating && pendingAnimationToConfigure) {
                    pendingAnimationToConfigure = false
                    setupLineChart()
                }
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
        lbl.setStyle(adaptiveFontSize(), WFont.Medium)
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
        drawable.isAutoMirrored = false
        setColorFilter(WColor.SecondaryText.color, PorterDuff.Mode.SRC_IN)
        rotation = if (isExpanded) 270f else 90f
    }

    private val collapsedChartView = WLineChartView(context, false).apply {
        setTouchEnabled(false)
        visibility = if (isExpanded) INVISIBLE else VISIBLE
        alpha = 0f
    }
    private val expandedChartView = WLineChartView(context, true).apply {
        visibility = if (isExpanded) VISIBLE else INVISIBLE
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

    private val agentHintView = WAgentHintView(
        context,
        "",
        contentVerticalPadding = 8.dp,
        animatePressAlpha = false
    ) {
        val insight = priceInsight ?: return@WAgentHintView
        val tokenName = token?.displayName ?: token?.name ?: return@WAgentHintView
        onAgentPrompt?.invoke(insight.prompt(tokenName))
    }.apply {
        minimumHeight = PRICE_INSIGHT_HEIGHT_DP.dp
        visibility = GONE
        addOnLayoutChangeListener { _, _, top, _, bottom, _, oldTop, _, oldBottom ->
            if (bottom - top != oldBottom - oldTop) updateMeasuredPriceInsightHeight()
        }
    }

    private val roundDrawable = RoundProgressDrawable(12f.dp, 0.5f.dp)

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
        addView(chartTimeLineView, LayoutParams(MATCH_CONSTRAINT, 36.dp))
        addView(segmentedControlGroupContainer, LayoutParams(0, 46.dp))
        addView(
            agentHintView,
            LayoutParams(WRAP_CONTENT, WRAP_CONTENT).apply {
                constrainedWidth = true
            }
        )
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
            toCenterX(chartTimeLineView)
            bottomToTop(chartTimeLineView, segmentedControlGroupContainer, 8f)
            toCenterX(segmentedControlGroupContainer, 12f)
            toBottom(segmentedControlGroupContainer)
            toCenterX(agentHintView, 20f)
        }
        post {
            progressView.x =
                collapsedChartView.x +
                if (LocaleController.isRTL) 0 else collapsedChartView.width - progressViewWidth
            progressView.y = 20f.dp
            noDataLabel.x =
                collapsedChartView.x + (collapsedChartView.width - noDataLabelWidth)
            noDataLabel.y =
                collapsedChartView.y + (collapsedChartView.height - noDataLabelHeight) / 2f
            noDataMaxX = noDataLabel.x
            if (isExpanded) {
                renderProgressView(expandedChartView, 1f)
                renderNoDataLabel(expandedChartView, 1f)
            }
            if (historyData.isNullOrEmpty()) {
                progressTaskManager.startTask({
                    progressView.visibility = VISIBLE
                    progressView.fadeIn()
                }, 1000)
            }
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
        containerView.setOnClickListener {
            // Expand
            // Collapse
            if (isAnimating) return@setOnClickListener
            settlePriceInsightLayout()
            isAnimating = true
            collapsedChartImageView.setImageBitmap(collapsedChartView.asImage())
            expandedChartImageView.setImageBitmap(expandedChartView.asImage())
            // Collapse
            if (isExpanded) {
                // Collapse
                val startValue = containerView.height.toFloat()
                val endValue = 64.dp.toFloat()
                startSpringAnimation(startValue, endValue)
            } else {
                // Expand
                val startValue = 64.dp.toFloat()
                val endValue = expandedHeight().toFloat()
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
        if (isExpanded) {
            collapsedChartView.visibility = INVISIBLE
            expandedChartView.visibility = VISIBLE
            segmentedControlGroupContainer.alpha = 1f
            segmentedControlGroupContainer.visibility = VISIBLE
            chartTimeLineView.alpha = 1f
            chartTimeLineView.isVisible = historyData?.isNotEmpty() == true
            containerView.doOnPreDraw {
                if (isExpanded && !isAnimating) settlePriceInsightLayout()
            }
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
        chartTimeLineView.updateTheme()
        segmentedControlGroup.updateTheme()
        agentHintView.updateTheme()
    }

    private fun updatePriceChangeLabelColor() {
        priceChangeLabel.setTextColor(
            if (highlight != null ||
                percentChange == 0.0
            ) {
                WColor.SecondaryText.color
            } else if ((
                    percentChange
                        ?: 0.0
                    ) > 0.0
            ) {
                WColor.Green.color
            } else {
                WColor.Red.color
            }
        )
    }

    private fun renderChartAnimationFrame(isExpanding: Boolean, fraction: Float, height: Float) {
        val containerLayoutParams = containerView.layoutParams
        containerLayoutParams.height = height.roundToInt()
        containerView.layoutParams = containerLayoutParams
        onHeightChange?.invoke(isExpanding, containerLayoutParams.height)

        arrowIcon.rotation = 90f + 180f * fraction
        collapsedChartImageView.alpha = min(1 - fraction, collapsedChartView.alpha)
        expandedChartImageView.alpha = min(fraction, expandedChartView.alpha)
        val chartLayoutParams = collapsedChartImageView.layoutParams
        chartLayoutParams.width =
            collapsedChartView.width +
            (((expandedChartView.width - 20.dp) - collapsedChartView.width) * fraction).roundToInt()
        val expandedHeight = expandedChartView.height - 16.dp
        chartLayoutParams.height = collapsedChartView.height +
            ((expandedHeight - collapsedChartView.height) * fraction).roundToInt()
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
        val renderedChartAlpha = max(collapsedChartImageView.alpha, expandedChartImageView.alpha)
        val priceInsightGapProgress = currentPriceInsightGapProgress()
        updatePriceInsightAlpha(renderedChartAlpha, allowVisible = true)
        agentHintView.translationY = 8.dp * (1f - priceInsightGapProgress)
        segmentedControlGroupContainer.visibility =
            if (segmentedControlGroupContainer.alpha > 0) VISIBLE else INVISIBLE
    }

    private fun renderProgressView(chartView: View, expandProgress: Float) {
        if (chartView.width == 0) return
        val horizontalProgress = if (LocaleController.isRTL) expandProgress else 1f
        progressView.x =
            chartView.x +
            (chartView.width - progressViewWidth) * horizontalProgress / (1 + expandProgress) +
            (expandProgress * 10.dp)
        progressView.y =
            chartView.y + (chartView.height - progressViewWidth) / 2 +
            (27.dp * expandProgress)
    }

    private fun renderNoDataLabel(chartView: View, expandProgress: Float) {
        if (chartView.width == 0) return
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
                WGlobalStorage.setIsTokenChartExpanded(isExpanded)
                isAnimating = false
                settlePriceInsightLayout()
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
        if (isChangingPeriod) {
            pendingPriceInsightUpdate = true
            if (historyData == null) {
                containerView.removeCallbacks(priceInsightExpiryRunnable)
            }
        } else {
            updatePriceInsight()
        }
        if (!isAnimating && (!isChangingPeriod || historyData == null)) {
            setupLineChart()
        } else {
            pendingAnimationToConfigure = true
        }
        updateTheme()
    }

    private fun updatePriceInsight() {
        val previousInsight = priceInsight
        val tokenName = token?.displayName ?: token?.name
        val newInsight = if (
            WGlobalStorage.getAreExperimentalFeaturesEnabled() && tokenName != null
        ) {
            TokenPriceInsight.calculate(activePeriod, historyData, token?.price)
        } else {
            null
        }
        priceInsight = newInsight
        schedulePriceInsightExpiry(newInsight)
        if (newInsight != null && tokenName != null) {
            agentHintView.setTitle(newInsight.title(tokenName))
        }

        val presenceChanged = (previousInsight == null) != (newInsight == null)
        if (presenceChanged && isExpanded && !isAnimating &&
            WGlobalStorage.getAreAnimationsActive()
        ) {
            if (newInsight != null) {
                animatePriceInsightAppearance()
            } else {
                animatePriceInsightDisappearance()
            }
        } else if (priceInsightHeightSpring == null) {
            settlePriceInsightLayout()
        }
    }

    private fun schedulePriceInsightExpiry(insight: TokenPriceInsight?) {
        containerView.removeCallbacks(priceInsightExpiryRunnable)
        if (insight == null) return
        val delayMs =
            (insight.expiresAtTimestampSeconds * 1000.0 - System.currentTimeMillis()).toLong() + 1
        if (delayMs > 0L) containerView.postDelayed(priceInsightExpiryRunnable, delayMs)
    }

    private fun setPriceInsightConstraints(hasInsight: Boolean) {
        containerView.setConstraints {
            clear(segmentedControlGroupContainer.id, ConstraintSet.BOTTOM)
            clear(agentHintView.id, ConstraintSet.TOP)
            clear(agentHintView.id, ConstraintSet.BOTTOM)
            if (hasInsight) {
                bottomToTop(segmentedControlGroupContainer, agentHintView, 8f)
                toBottom(agentHintView, PRICE_INSIGHT_BOTTOM_MARGIN_DP)
            } else {
                toBottom(segmentedControlGroupContainer)
            }
        }
    }

    private fun animatePriceInsightAppearance() {
        cancelPriceInsightAnimation()
        setPriceInsightConstraints(true)
        updatePriceInsightAlpha()
        agentHintView.translationY = 8f.dp
        agentHintView.visibility = INVISIBLE
        priceInsightPreDrawListener = containerView.doOnPreDraw {
            priceInsightPreDrawListener = null
            if (
                priceInsight == null || !isExpanded || isAnimating
            ) {
                return@doOnPreDraw
            }

            agentHintView.visibility = VISIBLE
            agentHintView.animate()
                .translationY(0f)
                .setDuration(AnimationConstants.VERY_QUICK_ANIMATION)
                .start()
            val targetHeight = expandedHeight()
            startPriceInsightHeightSpring(
                targetHeight,
                onUpdate = {
                    updatePriceInsightAlpha()
                },
                onEnd = {
                    if (priceInsight != null) {
                        updatePriceInsightAlpha()
                        agentHintView.translationY = 0f
                    }
                }
            )
        }
    }

    private fun animatePriceInsightDisappearance() {
        cancelPriceInsightAnimation()
        setPriceInsightConstraints(true)
        agentHintView.visibility = VISIBLE
        agentHintView.animate()
            .alpha(0f)
            .translationY(8f.dp)
            .setDuration(AnimationConstants.VERY_QUICK_ANIMATION)
            .start()
        startPriceInsightHeightSpring(baseExpandedHeight()) {
            if (priceInsight == null) {
                setPriceInsightConstraints(false)
                agentHintView.visibility = GONE
            }
        }
    }

    private fun startPriceInsightHeightSpring(
        targetHeight: Int,
        onUpdate: (height: Float) -> Unit = {},
        onEnd: () -> Unit
    ) {
        val startHeight = containerView.height
        if (startHeight == targetHeight) {
            onUpdate(targetHeight.toFloat())
            onEnd()
            segmentedControlGroupContainer.translationY = 0f
            chartTimeLineView.translationY = 0f
            return
        }

        val isExpanding = targetHeight > startHeight
        val currentControlsTranslation = segmentedControlGroupContainer.translationY
        val initialControlsTranslation =
            if (isExpanding && currentControlsTranslation == 0f) {
                (targetHeight - startHeight).toFloat()
            } else {
                currentControlsTranslation
            }
        segmentedControlGroupContainer.translationY = initialControlsTranslation
        chartTimeLineView.translationY = initialControlsTranslation
        val animation = SpringAnimation(FloatValueHolder()).apply {
            setStartValue(startHeight.toFloat())
            spring = SpringForce(targetHeight.toFloat()).apply {
                stiffness = SpringForce.STIFFNESS_LOW
                dampingRatio = SpringForce.DAMPING_RATIO_NO_BOUNCY
            }
        }
        priceInsightHeightSpring = animation
        animation.addUpdateListener { _, value, _ ->
            val height = value.roundToInt()
            containerView.updateLayoutParams { this.height = height }
            val controlsTranslation = initialControlsTranslation + startHeight - height
            segmentedControlGroupContainer.translationY = controlsTranslation
            chartTimeLineView.translationY = controlsTranslation
            onUpdate(height.toFloat())
            onHeightChange?.invoke(isExpanding, height)
        }
        animation.addEndListener { _, canceled, _, _ ->
            WGlobalStorage.decDoNotSynchronize()
            if (priceInsightHeightSpring === animation) priceInsightHeightSpring = null
            if (!canceled) {
                containerView.updateLayoutParams { height = targetHeight }
                val finalControlsTranslation =
                    initialControlsTranslation + startHeight - targetHeight
                segmentedControlGroupContainer.translationY = finalControlsTranslation
                chartTimeLineView.translationY = finalControlsTranslation
                onHeightChange?.invoke(isExpanding, targetHeight)
                onUpdate(targetHeight.toFloat())
                onEnd()
                segmentedControlGroupContainer.translationY = 0f
                chartTimeLineView.translationY = 0f
            }
        }
        WGlobalStorage.incDoNotSynchronize()
        animation.start()
    }

    private fun cancelPriceInsightAnimation() {
        priceInsightPreDrawListener?.removeListener()
        priceInsightPreDrawListener = null
        agentHintView.animate().cancel()
        agentHintView.scaleX = 1f
        agentHintView.scaleY = 1f
        priceInsightHeightSpring?.cancel()
        priceInsightHeightSpring = null
    }

    private fun settlePriceInsightLayout() {
        cancelPriceInsightAnimation()
        val hasInsight = priceInsight != null
        setPriceInsightConstraints(hasInsight)
        segmentedControlGroupContainer.translationY = 0f
        chartTimeLineView.translationY = 0f

        if (isExpanded && !isAnimating) {
            val oldHeight = containerView.height
            val newHeight = expandedHeight()
            if (oldHeight != newHeight) {
                containerView.updateLayoutParams { height = newHeight }
                onHeightChange?.invoke(newHeight > oldHeight, newHeight)
            }
        }

        val shouldShow = hasInsight && isExpanded && !isAnimating
        if (shouldShow) updatePriceInsightAlpha() else agentHintView.alpha = 0f
        agentHintView.translationY = if (shouldShow) 0f else 8f.dp
        if (!shouldShow) {
            agentHintView.visibility = if (hasInsight) INVISIBLE else GONE
        }
    }

    private fun currentPriceInsightGapProgress(): Float {
        val renderedHeight = containerView.layoutParams.height
        return (
            (renderedHeight - baseExpandedHeight()).toFloat() /
                priceInsightAreaHeight()
            ).coerceIn(0f, 1f)
    }

    private fun updateMeasuredPriceInsightHeight() {
        if (
            priceInsight == null || !isExpanded || isAnimating ||
            priceInsightPreDrawListener != null || priceInsightHeightSpring != null
        ) {
            return
        }

        val oldHeight = containerView.layoutParams.height
        val newHeight = expandedHeight()
        if (oldHeight == newHeight) return

        if (WGlobalStorage.getAreAnimationsActive()) {
            val controlsTranslation = (newHeight - containerView.height).toFloat()
            segmentedControlGroupContainer.translationY = controlsTranslation
            chartTimeLineView.translationY = controlsTranslation
            startPriceInsightHeightSpring(
                newHeight,
                onUpdate = { updatePriceInsightAlpha() },
                onEnd = { updatePriceInsightAlpha() }
            )
            return
        }

        containerView.updateLayoutParams { height = newHeight }
        onHeightChange?.invoke(newHeight > oldHeight, newHeight)
        updatePriceInsightAlpha()
    }

    private fun activeChartAlpha(): Float =
        (if (isExpanded) expandedChartView.alpha else collapsedChartView.alpha).coerceIn(0f, 1f)

    private fun updatePriceInsightAlpha(
        chartAlpha: Float = activeChartAlpha(),
        allowVisible: Boolean = isExpanded && !isAnimating
    ) {
        if (priceInsight == null) {
            agentHintView.alpha = 0f
            return
        }
        val priceInsightGapProgress = currentPriceInsightGapProgress()
        val normalizedGapProgress =
            (priceInsightGapProgress - PRICE_INSIGHT_FADE_START_PROGRESS) /
                (1f - PRICE_INSIGHT_FADE_START_PROGRESS)
        val gapAlpha = normalizedGapProgress.coerceIn(0f, 1f)
        agentHintView.alpha = min(gapAlpha, chartAlpha.coerceIn(0f, 1f))
        agentHintView.visibility =
            if (agentHintView.alpha > 0f && allowVisible) VISIBLE else INVISIBLE
    }

    private fun alphaObjectAnimator(view: View, targetAlpha: Float): ObjectAnimator? {
        view.visibility = VISIBLE
        if (!WGlobalStorage.getAreAnimationsActive() || view.alpha == targetAlpha) {
            view.alpha = targetAlpha
            return null
        }
        return ObjectAnimator.ofFloat(view, View.ALPHA, view.alpha, targetAlpha)
    }

    private fun startChartFadeAnimation(animations: List<ObjectAnimator>, onEnd: () -> Unit = {}) {
        if (animations.isEmpty()) {
            onEnd()
            return
        }

        var canceled = false
        val animator = AnimatorSet().apply {
            duration = AnimationConstants.VERY_VERY_QUICK_ANIMATION
            playTogether(animations)
        }
        chartFadeAnimator = animator
        animator.doOnCancel { canceled = true }
        animator.doOnEnd {
            if (chartFadeAnimator === animator) chartFadeAnimator = null
            WGlobalStorage.decDoNotSynchronize()
            if (!canceled) onEnd()
        }
        WGlobalStorage.incDoNotSynchronize()
        animator.start()
    }

    private fun cancelChartFadeAnimation() {
        chartFadeAnimator?.cancel()
        chartFadeAnimator = null
    }

    private fun baseExpandedHeight() = 182.dp + ((width - 20.dp) * 79 / 392)

    private fun priceInsightAreaHeight() =
        maxOf(agentHintView.measuredHeight, PRICE_INSIGHT_HEIGHT_DP.dp) +
            PRICE_INSIGHT_VERTICAL_SPACING_DP.dp

    private fun expandedHeight(): Int {
        val baseHeight = baseExpandedHeight()
        if (priceInsight == null) return baseHeight
        return baseHeight + priceInsightAreaHeight()
    }

    @SuppressLint("SetTextI18n")
    private fun setupTexts() {
        val baseCurrencySign =
            if (token?.symbol != WalletCore.baseCurrency.currencyCode) {
                WalletCore.baseCurrency.sign
            } else {
                MBaseCurrency.USD.sign
            }
        val price = if (highlightedHistoryData.isNullOrEmpty()) {
            token!!.price
        } else {
            highlightedHistoryData!!.last()[1]
        }
        val firstPrice = (highlightedHistoryData ?: historyData)?.firstOrNull {
            it[1] != 0.0
        }?.get(1)
        if (highlight == null) {
            if (token?.price != null) {
                percentChange = firstPrice?.let { firstPriceInChart ->
                    ((price!! - firstPriceInChart) / firstPriceInChart * 10000)
                }?.let {
                    kotlin.math.round(it) / 100
                }
                if (percentChange != null) {
                    if (priceChangeLabel.alpha == 0f) priceChangeLabel.fadeIn()
                    priceChangeLabel.text =
                        "\u202D" +
                        (
                            if (percentChange!! >
                                0
                            ) {
                                "+$signSpace"
                            } else if (percentChange!! <
                                0
                            ) {
                                "-$signSpace"
                            } else {
                                ""
                            }
                            ).plus(
                            kotlin.math.abs(percentChange!!).withLocalizedNumbers.plus("%")
                        )
                    priceChangeLabel.setTextColor(
                        if (percentChange!! >
                            0
                        ) {
                            WColor.Green.color
                        } else if (percentChange!! <
                            0
                        ) {
                            WColor.Red.color
                        } else {
                            WColor.SecondaryText.color
                        }
                    )
                } else {
                    priceChangeLabel.alpha = 0f
                    priceChangeLabel.text = null
                }
            } else {
                priceChangeLabel.alpha = 0f
                priceChangeLabel.text = null
            }
            val priceBigInt = price?.toBigInteger(9)
            val priceText = priceBigInt?.toString(
                9,
                baseCurrencySign,
                priceBigInt.smartDecimalsCount(9).coerceAtLeast(2),
                false,
                forceCurrencyToRight = false
            )
            priceLabel.text = priceText?.let {
                (
                    if (LocaleController.isRTL &&
                        priceChangeLabel.text.isNotEmpty()
                    ) {
                        "\u202D · "
                    } else {
                        ""
                    }
                    ) +
                    it
            } ?: ""
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
            val langCode = WGlobalStorage.getLangCode()
            val isDayFirst = WDateFormatter.isDayBeforeMonth(langCode)
            expandedChartView.dateFormat =
                WDateFormatter.of(
                    when (activePeriod) {
                        MHistoryTimePeriod.DAY -> {
                            "HH:mm"
                        }

                        MHistoryTimePeriod.ALL -> {
                            if (isDayFirst) "d MMM yyyy" else "MMM d, yyyy"
                        }

                        else -> {
                            if (isDayFirst) "d MMM" else "MMM d"
                        }
                    },
                    langCode
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
                cancelChartFadeAnimation()
                var animation1: ObjectAnimator? = null
                if (collapsedChartView.isVisible) {
                    animation1 = alphaObjectAnimator(collapsedChartView, 0f)
                } else if (expandedChartView.isVisible) {
                    animation1 = alphaObjectAnimator(expandedChartView, 0f)
                }
                val animation2 =
                    if (chartTimeLineView.isVisible) {
                        alphaObjectAnimator(chartTimeLineView, 0f)
                    } else {
                        null
                    }
                val animation3 =
                    if (noDataLabel.isVisible) alphaObjectAnimator(noDataLabel, 0f) else null
                animation1?.addUpdateListener { updatePriceInsightAlpha() }
                updatePriceInsightAlpha()
                startChartFadeAnimation(
                    arrayOf(animation1, animation2, animation3).filterNotNull()
                ) {
                    if (priceInsight != null && agentHintView.alpha == 0f) {
                        agentHintView.visibility = INVISIBLE
                    }
                    isChangingPeriod = false
                    if (this@TokenChartCell.historyData.isNullOrEmpty()) {
                        progressTaskManager.startTaskIfEmpty({
                            progressView.visibility = VISIBLE
                            progressView.fadeIn()
                            chartTimeLineView.periodChanged()
                            if (areChartsFadeOut) chartTimeLineView.visibility = INVISIBLE
                        }, 1000)
                        setDataSet()
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
                cancelChartFadeAnimation()
                var animation1: ObjectAnimator? = null
                var animation2: ObjectAnimator? = null
                var animation3: ObjectAnimator? = null
                if (collapsedChartView.isVisible) {
                    collapsedChartView.alpha = 0f
                    chartTimeLineView.isVisible = historyData?.isNotEmpty() == true
                    animation1 = alphaObjectAnimator(collapsedChartView, 1f)
                } else {
                    collapsedChartView.alpha = 1f
                }
                if (expandedChartView.isVisible) {
                    expandedChartView.alpha = 0f
                    animation1 = alphaObjectAnimator(expandedChartView, 1f)
                    chartTimeLineView.isVisible = historyData?.isNotEmpty() == true
                    if (chartTimeLineView.isVisible) {
                        animation2 = alphaObjectAnimator(chartTimeLineView, 1f)
                    }
                } else {
                    expandedChartView.alpha = 1f
                }
                noDataLabel.isVisible = historyData?.isEmpty() == true
                if (noDataLabel.isVisible) animation3 = alphaObjectAnimator(noDataLabel, 1f)
                animation1?.addUpdateListener { updatePriceInsightAlpha() }
                updatePriceInsightAlpha()
                startChartFadeAnimation(
                    arrayOf(animation1, animation2, animation3).filterNotNull()
                )
            }
        }
    }

    fun onDestroy() {
        containerView.removeCallbacks(priceInsightExpiryRunnable)
        cancelChartFadeAnimation()
        cancelPriceInsightAnimation()
        onSelectedPeriodChanged = null
        onAgentPrompt = null
        onHeightChange = null
    }
}
