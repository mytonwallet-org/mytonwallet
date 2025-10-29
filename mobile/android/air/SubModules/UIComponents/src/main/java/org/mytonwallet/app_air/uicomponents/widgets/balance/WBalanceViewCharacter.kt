package org.mytonwallet.app_air.uicomponents.widgets.balance

import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color

data class WBalanceViewCharacter(
    val char: Char,
    val size: Float,
    val overrideColor: Int?,

    val isDecimalPart: Boolean,
    val isBaseCurrency: Boolean,
    val left: Float,
) {
    val isDecimalOrBaseCurrency: Boolean
        get() {
            return isDecimalPart || isBaseCurrency
        }

    val color: Int
        get() {
            return overrideColor
                ?: if (isDecimalOrBaseCurrency) WColor.Decimals.color else WColor.PrimaryText.color
        }
}
