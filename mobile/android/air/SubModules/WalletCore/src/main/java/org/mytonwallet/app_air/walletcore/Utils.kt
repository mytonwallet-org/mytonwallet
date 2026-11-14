package org.mytonwallet.app_air.walletcore

import java.math.BigInteger
import java.math.RoundingMode
import org.mytonwallet.app_air.walletbasecontext.utils.smartDecimalsCount
import org.mytonwallet.app_air.walletbasecontext.utils.toString
import org.mytonwallet.app_air.walletcore.moshi.IApiToken

fun BigInteger.toAmountString(token: IApiToken): String = this.toString(
    currency = token.symbol ?: "",
    decimals = token.decimals,
    currencyDecimals = this.smartDecimalsCount(token.decimals, token.amountPrecision),
    showPositiveSign = false,
    rounding = RoundingMode.DOWN
)
