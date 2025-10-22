package org.mytonwallet.app_air.walletcore

import org.mytonwallet.app_air.walletbasecontext.utils.smartDecimalsCount
import org.mytonwallet.app_air.walletbasecontext.utils.toString
import org.mytonwallet.app_air.walletcore.moshi.IApiToken
import java.math.BigInteger

fun BigInteger.toAmountString(
    token: IApiToken
): String {
    return this.toString(
        currency = token.symbol ?: "",
        decimals = token.decimals,
        currencyDecimals = this.smartDecimalsCount(token.decimals),
        showPositiveSign = false,
        roundUp = false
    )
}
