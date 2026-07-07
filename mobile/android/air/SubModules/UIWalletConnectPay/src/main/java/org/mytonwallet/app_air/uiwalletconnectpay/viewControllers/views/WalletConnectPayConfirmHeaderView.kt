package org.mytonwallet.app_air.uiwalletconnectpay.viewControllers.views

import android.annotation.SuppressLint
import android.content.Context
import android.text.TextUtils
import android.view.Gravity
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.LinearLayout
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.typeface
import org.mytonwallet.app_air.uicomponents.image.Content
import org.mytonwallet.app_air.uicomponents.image.WCustomImageView
import org.mytonwallet.app_air.uicomponents.widgets.AutoScaleContainerView
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.balance.WBalanceView
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcore.models.MToken
import org.mytonwallet.app_air.walletcore.moshi.WcPayMerchant
import java.math.BigInteger

@SuppressLint("ViewConstructor")
class WalletConnectPayConfirmHeaderView(
    context: Context,
    merchant: WcPayMerchant,
    token: MToken? = null,
    amount: Amount? = null,
) : WView(context), WThemedView {

    data class Amount(
        val value: BigInteger,
        val decimals: Int,
        val currency: String,
        val forceCurrencyToRight: Boolean = true,
    )

    companion object {
        private const val ICON_SIZE = 80
        private const val SUBTITLE_ICON_SIZE = 18
    }

    private val iconView = WCustomImageView(context).apply {
        id = generateViewId()
        defaultRounding =
            if (token != null) Content.Rounding.Round else Content.Rounding.Radius(20f.dp)
        defaultPlaceholder = Content.Placeholder.Color(WColor.Background)
        chainSize = 28.dp
        chainSizeGap = 2f.dp
        set(
            token?.let { Content.of(it, showChain = true) }
                ?: Content.ofUrl(merchant.iconUrl ?: "")
        )
    }

    private val hasAmount = amount != null

    private val amountLabel = WBalanceView(context).apply {
        primarySize = 36f
        decimalsSize = 28f
        currencySize = 32f
        typeface = WFont.Medium.typeface
        defaultHeight = 40.dp
        if (amount != null) {
            animateText(
                WBalanceView.AnimateConfig(
                    amount = amount.value,
                    decimals = amount.decimals,
                    currency = amount.currency,
                    animated = false,
                    setInstantly = true,
                    forceCurrencyToRight = amount.forceCurrencyToRight
                )
            )
        }
    }

    private val amountContainer = AutoScaleContainerView(amountLabel).apply {
        id = generateViewId()
        clipChildren = false
        clipToPadding = false
        minPadding = 16.dp
        visibility = if (hasAmount) VISIBLE else GONE
    }

    private val subtitlePrefixLabel = WLabel(context).apply {
        setStyle(17f, WFont.Medium)
        gravity = Gravity.CENTER
        maxLines = 1
        ellipsize = TextUtils.TruncateAt.END
        text = LocaleController.getString("Send to")
    }

    private val subtitleIconView = WCustomImageView(context).apply {
        defaultRounding = Content.Rounding.Radius(4f.dp)
        defaultPlaceholder = Content.Placeholder.Color(WColor.SecondaryBackground)
        chainSize = 0
        set(Content.ofUrl(merchant.iconUrl ?: ""))
    }

    private val subtitleLabel = WLabel(context).apply {
        setStyle(17f, WFont.Medium)
        gravity = Gravity.CENTER
        maxLines = 1
        ellipsize = TextUtils.TruncateAt.END
        text = merchant.name
    }

    private val subtitleRow = LinearLayout(context).apply {
        id = generateViewId()
        orientation = LinearLayout.HORIZONTAL
        gravity = Gravity.CENTER
        clipChildren = false
        addView(
            subtitlePrefixLabel,
            LinearLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT).apply {
                marginEnd = 4.dp
            }
        )
        addView(
            subtitleIconView,
            LinearLayout.LayoutParams(SUBTITLE_ICON_SIZE.dp, SUBTITLE_ICON_SIZE.dp).apply {
                marginEnd = 4.dp
            }
        )
        addView(subtitleLabel, LinearLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
    }

    init {
        clipChildren = false
        addView(iconView, LayoutParams(ICON_SIZE.dp, ICON_SIZE.dp))
        addView(amountContainer, LayoutParams(0, WRAP_CONTENT))
        addView(subtitleRow, LayoutParams(0, WRAP_CONTENT))
        setConstraints {
            toTop(iconView, 24f)
            toCenterX(iconView)
            val anchor = if (hasAmount) amountContainer else iconView
            if (hasAmount) {
                topToBottom(amountContainer, iconView, 28f)
                toCenterX(amountContainer, 8f)
            }
            topToBottom(subtitleRow, anchor, if (hasAmount) 10f else 30f)
            toCenterX(subtitleRow, 8f)
            toBottom(subtitleRow, 24f)
            setVerticalBias(subtitleRow.id, 0f)
        }
        updateTheme()
    }

    override fun updateTheme() {
        amountLabel.currencyColor = WColor.SecondaryText.color
        amountLabel.updateColors(
            primaryColor = WColor.PrimaryText.color,
            secondaryColor = WColor.PrimaryText.color,
            drawGradient = false,
        )
        subtitlePrefixLabel.setTextColor(WColor.PrimaryText.color)
        subtitleLabel.setTextColor(WColor.SecondaryText.color)
    }
}
