package org.mytonwallet.app_air.uicomponents.widgets

import android.content.Context
import android.util.TypedValue
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.typeface
import org.mytonwallet.app_air.uicomponents.widgets.htextview.htextview.scale.ScaleTextView
import org.mytonwallet.app_air.walletcontext.utils.smartDecimalsCount
import org.mytonwallet.app_air.walletcontext.utils.toString
import java.math.BigInteger

open class WAnimatedLabel(context: Context) : ScaleTextView(context), WThemedView {
    init {
        id = generateViewId()
    }

    fun setStyle(size: Float, font: WFont? = null) {
        typeface = (font ?: WFont.Regular).typeface
        setTextSize(TypedValue.COMPLEX_UNIT_SP, size)
    }

    fun setAmount(
        amount: BigInteger,
        decimals: Int,
        currency: String,
        currencyDecimals: Int,
        smartDecimals: Boolean,
        showPositiveSign: Boolean = false,
        forceCurrencyToRight: Boolean
    ) {
        animateText(
            amount.toString(
                decimals = decimals,
                currency = currency,
                currencyDecimals = if (smartDecimals) amount.smartDecimalsCount(currencyDecimals) else currencyDecimals,
                showPositiveSign = showPositiveSign,
                forceCurrencyToRight = forceCurrencyToRight
            )
        )
    }

    fun setAmount(
        amount: Double,
        decimals: Int,
        currency: String,
        currencyDecimals: Int,
        smartDecimals: Boolean,
        forceCurrencyToRight: Boolean,
    ) {
        animateText(
            amount.toString(
                decimals = decimals,
                currency = currency,
                currencyDecimals = currencyDecimals,
                smartDecimals = smartDecimals,
                forceCurrencyToRight = forceCurrencyToRight
            )
        )
    }

    override fun updateTheme() {
        // To force change color on theme change
        animateText(text)
    }
}
