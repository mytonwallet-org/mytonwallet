package org.mytonwallet.app_air.walletcore.models

import org.json.JSONObject
import org.mytonwallet.app_air.walletbasecontext.utils.doubleAbsRepresentation
import org.mytonwallet.app_air.walletcore.SOLANA_SLUG
import org.mytonwallet.app_air.walletcore.TONCOIN_SLUG
import org.mytonwallet.app_air.walletcore.TON_USDT_SLUG
import org.mytonwallet.app_air.walletcore.TON_USDT_TESTNET_SLUG
import org.mytonwallet.app_air.walletcore.TRON_SLUG
import org.mytonwallet.app_air.walletcore.TRON_USDT_SLUG
import org.mytonwallet.app_air.walletcore.TRON_USDT_TESTNET_SLUG
import org.mytonwallet.app_air.walletcore.buildVirtualStakingSlug
import org.mytonwallet.app_air.walletcore.stores.TokenStore
import java.math.BigInteger

data class MTokenBalance(
    val token: String?,
    val amountValue: BigInteger,
    var toBaseCurrency: Double?,
    var toBaseCurrency24h: Double?,
    val toUsdBaseCurrency: Double?,
    val isVirtualStakingRow: Boolean = false,
) {
    val virtualStakingToken: String? = if (isVirtualStakingRow && token != null) {
        buildVirtualStakingSlug(token)
    } else {
        token
    }

    private val priorityOrder: Int get() = PRIORITY_ORDER.indexOf(token)

    val priorityOnSameBalance: Int
        get() {
            return when (token) {
                TONCOIN_SLUG -> 5
                TON_USDT_SLUG, TON_USDT_TESTNET_SLUG -> 4
                TRON_SLUG -> 3
                TRON_USDT_SLUG, TRON_USDT_TESTNET_SLUG -> 2
                SOLANA_SLUG -> 1
                else -> 0
            }
        }

    fun compareByDisplayOrder(
        other: MTokenBalance,
        ignorePriorities: Boolean = false,
    ): Int {
        val thisValue = this.toBaseCurrency ?: this.toUsdBaseCurrency ?: 0.0
        val otherValue = other.toBaseCurrency ?: other.toUsdBaseCurrency ?: 0.0

        if (!ignorePriorities) {
            val thisOrder = this.priorityOrder
            val otherOrder = other.priorityOrder
            if (thisOrder != -1 && otherOrder != -1) {
                if (thisValue == otherValue) {
                    val orderCompare = thisOrder.compareTo(otherOrder)
                    return when {
                        orderCompare != 0 -> orderCompare
                        this.isVirtualStakingRow == other.isVirtualStakingRow -> 0
                        else -> if (this.isVirtualStakingRow) -1 else 1
                    }
                }
            } else if (thisOrder != -1 && otherOrder == -1) {
                return -1
            } else if (otherOrder != -1 && thisOrder == -1) {
                return 1
            }
        }

        val valueCompare = otherValue.compareTo(thisValue)
        if (valueCompare != 0) {
            return valueCompare
        }

        if (!ignorePriorities) {
            val sameBalanceCompare =
                other.priorityOnSameBalance.compareTo(this.priorityOnSameBalance)
            if (sameBalanceCompare != 0) {
                return sameBalanceCompare
            }
        }

        val thisSlug = this.token ?: ""
        val otherSlug = other.token ?: ""
        val thisName = TokenStore.getToken(thisSlug)?.name ?: thisSlug
        val otherName = TokenStore.getToken(otherSlug)?.name ?: otherSlug
        val nameCompare = thisName.compareTo(otherName)
        if (nameCompare != 0) {
            return nameCompare
        }
        return thisSlug.compareTo(otherSlug)
    }

    companion object {
        private val PRIORITY_ORDER = listOf(
            TONCOIN_SLUG,
            TON_USDT_SLUG,
            TON_USDT_TESTNET_SLUG,
            TRON_SLUG,
            TRON_USDT_SLUG,
            TRON_USDT_TESTNET_SLUG,
            SOLANA_SLUG
        )

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
                token.price?.let { amount.doubleAbsRepresentation(token.decimals) * it }?.let {
                    if (it.isFinite()) it else null
                }
            val priceYesterday =
                token.price?.let { (token.price!!) / (1 + token.percentChange24hReal / 100) }?.let {
                    if (it.isFinite()) it else null
                }
            val toBaseCurrency24h =
                priceYesterday?.let { amount.doubleAbsRepresentation(token.decimals) * priceYesterday }
                    ?.let {
                        if (it.isFinite()) it else null
                    }
            val toUsdBaseCurrency =
                token.priceUsd.let { amount.doubleAbsRepresentation(token.decimals) * it }.let {
                    if (it.isFinite()) it else null
                }
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
                token = baseToken.slug,
                isVirtualStakingRow = true
            )
        }
    }
}
