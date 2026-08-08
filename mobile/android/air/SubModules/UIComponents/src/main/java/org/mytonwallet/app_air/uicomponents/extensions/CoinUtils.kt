package org.mytonwallet.app_air.uicomponents.extensions

import java.math.BigDecimal
import java.math.BigInteger
import org.mytonwallet.app_air.walletcontext.utils.CoinUtils
import org.mytonwallet.app_air.walletcore.moshi.IApiToken

fun CoinUtils.toBigInteger(value: String?, token: IApiToken?): BigInteger? = token?.let {
    fromDecimal(value, it.decimals)
}

fun CoinUtils.toBigDecimal(value: String?, token: IApiToken?): BigDecimal? = token?.let {
    fromDecimal(value, it.decimals)?.toBigDecimal(it.decimals)
}
