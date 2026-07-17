package org.mytonwallet.app_air.walletcontext.utils

import org.mytonwallet.app_air.walletbasecontext.utils.toBigInteger
import java.math.BigInteger
import kotlin.math.max

object PriceConversionUtils {

    fun convertTokenToBaseCurrency(
        tokenAmount: String,
        tokenDecimal: Int,
        tokenPrice: Double?,
        baseCurrencyDecimal: Int?
    ): BigInteger {
        val amountBigInt = CoinUtils.fromDecimal(tokenAmount, tokenDecimal) ?: BigInteger.valueOf(0)
        return convertTokenToBaseCurrency(
            amountBigInt,
            tokenDecimal,
            tokenPrice,
            baseCurrencyDecimal
        )
    }

    fun convertTokenToBaseCurrency(
        tokenAmountBigInt: BigInteger,
        tokenDecimal: Int?,
        tokenPrice: Double?,
        baseCurrencyDecimal: Int?
    ): BigInteger {
        val baseMul = max(6, baseCurrencyDecimal ?: 2)
        // Non-finite prices cannot be converted; render as zero instead of crashing
        val priceBigInt = (tokenPrice ?: 1.0).toBigInteger(baseMul) ?: return BigInteger.ZERO
        val amountInBaseCurrency =
            tokenAmountBigInt * priceBigInt / BigInteger.valueOf(10).pow(
                baseMul - (baseCurrencyDecimal ?: 2) + (tokenDecimal ?: 9)
            )
        return amountInBaseCurrency
    }

    fun convertBaseCurrencyToToken(
        baseCurrencyAmount: String,
        tokenDecimal: Int,
        tokenPrice: Double?,
        baseCurrencyDecimal: Int?
    ): BigInteger {
        val amountInBaseCurrencyBigInt = CoinUtils.fromDecimal(
            baseCurrencyAmount,
            baseCurrencyDecimal ?: 2
        ) ?: BigInteger.ZERO

        val price = tokenPrice ?: run {
            throw IllegalStateException()
        }
        val priceBigInt = price.toBigInteger(9)
            ?: throw IllegalStateException("Token price is not finite")
        val amount = amountInBaseCurrencyBigInt * BigInteger.valueOf(10)
            .pow(9) / priceBigInt * BigInteger.valueOf(10)
            .pow(tokenDecimal) / BigInteger.valueOf(10)
            .pow(baseCurrencyDecimal ?: 2)
        return amount
    }

}
