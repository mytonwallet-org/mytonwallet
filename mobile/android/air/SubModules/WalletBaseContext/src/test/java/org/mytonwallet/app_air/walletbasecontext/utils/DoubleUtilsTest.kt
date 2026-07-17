package org.mytonwallet.app_air.walletbasecontext.utils

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import java.math.BigInteger

class DoubleUtilsTest {

    // Double.toBigInteger — converts amounts to base units

    @Test
    fun convertsToBaseUnits() {
        assertEquals(BigInteger("1500000000"), 1.5.toBigInteger(9))
        assertEquals(BigInteger("250"), 2.5.toBigInteger(2))
        assertEquals(BigInteger.ZERO, 0.0.toBigInteger(9))
    }

    @Test
    fun floorsSubUnitRemainders() {
        // 1.5 base units floors to 1, never rounds up user funds
        assertEquals(BigInteger.ONE, 0.0000000015.toBigInteger(9))
    }

    @Test
    fun rejectsNonFiniteValues() {
        assertNull(Double.NaN.toBigInteger(9))
        assertNull(Double.POSITIVE_INFINITY.toBigInteger(9))
        assertNull(Double.NEGATIVE_INFINITY.toBigInteger(9))
    }

    @Test
    fun handlesNegativeAmounts() {
        assertEquals(BigInteger("-1500000000"), (-1.5).toBigInteger(9))
    }

    // Double.smartDecimalsCount

    @Test
    fun zeroAmountNeedsNoDecimals() {
        assertEquals(0, 0.0.smartDecimalsCount(9))
    }

    @Test
    fun lowDecimalTokensPassThrough() {
        assertEquals(2, 123.45.smartDecimalsCount(2))
    }

    @Test
    fun amountsAboveOneCapNearTwo() {
        assertEquals(2, 1.5.smartDecimalsCount(9))
        assertEquals(2, 123.0.smartDecimalsCount(9))
    }

    @Test
    fun tinyAmountsGetMorePrecision() {
        assertEquals(1, 0.5.smartDecimalsCount(9))
        assertEquals(2, 0.05.smartDecimalsCount(9))
        assertEquals(7, 0.0000005.smartDecimalsCount(9))
    }

    @Test
    fun precisionNeverExceedsTokenDecimals() {
        assertEquals(6, 0.0000005.smartDecimalsCount(6))
    }

    // Double.negative

    @Test
    fun negativeAlwaysReturnsNegativeMagnitude() {
        assertEquals(-1.5, 1.5.negative(), 0.0)
        assertEquals(-1.5, (-1.5).negative(), 0.0)
    }
}
