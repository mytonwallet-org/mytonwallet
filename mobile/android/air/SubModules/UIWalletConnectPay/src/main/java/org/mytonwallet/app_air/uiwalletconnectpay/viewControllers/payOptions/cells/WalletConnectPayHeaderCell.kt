package org.mytonwallet.app_air.uiwalletconnectpay.viewControllers.payOptions.cells

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.RenderEffect
import android.graphics.Shader
import android.os.Build
import android.view.Gravity
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.LinearLayout
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.typeface
import org.mytonwallet.app_air.uicomponents.image.Content
import org.mytonwallet.app_air.uicomponents.image.WCustomImageView
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.balance.WBalanceView
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletbasecontext.models.MBaseCurrency
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.toString
import org.mytonwallet.app_air.walletcontext.utils.CoinUtils
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.moshi.WcPayAmount
import org.mytonwallet.app_air.walletcore.moshi.WcPayMerchant
import org.mytonwallet.app_air.walletcore.stores.TokenStore
import java.math.BigInteger

@SuppressLint("ViewConstructor")
class WalletConnectPayHeaderCell(context: Context) :
    WCell(
        context,
        ViewGroup.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            FrameLayout.LayoutParams.WRAP_CONTENT
        )
    ), WThemedView {

    private val merchantIconView = WCustomImageView(context).apply {
        defaultRounding = Content.Rounding.Radius(20f.dp)
        defaultPlaceholder = Content.Placeholder.Color(WColor.Background)
    }

    private val merchantGlowView = WCustomImageView(context).apply {
        defaultRounding = Content.Rounding.Radius(25f.dp)
        alpha = 0.5f
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            setRenderEffect(
                RenderEffect.createBlurEffect(20f.dp, 20f.dp, Shader.TileMode.DECAL)
            )
        }
    }

    private val merchantIconContainer = FrameLayout(context).apply {
        clipChildren = false
        clipToPadding = false
        addView(
            merchantGlowView,
            FrameLayout.LayoutParams(92.dp, 92.dp, Gravity.CENTER)
        )
        addView(
            merchantIconView,
            FrameLayout.LayoutParams(80.dp, 80.dp, Gravity.CENTER)
        )
    }

    private val amountValueLabel = WBalanceView(context).apply {
        primarySize = 36f
        decimalsSize = 28f
        currencySize = 32f
        typeface = WFont.Medium.typeface
        defaultHeight = 40.dp
    }

    private val equivalentLabel = WLabel(context).apply {
        setStyle(16f, WFont.Regular)
        gravity = Gravity.CENTER
        layoutDirection = LAYOUT_DIRECTION_LTR
    }

    private val container = LinearLayout(context).apply {
        id = generateViewId()
        orientation = LinearLayout.VERTICAL
        clipChildren = false
        clipToPadding = false
        setPadding(0, 8.dp, 0, 25.dp)
        addView(
            merchantIconContainer, LinearLayout.LayoutParams(112.dp, 112.dp).apply {
                gravity = Gravity.CENTER_HORIZONTAL
            }
        )
        addView(
            amountValueLabel, LinearLayout.LayoutParams(
                LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT
            ).apply {
                gravity = Gravity.CENTER_HORIZONTAL
                topMargin = 12.dp
            }
        )
        addView(
            equivalentLabel, LinearLayout.LayoutParams(
                LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT
            ).apply {
                topMargin = 9.dp
            }
        )
    }

    init {
        addView(container, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT))
        setConstraints {
            toTop(container)
            toCenterX(container)
            toBottom(container, ViewConstants.GAP.toFloat())
        }
    }

    override fun updateTheme() {
        amountValueLabel.currencyColor = WColor.SecondaryText.color
        amountValueLabel.updateColors(
            primaryColor = WColor.PrimaryText.color,
            secondaryColor = WColor.PrimaryText.color,
            drawGradient = false,
        )
        equivalentLabel.setTextColor(WColor.SecondaryText.color)
    }

    fun configure(merchant: WcPayMerchant, amount: WcPayAmount?) {
        updateTheme()

        val merchantContent = Content.ofUrl(merchant.iconUrl ?: "")
        merchantIconView.set(merchantContent)
        merchantGlowView.set(merchantContent)

        if (amount == null) {
            amountValueLabel.visibility = GONE
            equivalentLabel.visibility = GONE
            return
        }
        amountValueLabel.visibility = VISIBLE

        val fiatCurrency = amount.fiatCurrency
        val value = runCatching { BigInteger(amount.value) }.getOrNull()
        if (value == null) {
            amountValueLabel.visibility = GONE
            equivalentLabel.visibility = GONE
            return
        }
        if (fiatCurrency != null) {
            amountValueLabel.animateText(
                WBalanceView.AnimateConfig(
                    amount = value,
                    decimals = amount.display.decimals,
                    currency = fiatCurrency.sign,
                    animated = false,
                    setInstantly = true,
                    forceCurrencyToRight = false
                )
            )
            val equivalent = baseCurrencyEquivalent(amount, fiatCurrency)
            if (equivalent != null) {
                equivalentLabel.text = equivalent
                equivalentLabel.visibility = VISIBLE
            } else {
                equivalentLabel.visibility = GONE
            }
        } else {
            amountValueLabel.animateText(
                WBalanceView.AnimateConfig(
                    amount = value,
                    decimals = amount.display.decimals,
                    currency = amount.display.assetSymbol,
                    animated = false,
                    setInstantly = true,
                    forceCurrencyToRight = true
                )
            )
            equivalentLabel.visibility = GONE
        }
    }

    private fun baseCurrencyEquivalent(
        amount: WcPayAmount,
        fiatCurrency: MBaseCurrency
    ): String? {
        val baseCurrency = WalletCore.baseCurrency
        if (baseCurrency == fiatCurrency) return null
        val rates = TokenStore.currencyRates ?: return null
        val baseRate = rates[baseCurrency.currencyCode] ?: return null

        return try {
            val originalValue =
                CoinUtils.toBigDecimal(BigInteger(amount.value), amount.display.decimals).toDouble()
            val amountInUsd = if (fiatCurrency == MBaseCurrency.USD) {
                originalValue
            } else {
                val fiatRate = rates[fiatCurrency.currencyCode] ?: return null
                originalValue / fiatRate
            }
            val valueInBaseCurrency = amountInUsd * baseRate
            valueInBaseCurrency.toString(
                9,
                baseCurrency.sign,
                baseCurrency.decimalsCount,
                smartDecimals = true,
            )?.let { "≈ $it" }
        } catch (_: Throwable) {
            null
        }
    }
}
