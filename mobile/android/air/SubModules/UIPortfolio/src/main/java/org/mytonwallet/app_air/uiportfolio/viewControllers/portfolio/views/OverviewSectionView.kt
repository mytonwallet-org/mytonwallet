package org.mytonwallet.app_air.uiportfolio.viewControllers.portfolio.views

import android.annotation.SuppressLint
import android.content.Context
import android.view.View
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import androidx.constraintlayout.widget.Barrier
import androidx.constraintlayout.widget.Guideline
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WBaseView
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.fadeIn
import org.mytonwallet.app_air.uicomponents.widgets.fadeOut
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.uiportfolio.viewControllers.portfolio.models.PortfolioOverview
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.models.MBaseCurrency
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.toString
import java.math.BigInteger
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlin.math.abs
import kotlin.math.pow
import kotlin.math.roundToInt

@SuppressLint("ViewConstructor")
class OverviewSectionView(context: Context) : WView(context), WThemedView {

    private val titleLabel = WLabel(context).apply {
        id = generateViewId()
        text = LocaleController.getString("Overview")
        setStyle(14f, WFont.DemiBold)
        setTextColor(WColor.Tint)
    }
    private val dateRangeLabel = WLabel(context).apply {
        id = generateViewId()
        setStyle(14f, WFont.Regular)
        setTextColor(WColor.SecondaryText)
    }
    private val totalValueLabel = WLabel(context).apply {
        id = generateViewId()
        setStyle(16f, WFont.DemiBold)
        setPadding(0, 0, 16.dp, 0)
    }
    private val totalCaptionLabel = WLabel(context).apply {
        id = generateViewId()
        text = LocaleController.getString("Total Balance")
        setStyle(13f)
        setTextColor(WColor.SecondaryText)
        setPadding(0, 0, 16.dp, 0)
    }
    private val netChangeLabel = WLabel(context).apply {
        id = generateViewId()
        setStyle(16f, WFont.DemiBold)
        setTextColor(WColor.PrimaryText)
    }
    private val netPctLabel = WLabel(context).apply {
        id = generateViewId()
        setStyle(13f, WFont.DemiBold)
    }
    private val netCaptionLabel = WLabel(context).apply {
        id = generateViewId()
        text = LocaleController.getString("Net Change")
        setStyle(13f)
        setTextColor(WColor.SecondaryText)
    }

    private val datePlaceholder = WBaseView(context).apply {
        id = generateViewId()
        visibility = GONE
    }
    private val totalValuePlaceholder = WBaseView(context).apply {
        id = generateViewId()
        visibility = GONE
    }
    private val netChangePlaceholder = WBaseView(context).apply {
        id = generateViewId()
        visibility = GONE
    }

    private val netChangeBox = WView(context).apply {
        id = generateViewId()
        addView(netChangeLabel, LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        addView(netPctLabel, LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        addView(netCaptionLabel, LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        addView(netChangePlaceholder, LayoutParams(140.dp, 22.dp))
        setConstraints {
            toTop(netChangeLabel)
            toStart(netChangeLabel)
            startToEnd(netPctLabel, netChangeLabel, 6f)
            baseLineToBasLine(netPctLabel, netChangeLabel)
            toEnd(netPctLabel)
            setHorizontalBias(netPctLabel.id, 0f)
            topToBottom(netCaptionLabel, netChangeLabel, 1f)
            toStart(netCaptionLabel)
            toBottom(netCaptionLabel)
            topToTop(netChangePlaceholder, netChangeLabel)
            startToStart(netChangePlaceholder, netChangeLabel)
        }
    }

    private val centerGuideline = Guideline(context).apply {
        id = generateViewId()
    }
    private val centerAnchor = WBaseView(context).apply {
        id = generateViewId()
    }
    private val netStartBarrier = Barrier(context).apply {
        id = generateViewId()
        type = Barrier.END
    }

    init {
        setPadding(16.dp, 16.dp, 20.dp, 10.dp)

        addView(titleLabel, LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        addView(dateRangeLabel, LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        addView(totalValueLabel, LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        addView(totalCaptionLabel, LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        addView(netChangeBox, LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        addView(datePlaceholder, LayoutParams(180.dp, 20.dp))
        addView(totalValuePlaceholder, LayoutParams(120.dp, 22.dp))
        addVerticalGuideline(centerGuideline)
        addView(centerAnchor, LayoutParams(0, 0))
        addView(netStartBarrier)
        netStartBarrier.referencedIds =
            intArrayOf(totalValueLabel.id, totalCaptionLabel.id, centerAnchor.id)
        setConstraints {
            guidelinePercent(centerGuideline, 0.5f)
            startToStart(centerAnchor, centerGuideline)
            endToEnd(centerAnchor, centerGuideline)
            toTop(centerAnchor)
            toTop(titleLabel)
            toStart(titleLabel, 4f)
            toTop(dateRangeLabel)
            toEnd(dateRangeLabel)
            topToBottom(totalValueLabel, titleLabel, 14f)
            toStart(totalValueLabel)
            topToBottom(totalCaptionLabel, totalValueLabel, 1f)
            toStart(totalCaptionLabel)
            toBottom(totalCaptionLabel)
            topToBottom(netChangeBox, dateRangeLabel, 14f)
            startToEnd(netChangeBox, netStartBarrier)
            endToEnd(netChangeBox, dateRangeLabel)
            toBottom(netChangeBox)
            setHorizontalBias(netChangeBox.id, 0f)

            topToTop(datePlaceholder, dateRangeLabel)
            endToEnd(datePlaceholder, dateRangeLabel)
            topToTop(totalValuePlaceholder, totalValueLabel)
            startToStart(totalValuePlaceholder, totalValueLabel)
        }
    }

    fun maskTargets(): List<Pair<View, Float>> = listOf(
        datePlaceholder to 4f.dp,
        totalValuePlaceholder to 4f.dp,
        netChangePlaceholder to 4f.dp,
    )

    fun crossFadeTargets(): List<View> =
        listOf(dateRangeLabel, totalValueLabel, netChangeLabel, netPctLabel)

    fun render(overview: PortfolioOverview?, baseCurrency: MBaseCurrency?) {
        if (overview == null || baseCurrency == null) {
            dateRangeLabel.text = ""
            totalValueLabel.text = ""
            netChangeLabel.text = ""
            netPctLabel.visibility = GONE
            return
        }
        dateRangeLabel.text = formatDateRange(overview.startTimestampMs, overview.endTimestampMs)
        totalValueLabel.text =
            formatOverviewCurrency(overview.totalValue, baseCurrency, showSign = false)
        netChangeLabel.text =
            formatOverviewCurrency(overview.netChangeAbs, baseCurrency, showSign = true)
        val isPositive = overview.netChangeAbs >= 0.0
        val deltaColor = if (isPositive) WColor.Green.color else WColor.Red.color
        val pct = overview.netChangePct
        if (pct == null) {
            netPctLabel.text = ""
            netPctLabel.visibility = GONE
        } else {
            netPctLabel.visibility = VISIBLE
            netPctLabel.text = formatPercent(pct)
            netPctLabel.setTextColor(deltaColor)
        }
    }

    fun showPlaceholders(animated: Boolean = false) {
        val clearText = {
            dateRangeLabel.text = ""
            totalValueLabel.text = ""
            netChangeLabel.text = ""
            netPctLabel.visibility = GONE
        }
        val targets = listOf(datePlaceholder, totalValuePlaceholder, netChangePlaceholder)
        targets.forEach { it.visibility = VISIBLE }
        if (animated) {
            targets.forEachIndexed { index, placeholder ->
                if (index == 0) {
                    placeholder.fadeIn(onCompletion = clearText)
                } else {
                    placeholder.fadeIn()
                }
            }
        } else {
            targets.forEach { it.alpha = 1f }
            clearText()
        }
    }

    fun hidePlaceholders() {
        datePlaceholder.fadeOut { datePlaceholder.visibility = GONE }
        totalValuePlaceholder.fadeOut { totalValuePlaceholder.visibility = GONE }
        netChangePlaceholder.fadeOut { netChangePlaceholder.visibility = GONE }
    }

    override fun updateTheme() {
        setBackgroundColor(WColor.Background.color, ViewConstants.BLOCK_RADIUS.dp)
        totalValueLabel.setTextColor(WColor.PrimaryText)
        val placeholderBg = WColor.SecondaryBackground.color
        datePlaceholder.setBackgroundColor(placeholderBg, 4f.dp)
        totalValuePlaceholder.setBackgroundColor(placeholderBg, 4f.dp)
        netChangePlaceholder.setBackgroundColor(placeholderBg, 4f.dp)
    }

    private fun formatDateRange(startMs: Long, endMs: Long): String {
        val fmt = SimpleDateFormat("d MMM yyyy", Locale.getDefault())
        return "${fmt.format(Date(startMs))} – ${fmt.format(Date(endMs))}"
    }

    private fun formatOverviewCurrency(
        value: Double,
        baseCurrency: MBaseCurrency,
        showSign: Boolean,
    ): String {
        val scale = 10.0.pow(baseCurrency.decimalsCount.toDouble())
        val scaled = (abs(value) * scale).toLong()
        val signedScaled = if (value < 0) -scaled else scaled
        return BigInteger.valueOf(signedScaled).toString(
            decimals = baseCurrency.decimalsCount,
            currency = baseCurrency.sign,
            currencyDecimals = baseCurrency.decimalsCount,
            showPositiveSign = showSign,
        )
    }

    private fun formatPercent(ratio: Double): String {
        val pct = ratio * 100.0
        val abs = abs(pct)
        return if (abs < 10.0 && abs != 0.0) {
            String.format(Locale.ENGLISH, "%.1f%%", abs)
        } else {
            "${abs.roundToInt()}%"
        }
    }
}
