package org.mytonwallet.app_air.uicomponents.extensions

import org.mytonwallet.app_air.walletcontext.utils.CoinUtils
import org.mytonwallet.app_air.walletcore.moshi.IApiToken
import java.math.BigDecimal
import java.math.BigInteger

fun CoinUtils.toBigInteger(value: String?, token: IApiToken?): BigInteger? {
    return token?.let {
        fromDecimal(value, it.decimals)
    }
}

fun CoinUtils.toBigDecimal(value: String?, token: IApiToken?): BigDecimal? {
    return token?.let {
        fromDecimal(value, it.decimals)?.toBigDecimal(it.decimals)
    }
}
