package org.mytonwallet.app_air.walletbasecontext.utils

import java.math.BigDecimal
import java.math.BigInteger
import java.math.RoundingMode
import kotlin.math.abs
import org.mytonwallet.app_air.walletbasecontext.models.MBaseCurrency

@Suppress("PropertyName")
const val decimalSeparator = '.'

// Six-per-em space; the rounded balance font (Google Sans Flex) draws the thin space
// (U+2009) at just 0.06em, while U+2006 renders ~0.167em consistently in all fonts.
@Suppress("PropertyName")
const val thinSpace = '\u2006'

@Suppress("PropertyName")
const val signSpace = '\u200A'

fun max(a: BigInteger, b: BigInteger): BigInteger = if (a > b) a else b

private val exactPowersOfTen = DoubleArray(23).also {
    it[0] = 1.0
    for (i in 1 until it.size) it[i] = it[i - 1] * 10
}

private val BIG_POWERS_OF_TEN = Array(20) { BigInteger.TEN.pow(it) }

private fun getPowerOfTen(exponent: Int): BigInteger =
    BIG_POWERS_OF_TEN.getOrElse(exponent) { BigInteger.TEN.pow(it) }

fun BigInteger.doubleAbsRepresentation(decimals: Int? = null): Double {
    val scale = decimals ?: 9
    // An integer below 2^53 and 10^scale up to 10^22 are exact doubles, so their quotient is rounded
    // once, exactly like parsing the decimal string.
    if (bitLength() <= 53 && scale in exactPowersOfTen.indices) {
        return abs(toLong()).toDouble() / exactPowersOfTen[scale]
    }
    return BigDecimal(this.abs(), scale).toPlainString().toDouble()
}

// Format amount into string with separator
fun BigInteger.toString(
    decimals: Int,
    currency: String,
    currencyDecimals: Int,
    showPositiveSign: Boolean,
    forceCurrencyToRight: Boolean = false,
    rounding: RoundingMode = RoundingMode.HALF_UP,
    localizedDigits: Boolean = false,
    zeroCountSubscriptMinCount: Int? = 6
): String {
    val shownDecimals = minOf(decimals, currencyDecimals)
    val absValue = if (shownDecimals == decimals) {
        abs()
    } else {
        BigDecimal(abs(), decimals).setScale(shownDecimals, rounding).unscaledValue()
    }
    val scale = getPowerOfTen(shownDecimals)
    val integerPart = absValue.divide(scale)
    val decimalPart = absValue.remainder(scale).toString().padStart(shownDecimals, '0')

    // Build result string
    val sb = StringBuilder(integerPart.toString())
    if (decimalPart.isNotEmpty()) {
        sb.append(decimalSeparator).append(decimalPart)
    }

    // Remove trailing zeros after rounding
    if (decimalSeparator in sb) {
        var i = sb.length - 1
        while (i >= 0 && sb[i] == '0') i--
        if (sb[i] == decimalSeparator) i--
        sb.setLength(i + 1)
    }

    var result = sb.toString()
        .applyZeroCountSubscript(zeroCountSubscriptMinCount)
        .insertGroupingSeparator()

    // Add sign
    val isNegative = this < BigInteger.ZERO
    if (isNegative) {
        result = "-$signSpace$result"
    }

    // Add currency symbol
    if (currency.isNotEmpty()) {
        result =
            if (currency.length > 1 || forceCurrencyToRight ||
                currency in MBaseCurrency.forcedToRight
            ) {
                "$result $currency"
            } else {
                "$currency$result"
            }
    }

    if (showPositiveSign && !isNegative) {
        result = "+$signSpace$result"
    }

    if (localizedDigits) {
        result = result.withLocalizedNumbers
    }

    return result
}

private val subscriptDigits =
    arrayOf('₀', '₁', '₂', '₃', '₄', '₅', '₆', '₇', '₈', '₉')

private fun Int.toSubscriptString(): String = toString().map {
    subscriptDigits[it.digitToInt()]
}.joinToString("")

// Collapse leading fractional zeros into a subscript count, e.g. "0.00000056" -> "0.0₆56".
// Only applies when the value starts with "0." and has at least [minZeroCount] leading zeros.
private fun String.applyZeroCountSubscript(minZeroCount: Int?): String {
    if (minZeroCount == null || minZeroCount <= 0 || !startsWith("0$decimalSeparator")) {
        return this
    }

    var zeroCount = 0
    var index = 2
    while (index < length && this[index] == '0') {
        zeroCount++
        index++
    }

    if (zeroCount < minZeroCount || index >= length) {
        return this
    }

    return "0${decimalSeparator}0${zeroCount.toSubscriptString()}${substring(index)}"
}

fun BigInteger.smartDecimalsCount(tokenDecimals: Int, preferredPrecision: Int? = null): Int {
    val minDigits = preferredPrecision ?: 2
    if (minDigits == 0) {
        return 0
    }
    if (tokenDecimals <= minDigits) {
        return tokenDecimals
    }
    val amount = this.abs()
    if (amount < BigInteger.valueOf(2)) {
        return tokenDecimals
    }
    val limit = getPowerOfTen(tokenDecimals + 1)
    if (amount >= limit) {
        return minDigits.coerceAtLeast(1 + tokenDecimals - "$amount".count())
    }
    var newAmount = amount
    var multiplier = 0
    while (newAmount < limit) {
        newAmount *= BigInteger.TEN
        multiplier += 1
    }
    return multiplier.coerceIn(minDigits, tokenDecimals)
}
