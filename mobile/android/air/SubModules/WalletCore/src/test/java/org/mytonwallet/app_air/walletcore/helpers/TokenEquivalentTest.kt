package org.mytonwallet.app_air.walletcore.helpers

import java.math.BigDecimal
import java.math.BigInteger
import org.junit.Assert.assertEquals
import org.junit.Test
import org.mytonwallet.app_air.walletbasecontext.models.MBaseCurrency
import org.mytonwallet.app_air.walletcore.moshi.IApiToken

class TokenEquivalentTest {

    @Test
    fun convertsBaseCurrencyWithRepeatingQuotient() {
        val equivalent = TokenEquivalent.from(
            inFiatMode = true,
            price = BigDecimal("3"),
            token = token(decimals = 9),
            amount = BigInteger("100"),
            currency = MBaseCurrency.USD
        )

        assertEquals(BigInteger("333333333"), equivalent.tokenAmount.amountInteger)
    }

    @Test
    fun roundsBaseCurrencyConversionDownToTokenPrecision() {
        val equivalent = TokenEquivalent.from(
            inFiatMode = true,
            price = BigDecimal("0.3"),
            token = token(decimals = 2),
            amount = BigInteger.ONE,
            currency = MBaseCurrency.USD
        )

        assertEquals(BigInteger("3"), equivalent.tokenAmount.amountInteger)
    }

    private fun token(decimals: Int) = object : IApiToken {
        override val slug = "test"
        override val decimals = decimals
        override val name: String? = "Test"
        override val symbol: String? = "TEST"
        override val chain: String? = null
        override val tokenAddress: String? = null
        override val image: String? = null
        override val isPopular: Boolean? = null
        override val keywords: List<String>? = null
    }
}
