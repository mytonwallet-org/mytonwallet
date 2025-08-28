package org.mytonwallet.app_air.walletcontext.utils

import java.math.BigInteger

const val decimalSeparator = '.'

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
    roundUp: Boolean = true
): String {
    val scale = BigInteger.TEN.pow(decimals)
    var integerPart = this.abs().divide(scale)
    var decimalPart = this.abs().remainder(scale).toString().padStart(decimals, '0')

    if (decimalPart.length > currencyDecimals) {
        val extraDigit = decimalPart.getOrNull(currencyDecimals)?.digitToInt() ?: 0
        decimalPart = decimalPart.take(currencyDecimals)

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

    var result = integerPart.toString()
    if (decimalPart.isNotEmpty()) {
        result += "$decimalSeparator$decimalPart"
    }

    // Remove trailing zeros after rounding
    if (result.contains(decimalSeparator))
        while (result.endsWith("0")) {
            if (result.endsWith("${decimalSeparator}0")) {
                result = result.dropLast(2)
                break
            } else {
                result = result.dropLast(1)
            }
        }

    if (result.endsWith(decimalSeparator)) {
        result = result.dropLast(1)
    }

    result = result.insertGroupingSeparator()

    // Add negative sign if needed
    if (this < BigInteger.valueOf(0)) {
        result = "-$result"
    }

    // Add currency symbol
    if (currency.isNotEmpty()) {
        result = if (currency.length > 1 || forceCurrencyToRight) {
            "$result $currency"
        } else {
            "$currency$result"
        }
    }

    // Add positive sign if needed
    if (showPositiveSign && this >= BigInteger.valueOf(0)) {
        result = "+$result"
    }

    return result
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
