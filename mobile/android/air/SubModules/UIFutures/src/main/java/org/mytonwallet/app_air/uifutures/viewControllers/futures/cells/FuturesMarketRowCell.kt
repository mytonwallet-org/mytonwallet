package org.mytonwallet.app_air.uifutures.viewControllers.futures.cells

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Color
import android.text.TextUtils
import android.view.Gravity
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import androidx.core.view.updateLayoutParams
import androidx.recyclerview.widget.RecyclerView
import kotlin.math.abs
import org.mytonwallet.app_air.uiassets.viewControllers.token.helpers.formatCompactNumber
import org.mytonwallet.app_air.uicomponents.drawable.WRippleDrawable
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.image.Content
import org.mytonwallet.app_air.uicomponents.image.WCustomImageView
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.uifutures.viewControllers.futures.helpers.pnlColor
import org.mytonwallet.app_air.uifutures.viewControllers.futures.helpers.toPercentString
import org.mytonwallet.app_air.uifutures.viewControllers.futures.helpers.toPriceString
import org.mytonwallet.app_air.uifutures.viewControllers.futures.helpers.toUsdString
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcontext.utils.colorWithAlpha
import org.mytonwallet.app_air.walletcore.moshi.MApiPerpsListedAsset

/** One perps market: ticker, maximum leverage, 24h volume, mark price and its 24h change. */
@SuppressLint("ViewConstructor")
class FuturesMarketRowCell(context: Context, private val onTap: (MApiPerpsListedAsset) -> Unit) :
    WCell(context, RecyclerView.LayoutParams(MATCH_PARENT, WRAP_CONTENT)),
    WThemedView {

    private var market: MApiPerpsListedAsset? = null
    private var isFirst = false
    private var isLast = false

    private val ripple = WRippleDrawable.create(0f)
    private val cardView = WView(context)
    private val rowView = WView(context)
    private val iconView = WCustomImageView(context)
    private val topLeftLabel = WLabel(context).apply {
        setStyle(16f, WFont.Medium)
        setSingleLine()
        ellipsize = TextUtils.TruncateAt.END
    }
    private val leverageLabel = WLabel(context).apply {
        setStyle(11f, WFont.Medium)
        setPadding(4.dp, 0, 4.dp, 0)
        gravity = Gravity.CENTER_VERTICAL
        setSingleLine()
    }
    private val bottomLeftLabel = WLabel(context).apply {
        setStyle(14f)
        setSingleLine()
    }
    private val topRightLabel = WLabel(context).apply {
        setStyle(16f)
        setSingleLine()
    }
    private val bottomRightLabel = WLabel(context).apply {
        setStyle(14f)
        setSingleLine()
    }

    init {
        rowView.background = ripple
        rowView.addView(iconView, LayoutParams(44.dp, 44.dp))
        rowView.addView(topLeftLabel, LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        rowView.addView(leverageLabel, LayoutParams(WRAP_CONTENT, 16.dp))
        rowView.addView(bottomLeftLabel, LayoutParams(0, WRAP_CONTENT))
        rowView.addView(topRightLabel, LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        rowView.addView(bottomRightLabel, LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        rowView.setConstraints {
            // Icon View
            toStart(iconView, 12f)
            toTop(iconView, 8f)
            // Top Row
            startToEnd(topLeftLabel, iconView, 12f)
            toTop(topLeftLabel, 9f)
            startToEnd(leverageLabel, topLeftLabel, 4f)
            centerYToCenterY(leverageLabel, topLeftLabel)
            toEnd(topRightLabel, 16f)
            toTop(topRightLabel, 9f)
            // Bottom Row
            startToStart(bottomLeftLabel, topLeftLabel)
            endToStart(bottomLeftLabel, bottomRightLabel, 8f)
            toBottom(bottomLeftLabel, ROW_VERTICAL_MARGIN)
            toEnd(bottomRightLabel, 16f)
            toBottom(bottomRightLabel, ROW_VERTICAL_MARGIN)
        }
        rowView.setOnClickListener { market?.let(onTap) }

        cardView.addView(rowView, LayoutParams(MATCH_PARENT, ROW_HEIGHT.dp))
        cardView.setConstraints {
            allEdges(rowView)
        }
        addView(cardView, LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        setConstraints {
            allEdges(cardView)
        }
    }

    fun configure(market: MApiPerpsListedAsset, isFirst: Boolean, isLast: Boolean) {
        this.market = market
        this.isFirst = isFirst
        this.isLast = isLast
        configureCard(isLast)
        rowView.updateLayoutParams { height = (if (isLast) LAST_ROW_HEIGHT else ROW_HEIGHT).dp }
        val bottomMargin = if (isLast) LAST_ROW_BOTTOM_MARGIN else ROW_VERTICAL_MARGIN
        rowView.setConstraints {
            toBottom(bottomLeftLabel, bottomMargin)
            toBottom(bottomRightLabel, bottomMargin)
        }
        market.image?.let { iconView.set(Content.ofUrl(it, market.isRwaStock)) }
            ?: iconView.clear()
        topLeftLabel.text = market.symbol
        leverageLabel.text = "${market.maxLeverage}x"
        val volume = formatCompactNumber(market.volume24h)
        bottomLeftLabel.text = "${LocaleController.getString("24h Volume")} \$$volume"
        topRightLabel.text = market.markPrice?.toPriceString() ?: EMPTY_VALUE
        val change = market.change24h
        bottomRightLabel.text = change?.let {
            "${if (it < 0) "-" else "+"}${abs(it).toPercentString(shouldUseLatinDigits = true)}"
        } ?: EMPTY_VALUE
        updateTheme()
    }

    override fun updateTheme() {
        cardView.setPositionsCardBackground(isFirst, isLast)
        ripple.backgroundColor = Color.TRANSPARENT
        ripple.rippleColor = WColor.BackgroundRipple.color
        topLeftLabel.setTextColor(WColor.PrimaryText.color)
        leverageLabel.setTextColor(WColor.SecondaryText.color)
        leverageLabel.setBackgroundColor(WColor.SecondaryText.color.colorWithAlpha(26), 4f.dp)
        bottomLeftLabel.setTextColor(WColor.SecondaryText.color)
        topRightLabel.setTextColor(WColor.PrimaryText.color)
        bottomRightLabel.setTextColor(
            market?.change24h?.let(::pnlColor) ?: WColor.SecondaryText.color
        )
    }

    private companion object {
        const val ROW_HEIGHT = 60
        const val LAST_ROW_HEIGHT = 58
        const val ROW_VERTICAL_MARGIN = 9f
        const val LAST_ROW_BOTTOM_MARGIN = 7f
        const val EMPTY_VALUE = "—"
    }
}
