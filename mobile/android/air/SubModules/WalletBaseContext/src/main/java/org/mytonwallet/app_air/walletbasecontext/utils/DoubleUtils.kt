package org.mytonwallet.app_air.walletbasecontext.utils

import java.math.BigDecimal
import java.math.BigInteger
import java.math.RoundingMode
import kotlin.math.abs

fun Double.toString(
    decimals: Int,
    currency: String,
    currencyDecimals: Int,
    smartDecimals: Boolean,
    showPositiveSign: Boolean = false,
    forceCurrencyToRight: Boolean = false,
    roundUp: Boolean = true
): String? {
    val bigInteger = toBigInteger(decimals)
    return bigInteger?.toString(
        decimals,
        currency,
        if (smartDecimals) bigInteger.smartDecimalsCount(decimals) else currencyDecimals,
        showPositiveSign,
        forceCurrencyToRight,
        roundUp
    )
}

fun Double.toBigInteger(digits: Int): BigInteger? {
    if (!isFinite()) return null

    val scaleFactor = BigDecimal.TEN.pow(digits)
    return BigDecimal.valueOf(this)
        .multiply(scaleFactor)
        .setScale(0, RoundingMode.FLOOR)
        .toBigInteger()
}

fun Double.smartDecimalsCount(tokenDecimals: Int): Int {
    if (tokenDecimals <= 2) {
        return tokenDecimals
    }
    val amount = abs(this)
    if (amount == 0.0) {
        return 0
    }
    if (amount >= 1) {
        return maxOf(2, 3 - amount.toInt().toString().length)
    }
    var newAmount = abs(amount)
    var multiplier = 0
    while (newAmount < 2) {
        newAmount *= 10
        multiplier += 1
    }
    return minOf(tokenDecimals, multiplier)
}
