package org.mytonwallet.app_air.walletbasecontext.utils

import org.mytonwallet.app_air.walletbasecontext.models.MBaseCurrency
import java.math.BigInteger

const val decimalSeparator = '.'

// Six-per-em space; the rounded balance font (Google Sans Flex) draws the thin space
// (U+2009) at just 0.06em, while U+2006 renders ~0.167em consistently in all fonts.
const val thinSpace = '\u2006'
const val signSpace = '\u200A'

fun max(a: BigInteger, b: BigInteger): BigInteger {
    return if (a > b) a else b
}

fun BigInteger.doubleAbsRepresentation(decimals: Int? = null): Double {
    val absValue = this.abs()
    var str = absValue.toString()
    // Number of decimals to ensure (default is 9)
    val decimalPlaces = decimals ?: 9
    // Ensure the string has enough digits
    while (str.length < decimalPlaces + 1) {
        str = "0$str"
    }
    // Insert the decimal point
    val integerPart = str.substring(0, str.length - decimalPlaces)
    val fractionalPart = str.substring(str.length - decimalPlaces)
    val formattedStr = "$integerPart.$fractionalPart"
    return formattedStr.toDouble()
}

// Format amount into string with separator
fun BigInteger.toString(
    decimals: Int,
    currency: String,
    currencyDecimals: Int,
    showPositiveSign: Boolean,
    forceCurrencyToRight: Boolean = false,
    roundUp: Boolean = true,
    zeroCountSubscriptMinCount: Int? = 6
): String {
    val scale = BigInteger.TEN.pow(decimals)
    val absValue = abs()
    var integerPart = absValue.divide(scale)
    var decimalPart = absValue.remainder(scale).toString().padStart(decimals, '0')

    // Handle rounding
    if (decimalPart.length > currencyDecimals) {
        val extraDigit = decimalPart[currencyDecimals].digitToInt()
        decimalPart = decimalPart.substring(0, currencyDecimals)

        if (roundUp && extraDigit >= 5) {
            val rounded = decimalPart.toBigInteger() + BigInteger.ONE
            decimalPart = rounded.toString().padStart(currencyDecimals, '0')
            if (decimalPart.length > currencyDecimals) {
                // If rounding causes overflow, adjust integer part
                decimalPart = ""
                integerPart += BigInteger.ONE
            }
        }
    }

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
            if (currency.length > 1 || forceCurrencyToRight || currency in MBaseCurrency.forcedToRight) {
                "$result $currency"
            } else {
                "$currency$result"
            }
    }

    if (showPositiveSign && !isNegative) {
        result = "+$signSpace$result"
    }

    return result
}

private val subscriptDigits =
    arrayOf('₀', '₁', '₂', '₃', '₄', '₅', '₆', '₇', '₈', '₉')

private fun Int.toSubscriptString(): String {
    return toString().map { subscriptDigits[it.digitToInt()] }.joinToString("")
}

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

fun BigInteger.smartDecimalsCount(tokenDecimals: Int): Int {
    if (tokenDecimals <= 2) {
        return tokenDecimals
    }
    val amount = this.abs()
    if (amount < BigInteger.valueOf(2)) {
        return tokenDecimals
    }
    if (amount >= BigInteger.valueOf(10).pow(tokenDecimals + 1)) {
        return 2.coerceAtLeast(1 + tokenDecimals - "$amount".count())
    }
    var newAmount = amount
    var multiplier = 0
    while (newAmount < BigInteger.valueOf(10).pow(tokenDecimals + 1)) {
        newAmount *= BigInteger.valueOf(10)
        multiplier += 1
    }
    return multiplier.coerceIn(2, tokenDecimals)
}
