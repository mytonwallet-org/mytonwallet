package org.mytonwallet.app_air.walletcore.models

import org.json.JSONObject
import org.mytonwallet.app_air.walletbasecontext.utils.doubleAbsRepresentation
import org.mytonwallet.app_air.walletcore.TONCOIN_SLUG
import org.mytonwallet.app_air.walletcore.TON_USDT_SLUG
import org.mytonwallet.app_air.walletcore.TRON_SLUG
import java.math.BigInteger

data class MTokenBalance(
    val token: String?,
    val amountValue: BigInteger,
    var toBaseCurrency: Double?,
    var toBaseCurrency24h: Double?,
    val toUsdBaseCurrency: Double?,
    val isVirtualStakingRow: Boolean = false,
) {

    val priority: Int
        get() {
            return when (token) {
                TONCOIN_SLUG -> 1
                TON_USDT_SLUG -> 1
                TRON_SLUG -> 1
                else -> 0
            }
        }

    val priorityOnSameBalance: Int
        get() {
            return when (token) {
                TONCOIN_SLUG -> 3
                TON_USDT_SLUG -> 2
                TRON_SLUG -> 1
                else -> 0
            }
        }

    companion object {
        // Factory method to create an instance from JSON
        fun fromJson(json: JSONObject): MTokenBalance {
            val token = json.optJSONObject("token")?.optString("slug")
            val amountValueString = json.optString("balance").substringAfter("bigint:", "")
            val amountValue = amountValueString.toBigIntegerOrNull() ?: BigInteger.ZERO
            return MTokenBalance(token, amountValue, null, null, null)
        }

        // Factory method to create an instance from separate parameters
        fun fromParameters(token: MToken?, amount: BigInteger?): MTokenBalance? {
            if (token == null || amount == null)
                return null
            val toBaseCurrency =
                token.price?.let { amount.doubleAbsRepresentation(token.decimals) * it }
            val priceYesterday =
                token.price?.let { (token.price!!) / (1 + token.percentChange24hReal / 100) }
            val toBaseCurrency24h =
                priceYesterday?.let { amount.doubleAbsRepresentation(token.decimals) * priceYesterday }
            val toUsdBaseCurrency =
                token.priceUsd.let { amount.doubleAbsRepresentation(token.decimals) * it }
            return MTokenBalance(
                token.slug,
                amount,
                toBaseCurrency,
                toBaseCurrency24h,
                toUsdBaseCurrency
            )
        }

        fun fromVirtualStakingData(baseToken: MToken, amount: BigInteger): MTokenBalance {
            return fromParameters(baseToken, amount)!!.copy(
                isVirtualStakingRow = true
            )
        }
    }
}
