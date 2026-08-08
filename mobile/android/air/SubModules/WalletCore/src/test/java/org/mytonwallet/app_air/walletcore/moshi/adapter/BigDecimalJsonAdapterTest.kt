package org.mytonwallet.app_air.walletcore.moshi.adapter

import java.math.BigDecimal
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class BigDecimalJsonAdapterTest {
    private val adapter = BigDecimalJsonAdapter()

    @Test
    fun decodesDecimalWithoutPrecisionLoss() {
        assertEquals(
            BigDecimal("1234567890.123456789"),
            adapter.fromJson("\"1234567890.123456789\"")
        )
    }

    @Test
    fun preservesNegativeDecimal() {
        assertEquals(BigDecimal("-0.000000001"), adapter.fromJson("\"-0.000000001\""))
    }

    @Test
    fun decodesLegacyJsonNumber() {
        assertEquals(BigDecimal("42.125"), adapter.fromJson("42.125"))
    }

    @Test
    fun encodesDecimalWithoutScientificNotation() {
        assertEquals("\"0.000000001\"", adapter.toJson(BigDecimal("1E-9")))
    }

    @Test
    fun removesInsignificantTrailingZeros() {
        assertEquals("\"1.23\"", adapter.toJson(BigDecimal("1.2300")))
    }

    @Test
    fun encodesLargeExponentAsPlainDecimal() {
        assertEquals("\"100000000000000000000\"", adapter.toJson(BigDecimal("1E+20")))
    }

    @Test
    fun encodesNullAsJsonNull() {
        assertEquals("null", adapter.toJson(null))
    }

    @Test
    fun rejectsMalformedDecimal() {
        assertThrows(NumberFormatException::class.java) {
            adapter.fromJson("\"not-a-number\"")
        }
    }
}
