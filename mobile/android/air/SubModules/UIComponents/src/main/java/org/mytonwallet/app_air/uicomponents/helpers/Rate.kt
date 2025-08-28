package org.mytonwallet.app_air.uicomponents.helpers

import org.mytonwallet.app_air.walletcontext.utils.CoinUtils
import java.math.BigDecimal
import java.math.BigInteger
import java.math.RoundingMode

data class Rate(
    val sendAmount: BigDecimal,
    val receiveAmount: BigDecimal,
) {

    fun fmtSend(symbol: String?, decimals: Int?, round: Boolean) =
        fmt(sendAmount, symbol, decimals, round)

    fun fmtReceive(symbol: String?, decimals: Int?, round: Boolean) =
        fmt(receiveAmount, symbol, decimals, round)

    companion object {
        private fun fmt(
            amount: BigDecimal,
            symbol: String?,
            decimals: Int?,
            round: Boolean
        ): String {
            val amountFmt = CoinUtils.toDecimalString(amount, decimals, round)
            return symbol?.let { "$amountFmt $it" } ?: amountFmt
        }

        fun build(
            sendAmount: BigDecimal,
            receiveAmount: BigDecimal
        ): Rate {
            if (receiveAmount.compareTo(BigDecimal.ZERO) == 0 || receiveAmount == BigInteger.ZERO) {
                return Rate(sendAmount = BigDecimal.ZERO, receiveAmount = BigDecimal.ONE)
            }

            val i = 0
            val rate = sendAmount.divide(receiveAmount, 9, RoundingMode.UP).stripTrailingZeros()
            if (rate.compareTo(BigDecimal.ZERO) == 0) {
                return Rate(sendAmount = BigDecimal.ZERO, receiveAmount = BigDecimal.ONE)
            }

            /*while (rate < BigDecimal("0.1")) {
                if (i > 9) break

                rate = rate.scaleByPowerOfTen(1)
                i++
            }*/

            return Rate(
                sendAmount = rate,
                receiveAmount = BigDecimal.ONE.scaleByPowerOfTen(i)
            )
        }
    }
}
