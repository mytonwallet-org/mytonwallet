package org.mytonwallet.app_air.walletcore.helpers

import org.mytonwallet.app_air.walletbasecontext.models.MBaseCurrency
import org.mytonwallet.app_air.walletbasecontext.utils.smartDecimalsCount
import org.mytonwallet.app_air.walletbasecontext.utils.toString
import org.mytonwallet.app_air.walletcore.moshi.IApiToken
import java.math.BigDecimal
import java.math.BigInteger

data class TokenAmount(
    val decimals: Int,
    val amountInteger: BigInteger,
) {
    val amountDecimal = amountInteger.toBigDecimal(decimals)

    companion object {
        fun valueOf(decimals: Int, amount: BigInteger): TokenAmount {
            return TokenAmount(
                decimals = decimals,
                amountInteger = amount,
            )
        }

        fun valueOf(decimals: Int, amount: BigDecimal): TokenAmount {
            return TokenAmount(
                decimals = decimals,
                amountInteger = amount.movePointRight(decimals).toBigInteger(),
            )
        }
    }
}

data class TokenEquivalent(
    val price: BigDecimal,
    val token: IApiToken,
    val tokenAmount: TokenAmount,
    val currency: MBaseCurrency,
    val currencyAmount: TokenAmount
) {
    private val tokenAmountDec = tokenAmount.amountDecimal
    private val currencyAmountDec = maxOf(
        currencyAmount.amountInteger,
        BigInteger.ZERO
    ).toBigDecimal(currency.decimalsCount)

    private val tokenFmt: String = tokenAmount.amountInteger.toString(
        decimals = token.decimals,
        currency = token.symbol ?: "",
        currencyDecimals = tokenAmount.amountInteger.smartDecimalsCount(token.decimals),
        showPositiveSign = false,
        roundUp = false
    )

    private val currencyFmt: String = currencyAmount.amountInteger.toString(
        decimals = currency.decimalsCount,
        currency = currency.sign,
        currencyDecimals = currencyAmount.amountInteger.smartDecimalsCount(currency.decimalsCount),
        showPositiveSign = false,
        roundUp = false
    )

    fun getRaw(currency: Boolean): String =
        (if (currency) currencyAmountDec else tokenAmountDec).stripTrailingZeros().toPlainString()

    fun getFmt(currency: Boolean) = if (currency) currencyFmt else tokenFmt

    fun getTokenAmount(): BigInteger = tokenAmount.amountInteger

    companion object {
        fun from(
            inFiatMode: Boolean,
            price: BigDecimal,
            token: IApiToken,
            amount: BigInteger,
            currency: MBaseCurrency
        ): TokenEquivalent {
            return if (inFiatMode) {
                fromCurrency(price, token, amount, currency)
            } else {
                fromToken(price, token, amount, currency)
            }
        }

        fun fromToken(
            price: BigDecimal,
            token: IApiToken,
            amount: BigInteger,
            currency: MBaseCurrency,
        ): TokenEquivalent {
            val tokenAmount = TokenAmount.valueOf(token.decimals, amount)
            val currencyAmountDecimal = (tokenAmount.amountDecimal * price).stripTrailingZeros()

            return TokenEquivalent(
                price = price,
                token = token,
                tokenAmount = tokenAmount,
                currency = currency,
                currencyAmount = TokenAmount.valueOf(currency.decimalsCount, currencyAmountDecimal)
            )
        }

        private fun fromCurrency(
            price: BigDecimal,
            token: IApiToken,
            amount: BigInteger,
            currency: MBaseCurrency,
        ): TokenEquivalent {
            val currencyAmount = TokenAmount.valueOf(currency.decimalsCount, amount)
            val tokenAmountDecimal = if (price > BigDecimal.ZERO)
                (currencyAmount.amountDecimal / price).stripTrailingZeros()
            else BigDecimal.ZERO

            return TokenEquivalent(
                price = price,
                token = token,
                tokenAmount = TokenAmount.valueOf(token.decimals, tokenAmountDecimal),
                currency = currency,
                currencyAmount = currencyAmount
            )
        }
    }
}
