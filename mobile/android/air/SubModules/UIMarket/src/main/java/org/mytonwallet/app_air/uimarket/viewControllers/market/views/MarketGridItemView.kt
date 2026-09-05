package org.mytonwallet.app_air.uimarket.viewControllers.market.views

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Color
import android.text.TextUtils
import android.view.Gravity
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import org.mytonwallet.app_air.uicomponents.drawable.WRippleDrawable
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.image.Content
import org.mytonwallet.app_air.uicomponents.image.WCustomImageView
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uimarket.viewControllers.market.MarketToken
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color

@SuppressLint("ViewConstructor")
class MarketGridItemView(context: Context, private val onTap: (MarketToken) -> Unit) :
    WView(context),
    WThemedView {
    private val ripple = WRippleDrawable.create(16f.dp)
    private val iconView = WCustomImageView(context).apply {
        chainSize = 22.dp
    }
    private val nameLabel = WLabel(context).apply {
        setStyle(13f, WFont.Medium)
        translationY = 1f.dp
        setSingleLine()
        ellipsize = TextUtils.TruncateAt.END
        gravity = Gravity.CENTER
    }
    private val changeLabel = WLabel(context).apply {
        setStyle(13f, WFont.Regular)
        setSingleLine()
        gravity = Gravity.CENTER
    }
    private var marketToken: MarketToken? = null

    init {
        background = ripple
        addView(iconView, LayoutParams(60.dp, 60.dp))
        addView(nameLabel, LayoutParams(0, WRAP_CONTENT))
        addView(changeLabel, LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        setConstraints {
            toTop(iconView, 8f)
            toCenterX(iconView)
            topToBottom(nameLabel, iconView, 5f)
            toStart(nameLabel, 3f)
            toEnd(nameLabel, 3f)
            topToBottom(changeLabel, nameLabel)
            toCenterX(changeLabel)
        }
        isClickable = true
        setOnClickListener { marketToken?.let(onTap) }
        updateTheme()
    }

    fun configure(token: MarketToken) {
        marketToken = token
        iconView.set(Content.of(token.token, showChain = true))
        nameLabel.text = token.name
        changeLabel.text = token.changeText
        contentDescription = "${token.name}, ${token.changeText}"
        updateTheme()
    }

    override fun updateTheme() {
        ripple.backgroundColor = Color.TRANSPARENT
        ripple.rippleColor = WColor.BackgroundRipple.color
        nameLabel.setTextColor(WColor.PrimaryText.color)
        marketToken?.let {
            changeLabel.setTextColor(if (it.isPositive) WColor.Green.color else WColor.Red.color)
        }
    }
}
