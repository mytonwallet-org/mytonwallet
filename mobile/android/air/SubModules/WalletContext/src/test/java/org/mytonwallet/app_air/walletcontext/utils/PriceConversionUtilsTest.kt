package org.mytonwallet.app_air.walletcontext.utils

import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test
import java.math.BigInteger

class PriceConversionUtilsTest {

    // convertTokenToBaseCurrency — display value of a token amount in fiat

    @Test
    fun convertsTokenAmountToBaseCurrency() {
        // 1 token (9 decimals) at price 2.5, base currency with 2 decimals -> 250 (i.e. 2.50)
        assertEquals(
            BigInteger.valueOf(250),
            PriceConversionUtils.convertTokenToBaseCurrency("1", 9, 2.5, 2)
        )
    }

    @Test
    fun convertsFractionalTokenAmount() {
        // 0.5 token at price 2.0 -> 1.00
        assertEquals(
            BigInteger.valueOf(100),
            PriceConversionUtils.convertTokenToBaseCurrency("0.5", 9, 2.0, 2)
        )
    }

    @Test
    fun treatsNullPriceAsOne() {
        assertEquals(
            BigInteger.valueOf(100),
            PriceConversionUtils.convertTokenToBaseCurrency("1", 9, null, 2)
        )
    }

    @Test
    fun unparsableAmountConvertsToZero() {
        assertEquals(
            BigInteger.ZERO,
            PriceConversionUtils.convertTokenToBaseCurrency("abc", 9, 2.5, 2)
        )
    }

    @Test
    fun bigIntOverloadDefaultsNullDecimals() {
        // tokenDecimal null -> 9, baseCurrencyDecimal null -> 2
        assertEquals(
            BigInteger.valueOf(250),
            PriceConversionUtils.convertTokenToBaseCurrency(BigInteger("1000000000"), null, 2.5, null)
        )
    }

    // convertBaseCurrencyToToken — used when user types the fiat amount in Send

    @Test
    fun convertsBaseCurrencyAmountToTokenUnits() {
        // 2.50 in fiat at price 2.5 -> exactly 1 token = 1e9 base units
        assertEquals(
            BigInteger("1000000000"),
            PriceConversionUtils.convertBaseCurrencyToToken("2.5", 9, 2.5, 2)
        )
    }

    @Test
    fun convertsBaseCurrencyForTokenWithFewDecimals() {
        // 10.00 fiat at price 5.0 for a 6-decimals token -> 2 tokens = 2e6
        assertEquals(
            BigInteger("2000000"),
            PriceConversionUtils.convertBaseCurrencyToToken("10", 6, 5.0, 2)
        )
    }

    @Test
    fun throwsWhenPriceUnknown() {
        assertThrows(IllegalStateException::class.java) {
            PriceConversionUtils.convertBaseCurrencyToToken("1", 9, null, 2)
        }
    }

    @Test
    fun roundTripsTokenToFiatAndBack() {
        val fiat = PriceConversionUtils.convertTokenToBaseCurrency("2", 9, 4.0, 2)
        assertEquals(BigInteger.valueOf(800), fiat)
        assertEquals(
            BigInteger("2000000000"),
            PriceConversionUtils.convertBaseCurrencyToToken(CoinUtils.toDecimalString(fiat, 2), 9, 4.0, 2)
        )
    }
}