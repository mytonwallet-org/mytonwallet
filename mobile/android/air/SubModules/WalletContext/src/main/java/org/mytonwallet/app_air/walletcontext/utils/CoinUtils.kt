package org.mytonwallet.app_air.walletcontext.utils

import android.text.Spannable
import java.math.BigDecimal
import java.math.BigInteger
import java.math.RoundingMode

object CoinUtils {

    fun setSpanToFractionalPart(text: Spannable, relativeSizeSpan: Any) {
        text.removeSpan(relativeSizeSpan)
        var start = text.indexOf('.')
        if (start == -1) {
            start = text.lastIndexOf(' ')
        }

        if (start != -1) {
            text.setSpan(relativeSizeSpan, start, text.length, Spannable.SPAN_EXCLUSIVE_EXCLUSIVE)
        }
    }

    fun <T : Spannable> setSpanToSymbolPart(text: T, colorSpan: Any): T {
        text.removeSpan(colorSpan)
        val start = text.lastIndexOf(' ')
        if (start != -1) {
            text.setSpan(colorSpan, start, text.length, Spannable.SPAN_EXCLUSIVE_EXCLUSIVE)
        }
        return text
    }


    fun toDecimalString(value: BigInteger, decimals: Int): String {
        return value.toBigDecimal(decimals).stripTrailingZeros().toPlainString()
    }

    fun toDecimalString(value: BigDecimal, decimals: Int?, round: Boolean): String {
        return (
            if (decimals != null)
                value.setScale(
                    decimals,
                    if (round) RoundingMode.HALF_UP else RoundingMode.FLOOR
                )
            else
                value
            ).stripTrailingZeros().toPlainString()
    }

    fun toDecimalString(value: String?, decimals: Int?): String? {
        if (value == null || decimals == null) {
            return value;
        }
        return toDecimalString(BigInteger(value), decimals)
    }

    fun toBigDecimal(value: BigInteger, decimals: Int): BigDecimal {
        return value.toBigDecimal(decimals)
    }

    fun fromDecimal(value: BigDecimal?, decimals: Int): BigInteger? {
        val v = value ?: return null

        return try {
            v.movePointRight(decimals).toBigInteger()
        } catch (t: ArithmeticException) {
            null
        }
    }

    fun fromDecimal(value: String?, decimals: Int): BigInteger? {
        val v = value ?: return null

        return try {
            BigDecimal(v).movePointRight(decimals).toBigInteger()
        } catch (t: NumberFormatException) {
            null
        } catch (t: ArithmeticException) {
            null
        }
    }
}
