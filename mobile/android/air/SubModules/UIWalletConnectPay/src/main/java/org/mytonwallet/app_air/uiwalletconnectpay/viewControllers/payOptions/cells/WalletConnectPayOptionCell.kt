package org.mytonwallet.app_air.uiwalletconnectpay.viewControllers.payOptions.cells

import android.annotation.SuppressLint
import android.content.Context
import android.text.TextUtils
import android.view.Gravity
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.adaptiveFontSize
import org.mytonwallet.app_air.uicomponents.image.Content
import org.mytonwallet.app_air.uicomponents.image.WCustomImageView
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.smartDecimalsCount
import org.mytonwallet.app_air.walletbasecontext.utils.toString
import org.mytonwallet.app_air.walletcontext.utils.CoinUtils
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.models.MToken
import org.mytonwallet.app_air.walletcore.models.blockchain.MBlockchain
import org.mytonwallet.app_air.walletcore.moshi.WcPayPaymentOption
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import org.mytonwallet.app_air.walletcore.stores.BalanceStore
import org.mytonwallet.app_air.walletcore.stores.TokenStore
import java.math.BigInteger

@SuppressLint("ViewConstructor")
class WalletConnectPayOptionCell(context: Context) : WCell(context), WThemedView {

    private val iconView = WCustomImageView(context).apply {
        defaultRounding = Content.Rounding.Round
        defaultPlaceholder = Content.Placeholder.Color(WColor.Background)
        chainSize = 18.dp
        chainSizeGap = 2f.dp
    }

    private val topLeftLabel = WLabel(context).apply {
        setStyle(adaptiveFontSize(), WFont.Medium)
        setSingleLine()
        ellipsize = TextUtils.TruncateAt.END
    }

    private val bottomLeftLabel = WLabel(context).apply {
        setStyle(13f)
        setSingleLine()
        ellipsize = TextUtils.TruncateAt.END
    }

    private val topRightLabel = WLabel(context).apply {
        setStyle(adaptiveFontSize())
        gravity = Gravity.END
    }

    private val bottomRightLabel = WLabel(context).apply {
        setStyle(13f)
        gravity = Gravity.END
        layoutDirection = LAYOUT_DIRECTION_LTR
    }

    var onTap: ((option: WcPayPaymentOption) -> Unit)? = null

    init {
        layoutParams.apply { height = 60.dp }
        addView(iconView, LayoutParams(46.dp, 46.dp))
        addView(topLeftLabel, LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        addView(bottomLeftLabel, LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        addView(topRightLabel, LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        addView(bottomRightLabel, LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        setConstraints {
            toCenterY(iconView)
            toStart(iconView, 12f)
            // Top row
            toTop(topLeftLabel, 9f)
            startToEnd(topLeftLabel, iconView, 10f)
            endToStart(topLeftLabel, topRightLabel, 8f)
            constrainedWidth(topLeftLabel.id, true)
            setHorizontalBias(topLeftLabel.id, 0f)
            toTop(topRightLabel, 9f)
            toEnd(topRightLabel, 16f)
            // Bottom row
            toBottom(bottomLeftLabel, 10f)
            startToEnd(bottomLeftLabel, iconView, 10f)
            endToStart(bottomLeftLabel, bottomRightLabel, 8f)
            constrainedWidth(bottomLeftLabel.id, true)
            setHorizontalBias(bottomLeftLabel.id, 0f)
            toBottom(bottomRightLabel, 10f)
            toEnd(bottomRightLabel, 16f)
        }
        setOnClickListener {
            option?.let { onTap?.invoke(it) }
        }
    }

    override fun updateTheme() {
        setBackgroundColor(
            WColor.Background.color,
            0f,
            if (isLast) ViewConstants.BLOCK_RADIUS.dp else 0f
        )
        addRippleEffect(
            WColor.SecondaryBackground.color,
            0f,
            if (isLast) ViewConstants.BLOCK_RADIUS.dp else 0f
        )
        topLeftLabel.setTextColor(WColor.PrimaryText.color)
        bottomLeftLabel.setTextColor(WColor.SecondaryText.color)
        topRightLabel.setTextColor(WColor.PrimaryText.color)
        bottomRightLabel.setTextColor(WColor.SecondaryText.color)
    }

    private var option: WcPayPaymentOption? = null
    private var isLast = false

    fun configure(option: WcPayPaymentOption, isLast: Boolean) {
        this.option = option
        this.isLast = isLast
        updateTheme()

        val display = option.display
        val token = option.slug?.let { TokenStore.getToken(it) }
        if (token != null) {
            iconView.set(Content.of(token, showChain = true))
        } else {
            iconView.set(
                Content(
                    image = Content.Image.Res(MBlockchain.ton.icon),
                    subImageRes = 0
                )
            )
        }

        topLeftLabel.text = token?.name
        topRightLabel.text = formatAmount(option.amountValue, display.decimals, display.assetSymbol)
        bottomLeftLabel.text = availableText(token)
        bottomRightLabel.text = baseCurrencyEquivalent(option, token)
    }

    // Bottom-left: the active wallet's available balance for the matched token.
    private fun availableText(token: MToken?): String? {
        token ?: return null
        val balance = BalanceStore.getBalances(AccountStore.activeAccountId)?.get(token.slug)
            ?: return null
        val formatted = balance.toString(
            decimals = token.decimals,
            currency = token.symbol,
            currencyDecimals = balance.smartDecimalsCount(token.decimals),
            showPositiveSign = false,
        )
        return LocaleController.getStringWithKeyValues(
            "\$available_balance",
            listOf("%balance%" to formatted)
        )
    }

    // Bottom-right: fiat value of the option amount in the user's base currency.
    private fun baseCurrencyEquivalent(option: WcPayPaymentOption, token: MToken?): String? {
        val price = token?.price ?: return null
        return try {
            val amount = CoinUtils.toBigDecimal(
                BigInteger(option.amountValue), option.display.decimals
            ).toDouble()
            (amount * price).toString(
                9,
                WalletCore.baseCurrency.sign,
                WalletCore.baseCurrency.decimalsCount,
                smartDecimals = true,
            )?.let { "≈ $it" }
        } catch (_: Throwable) {
            null
        }
    }

    private fun formatAmount(value: String, decimals: Int, symbol: String): String {
        return try {
            val amount = BigInteger(value)
            amount.toString(
                decimals = decimals,
                currency = symbol,
                currencyDecimals = amount.smartDecimalsCount(decimals),
                showPositiveSign = false,
            )
        } catch (_: Throwable) {
            "$value $symbol"
        }
    }
}
