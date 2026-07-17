package org.mytonwallet.app_air.walletbasecontext.utils

import org.junit.Assert.assertEquals
import org.junit.Test
import java.math.BigInteger

class BigIntegerUtilsTest {

    private fun format(
        value: BigInteger,
        decimals: Int = 9,
        currency: String = "",
        currencyDecimals: Int = 2,
        showPositiveSign: Boolean = false,
        forceCurrencyToRight: Boolean = false,
        roundUp: Boolean = true,
        zeroCountSubscriptMinCount: Int? = 6
    ) = value.toString(
        decimals,
        currency,
        currencyDecimals,
        showPositiveSign,
        forceCurrencyToRight,
        roundUp,
        zeroCountSubscriptMinCount
    )

    @Test
    fun formatsWholeAndFractionalParts() {
        assertEquals("1.5", format(BigInteger("1500000000")))
        assertEquals("0.12", format(BigInteger("123456789")))
        assertEquals("42", format(BigInteger("42000000000")))
    }

    @Test
    fun insertsGroupingSeparatorEveryThreeDigits() {
        assertEquals(
            "1${thinSpace}234${thinSpace}567.89",
            format(BigInteger("1234567890000000"))
        )
    }

    @Test
    fun roundsUpAndCarriesIntoIntegerPart() {
        // 0.999999999 rounded to 2 decimals overflows into the integer part
        assertEquals("1", format(BigInteger("999999999")))
    }

    @Test
    fun floorsWhenRoundUpDisabled() {
        assertEquals("0.99", format(BigInteger("999999999"), roundUp = false))
    }

    @Test
    fun stripsTrailingZeros() {
        assertEquals("1.5", format(BigInteger("1500000000"), currencyDecimals = 9))
        assertEquals("2", format(BigInteger("2000000000"), currencyDecimals = 9))
    }

    @Test
    fun collapsesLeadingFractionalZerosIntoSubscript() {
        // 0.00000056 -> 0.0(subscript 6)56
        assertEquals(
            "0.0₆56",
            format(BigInteger("560"), currencyDecimals = 9)
        )
    }

    @Test
    fun skipsSubscriptBelowMinZeroCount() {
        // 5 leading zeros < min of 6 -> rendered plainly
        assertEquals(
            "0.0000056",
            format(BigInteger("5600"), currencyDecimals = 9)
        )
        // Disabled entirely with null
        assertEquals(
            "0.00000056",
            format(BigInteger("560"), currencyDecimals = 9, zeroCountSubscriptMinCount = null)
        )
    }

    @Test
    fun rendersNegativeWithSignSpace() {
        assertEquals("-${signSpace}1.5", format(BigInteger("-1500000000")))
    }

    @Test
    fun rendersPositiveSignWhenRequested() {
        assertEquals("+${signSpace}1.5", format(BigInteger("1500000000"), showPositiveSign = true))
    }

    @Test
    fun placesSingleCharCurrencyLeftAndMultiCharRight() {
        assertEquals("$1.5", format(BigInteger("1500000000"), currency = "$"))
        assertEquals("1.5 TON", format(BigInteger("1500000000"), currency = "TON"))
    }

    @Test
    fun forcesCurrencyRightWhenRequested() {
        assertEquals(
            "1.5 $",
            format(BigInteger("1500000000"), currency = "$", forceCurrencyToRight = true)
        )
    }

    // doubleAbsRepresentation

    @Test
    fun doubleAbsRepresentationConvertsBaseUnits() {
        assertEquals(1.5, BigInteger("1500000000").doubleAbsRepresentation(9), 0.0)
        assertEquals(1.5, BigInteger("-1500000000").doubleAbsRepresentation(9), 0.0)
        assertEquals(0.000000001, BigInteger.ONE.doubleAbsRepresentation(9), 0.0)
    }

    @Test
    fun doubleAbsRepresentationDefaultsToNineDecimals() {
        assertEquals(1.5, BigInteger("1500000000").doubleAbsRepresentation(), 0.0)
    }

    // smartDecimalsCount

    @Test
    fun smartDecimalsCapsAtTwoForLargeAmounts() {
        // 1.5 token (9 decimals)
        assertEquals(2, BigInteger("1500000000").smartDecimalsCount(9))
    }

    @Test
    fun smartDecimalsGrowsForTinyAmounts() {
        // 0.00000056 needs 8 decimals to surface its two significant digits
        assertEquals(8, BigInteger("560").smartDecimalsCount(9))
        // Sub-unit dust keeps full token precision
        assertEquals(9, BigInteger.ONE.smartDecimalsCount(9))
    }

    @Test
    fun smartDecimalsPassesThroughLowDecimalTokens() {
        assertEquals(2, BigInteger("123").smartDecimalsCount(2))
        assertEquals(0, BigInteger("123").smartDecimalsCount(0))
    }

    // max

    @Test
    fun maxReturnsLarger() {
        assertEquals(BigInteger.TEN, max(BigInteger.ONE, BigInteger.TEN))
        assertEquals(BigInteger.TEN, max(BigInteger.TEN, BigInteger.ONE))
    }
}
