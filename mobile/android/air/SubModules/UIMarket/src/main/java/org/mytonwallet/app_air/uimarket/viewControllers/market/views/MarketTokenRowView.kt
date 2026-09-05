package org.mytonwallet.app_air.uimarket.viewControllers.market.views

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Color
import android.text.TextUtils
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import androidx.core.view.isGone
import org.mytonwallet.app_air.uicomponents.drawable.WRippleDrawable
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.image.Content
import org.mytonwallet.app_air.uicomponents.image.WCustomImageView
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.uimarket.viewControllers.market.MarketToken
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcontext.utils.colorWithAlpha

@SuppressLint("ViewConstructor")
class MarketTokenRowView(context: Context, private val onTap: (MarketToken) -> Unit) :
    WView(context),
    WThemedView {
    private val ripple = WRippleDrawable.create(0f)
    private val lastItemRipple = WRippleDrawable.create(
        0f,
        0f,
        ViewConstants.BLOCK_RADIUS.dp,
        ViewConstants.BLOCK_RADIUS.dp
    )
    private val iconView = WCustomImageView(context)
    private val symbolLabel = WLabel(context).apply {
        setStyle(16f, WFont.Medium)
        setSingleLine()
        ellipsize = TextUtils.TruncateAt.END
    }
    private val badgeLabel = WLabel(context).apply {
        setStyle(11f, WFont.Medium)
        setPadding(4.dp, 1.dp, 4.dp, 1.dp)
        setSingleLine()
    }
    private val subtitleLabel = MarketPriceChangeLabel(context).apply {
        ellipsize = TextUtils.TruncateAt.END
    }
    private var marketToken: MarketToken? = null

    init {
        background = ripple
        addView(iconView, LayoutParams(44.dp, 44.dp))
        addView(symbolLabel, LayoutParams(0, WRAP_CONTENT))
        addView(badgeLabel, LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        addView(subtitleLabel, LayoutParams(0, WRAP_CONTENT))
        setConstraints {
            toStart(iconView, 16f)
            toTop(iconView, 10f)
            startToEnd(symbolLabel, iconView, 12f)
            toTop(symbolLabel, 11f)
            startToEnd(badgeLabel, symbolLabel, 7f)
            centerYToCenterY(badgeLabel, symbolLabel)
            toEnd(badgeLabel, 12f)
            setHorizontalBias(badgeLabel.id, 0f)
            constrainedWidth(symbolLabel.id, true)
            setHorizontalBias(symbolLabel.id, 0f)
            startToStart(subtitleLabel, symbolLabel)
            toBottom(subtitleLabel, 12f)
            toEnd(subtitleLabel, 12f)
            constrainedWidth(subtitleLabel.id, true)
            setHorizontalBias(subtitleLabel.id, 0f)
        }
        isClickable = true
        setOnClickListener { marketToken?.let(onTap) }
        updateTheme()
    }

    fun configure(token: MarketToken, isLastInSection: Boolean = false) {
        marketToken = token
        background = if (isLastInSection) lastItemRipple else ripple
        iconView.set(Content.of(token.token, showChain = true))
        symbolLabel.text = token.symbol
        badgeLabel.text = token.token.label
        badgeLabel.isGone = token.token.label.isNullOrBlank()
        subtitleLabel.configure(token)
        setConstraints {
            toBottom(subtitleLabel, if (isLastInSection) 18f else 12f)
        }
        contentDescription = listOfNotNull(
            token.symbol,
            token.name.takeIf { it != token.symbol },
            token.priceText,
            token.changeText
        ).joinToString(", ")
        updateTheme()
    }

    override fun updateTheme() {
        ripple.backgroundColor = Color.TRANSPARENT
        ripple.rippleColor = WColor.BackgroundRipple.color
        lastItemRipple.backgroundColor = Color.TRANSPARENT
        lastItemRipple.rippleColor = WColor.BackgroundRipple.color
        symbolLabel.setTextColor(WColor.PrimaryText.color)
        badgeLabel.setTextColor(WColor.StockBadge.color)
        badgeLabel.setBackgroundColor(WColor.StockBadge.color.colorWithAlpha(34), 100f.dp)
        subtitleLabel.updateTheme()
    }
}
