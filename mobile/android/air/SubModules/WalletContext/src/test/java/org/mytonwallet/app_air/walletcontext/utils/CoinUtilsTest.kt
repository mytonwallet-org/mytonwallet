package org.mytonwallet.app_air.walletcontext.utils

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import java.math.BigDecimal
import java.math.BigInteger

class CoinUtilsTest {

    // toDecimalString(BigInteger)

    @Test
    fun toDecimalStringConvertsBaseUnits() {
        assertEquals("1.5", CoinUtils.toDecimalString(BigInteger("1500000000"), 9))
        assertEquals("0.000000001", CoinUtils.toDecimalString(BigInteger.ONE, 9))
        assertEquals("123", CoinUtils.toDecimalString(BigInteger("123000000000"), 9))
    }

    @Test
    fun toDecimalStringHandlesZeroAndNegative() {
        assertEquals("0", CoinUtils.toDecimalString(BigInteger.ZERO, 9))
        assertEquals("-1.5", CoinUtils.toDecimalString(BigInteger("-1500000000"), 9))
    }

    @Test
    fun toDecimalStringHandlesZeroDecimals() {
        assertEquals("42", CoinUtils.toDecimalString(BigInteger("42"), 0))
    }

    // toDecimalString(String)

    @Test
    fun toDecimalStringFromStringParsesBaseUnits() {
        assertEquals("1.5", CoinUtils.toDecimalString("1500000000", 9))
    }

    @Test
    fun toDecimalStringFromStringReturnsNullOnMalformedInput() {
        assertNull(CoinUtils.toDecimalString("not-a-number", 9))
        assertNull(CoinUtils.toDecimalString("1.5", 9))
    }

    @Test
    fun toDecimalStringFromStringPassesThroughNulls() {
        assertNull(CoinUtils.toDecimalString(null, 9))
        assertEquals("123", CoinUtils.toDecimalString("123", null))
    }

    // toDecimalString(BigDecimal)

    @Test
    fun toDecimalStringRoundsHalfUpWhenRounding() {
        assertEquals("1.24", CoinUtils.toDecimalString(BigDecimal("1.235"), 2, round = true))
    }

    @Test
    fun toDecimalStringFloorsWhenNotRounding() {
        assertEquals("1.23", CoinUtils.toDecimalString(BigDecimal("1.239"), 2, round = false))
    }

    // fromDecimal — converts user-entered amounts to base units for transactions

    @Test
    fun fromDecimalConvertsUserAmountToBaseUnits() {
        assertEquals(BigInteger("1500000000"), CoinUtils.fromDecimal("1.5", 9))
        assertEquals(BigInteger("1"), CoinUtils.fromDecimal("0.000000001", 9))
        assertEquals(BigInteger("-1500000000"), CoinUtils.fromDecimal("-1.5", 9))
    }

    @Test
    fun fromDecimalTruncatesBelowSmallestUnit() {
        assertEquals(BigInteger.ZERO, CoinUtils.fromDecimal("0.0000000001", 9))
    }

    @Test
    fun fromDecimalReturnsNullOnMalformedInput() {
        assertNull(CoinUtils.fromDecimal("abc", 9))
        assertNull(CoinUtils.fromDecimal("1,5", 9))
        assertNull(CoinUtils.fromDecimal("", 9))
        assertNull(CoinUtils.fromDecimal(null as String?, 9))
    }

    @Test
    fun fromDecimalRoundTripsWithToDecimalString() {
        val original = "123.456789"
        val baseUnits = CoinUtils.fromDecimal(original, 9)!!
        assertEquals(original, CoinUtils.toDecimalString(baseUnits, 9))
    }

    @Test
    fun fromDecimalBigDecimalOverloadMatchesStringOverload() {
        assertEquals(
            CoinUtils.fromDecimal("1.5", 9),
            CoinUtils.fromDecimal(BigDecimal("1.5"), 9)
        )
        assertNull(CoinUtils.fromDecimal(null as BigDecimal?, 9))
    }

    // toBigDecimal

    @Test
    fun toBigDecimalScalesByDecimals() {
        assertEquals(BigDecimal("1.500000000"), CoinUtils.toBigDecimal(BigInteger("1500000000"), 9))
    }
}