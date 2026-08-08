package org.mytonwallet.app_air.walletcore.moshi.adapter

import java.math.BigInteger
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class BigIntegerJsonAdapterTest {
    private val adapter = BigIntegerJsonAdapter()

    @Test
    fun decodesSdkPrefixedInteger() {
        assertEquals(
            BigInteger("12345678901234567890"),
            adapter.fromJson("\"bigint:12345678901234567890\"")
        )
    }

    @Test
    fun decodesUnprefixedInteger() {
        assertEquals(BigInteger.valueOf(42), adapter.fromJson("\"42\""))
    }

    @Test
    fun decodesLegacyJsonNumber() {
        assertEquals(BigInteger.valueOf(42), adapter.fromJson("42"))
    }

    @Test
    fun preservesNegativeInteger() {
        assertEquals(BigInteger.valueOf(-42), adapter.fromJson("\"bigint:-42\""))
    }

    @Test
    fun encodesIntegerWithSdkPrefix() {
        assertEquals(
            "\"bigint:12345678901234567890\"",
            adapter.toJson(BigInteger("12345678901234567890"))
        )
    }

    @Test
    fun encodesZeroWithSdkPrefix() {
        assertEquals("\"bigint:0\"", adapter.toJson(BigInteger.ZERO))
    }

    @Test
    fun encodesNullAsJsonNull() {
        assertEquals("null", adapter.toJson(null))
    }

    @Test
    fun rejectsMalformedInteger() {
        assertThrows(NumberFormatException::class.java) {
            adapter.fromJson("\"bigint:not-a-number\"")
        }
    }
}
