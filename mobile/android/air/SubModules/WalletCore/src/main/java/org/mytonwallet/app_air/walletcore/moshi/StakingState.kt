package org.mytonwallet.app_air.walletcore.moshi

import com.squareup.moshi.Json
import com.squareup.moshi.JsonClass
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.utils.DateUtils
import org.mytonwallet.app_air.walletbasecontext.utils.smartDecimalsCount
import org.mytonwallet.app_air.walletbasecontext.utils.toString
import org.mytonwallet.app_air.walletcore.TONCOIN_SLUG
import org.mytonwallet.app_air.walletcore.USDE_SLUG
import org.mytonwallet.app_air.walletcore.stores.TokenStore
import java.math.BigInteger

sealed class StakingState {
    abstract val stakingType: String
    abstract val id: String
    abstract val tokenSlug: String
    abstract val annualYield: Float
    abstract val yieldType: YieldType
    abstract val balance: BigInteger
    abstract val pool: String
    abstract val isUnstakeRequested: Boolean?
    abstract val unstakeRequestAmount: BigInteger?

    @JsonClass(generateAdapter = true)
    data class Liquid(
        @Transient override val stakingType: String = "liquid",
        override val id: String,
        override val tokenSlug: String,
        override val annualYield: Float,
        override val yieldType: YieldType,
        override val balance: BigInteger,
        override val pool: String,
        override val isUnstakeRequested: Boolean?,
        override val unstakeRequestAmount: BigInteger?,
        val tokenBalance: String,
        val instantAvailable: BigInteger,
        val end: Long
    ) : StakingState()

    @JsonClass(generateAdapter = true)
    data class Jetton(
        @Transient override val stakingType: String = "jetton",
        override val id: String,
        override val tokenSlug: String,
        override val annualYield: Float,
        override val yieldType: YieldType,
        override val balance: BigInteger,
        override val pool: String,
        override val isUnstakeRequested: Boolean?,
        override val unstakeRequestAmount: BigInteger? = null,
        val tokenAddress: String,
        val unclaimedRewards: BigInteger,
        val stakeWalletAddress: String,
        val tokenAmount: String,
        val period: Double,
        val tvl: String,
        val dailyReward: String,
        val poolWallets: List<String>?
    ) : StakingState()

    @JsonClass(generateAdapter = true)
    data class Ethena(
        @Transient override val stakingType: String = "ethena",
        override val id: String,
        override val tokenSlug: String,
        override val annualYield: Float,
        override val yieldType: YieldType,
        override val balance: BigInteger,
        override val pool: String,
        override val isUnstakeRequested: Boolean?,
        override val unstakeRequestAmount: BigInteger?,
        val tokenBalance: BigInteger?,
        val tsUsdeWalletAddress: String?,
        val lockedBalance: BigInteger?,
        val unlockTime: Long?,
        val annualYieldStandard: Float,
        val annualYieldVerified: Float,
    ) : StakingState()

    @JsonClass(generateAdapter = true)
    data class Nominators(
        @Transient override val stakingType: String = "nominators",
        override val id: String,
        override val tokenSlug: String,
        override val annualYield: Float,
        override val yieldType: YieldType,
        override val balance: BigInteger,
        override val pool: String,
        override val isUnstakeRequested: Boolean?,
        override val unstakeRequestAmount: BigInteger?,
        val end: Long
    ) : StakingState()

    @JsonClass(generateAdapter = false)
    enum class YieldType {
        @Json(name = "APY")
        APY,

        @Json(name = "APR")
        APR
    }

    fun getRequestedAmount(): String? {
        return when (this) {
            is Ethena -> {
                if (unstakeRequestAmount == BigInteger.ZERO)
                    return null
                val token = TokenStore.getToken(USDE_SLUG)!!
                unstakeRequestAmount?.toString(
                    decimals = token.decimals,
                    currency = token.symbol,
                    currencyDecimals = unstakeRequestAmount.smartDecimalsCount(token.decimals),
                    showPositiveSign = false,
                    roundUp = false
                )
            }

            is Jetton -> {
                null
            }

            is Liquid -> {
                if (unstakeRequestAmount == BigInteger.ZERO)
                    return null
                else {
                    val token = TokenStore.getToken(TONCOIN_SLUG)!!
                    unstakeRequestAmount?.toString(
                        decimals = token.decimals,
                        currency = token.symbol,
                        currencyDecimals = unstakeRequestAmount.smartDecimalsCount(token.decimals),
                        showPositiveSign = false
                    )
                }
            }

            is Nominators -> {
                if (unstakeRequestAmount == BigInteger.ZERO)
                    return null
                else {
                    val token = TokenStore.getToken(TONCOIN_SLUG)!!
                    unstakeRequestAmount?.toString(
                        decimals = token.decimals,
                        currency = token.symbol,
                        currencyDecimals = unstakeRequestAmount.smartDecimalsCount(token.decimals),
                        showPositiveSign = false
                    )
                }
            }
        }
    }

    val endTime: Long?
        get() = when (this) {
            is Ethena -> unlockTime
            is Jetton -> null
            is Liquid -> end
            is Nominators -> end
        }

    fun getRemainingToEndTime(): Long? {
        return endTime?.minus(System.currentTimeMillis())
    }

    fun getRemainingToEndTimeString(): String? {
        val remaining = getRemainingToEndTime()
        return when (this) {
            is Ethena -> remaining?.let {
                DateUtils.formatTimeToWait(it)
            } ?: LocaleController.getPlural(7, "\$in_days")

            is Jetton -> null
            else -> remaining?.let { DateUtils.formatTimeToWait(it) }
        }
    }

    val shouldShowWithdrawButton: Boolean
        get() {
            return when (this) {
                is Ethena -> {
                    totalBalance > BigInteger.ZERO
                }

                else -> {
                    balance > BigInteger.ZERO
                }
            }
        }

    val totalBalance: BigInteger
        get() {
            return when (this) {
                is Ethena -> {
                    balance + (unstakeRequestAmount ?: BigInteger.ZERO)
                }

                is Jetton -> {
                    balance + unclaimedRewards
                }

                else -> {
                    balance
                }
            }
        }

    val isUnstakeRequestAmountUnlocked: Boolean
        get() {
            return (unstakeRequestAmount ?: BigInteger.ZERO) > BigInteger.ZERO &&
                (getRemainingToEndTime() ?: 0) <= 0
        }

    val amountToClaim: BigInteger?
        get() {
            return when (this) {
                is Ethena -> {
                    unstakeRequestAmount ?: BigInteger.ZERO
                }

                is Jetton -> {
                    unclaimedRewards
                }

                else -> {
                    null
                }
            }
        }
}
