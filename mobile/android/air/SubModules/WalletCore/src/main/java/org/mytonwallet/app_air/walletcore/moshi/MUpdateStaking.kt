package org.mytonwallet.app_air.walletcore.moshi

import com.squareup.moshi.JsonClass
import org.mytonwallet.app_air.walletcore.MYCOIN_SLUG
import org.mytonwallet.app_air.walletcore.STAKED_MYCOIN_SLUG
import org.mytonwallet.app_air.walletcore.STAKED_USDE_SLUG
import org.mytonwallet.app_air.walletcore.STAKE_SLUG
import org.mytonwallet.app_air.walletcore.TONCOIN_SLUG
import org.mytonwallet.app_air.walletcore.USDE_SLUG
import org.mytonwallet.app_air.walletcore.models.MTokenBalance
import org.mytonwallet.app_air.walletcore.stores.TokenStore
import java.math.BigInteger

@JsonClass(generateAdapter = true)
data class MUpdateStaking(
    val accountId: String,
    val states: List<StakingState?>,
    val totalProfit: BigInteger,
    val shouldUseNominators: Boolean?,
) {

    val tonStakingState: StakingState? by lazy {
        states.firstOrNull {
            if (shouldUseNominators == true)
                it is StakingState.Nominators
            else it is StakingState.Liquid
        }
    }

    val mycoinStakingState: StakingState? by lazy {
        states.firstOrNull {
            it is StakingState.Jetton && it.tokenSlug == MYCOIN_SLUG
        }
    }

    val usdeStakingState: StakingState? by lazy {
        states.firstOrNull {
            it is StakingState.Ethena && it.tokenSlug == USDE_SLUG
        }
    }

    val totalTonBalance: BigInteger?
        get() {
            return tonStakingState?.totalBalance
        }

    val totalMycoinBalance: BigInteger?
        get() {
            return mycoinStakingState?.totalBalance
        }

    val totalUSDeBalance: BigInteger?
        get() {
            return usdeStakingState?.totalBalance
        }

    fun stakingState(tokenSlug: String?): StakingState? {
        return when (tokenSlug) {
            TONCOIN_SLUG, STAKE_SLUG -> {
                tonStakingState
            }

            MYCOIN_SLUG, STAKED_MYCOIN_SLUG -> {
                mycoinStakingState
            }

            USDE_SLUG, STAKED_USDE_SLUG -> {
                usdeStakingState
            }

            else -> {
                null
            }
        }
    }

    fun hasActiveStaking(tokenSlug: String?): Boolean {
        return (stakingState(tokenSlug)?.totalBalance?.signum() ?: 0) > 0
    }

    fun hasActiveStaking(): Boolean {
        return states.any { (it?.totalBalance?.signum() ?: 0) > 0 }
    }

    fun activeStakingTokenSlug(): String? {
        return states.firstOrNull { (it?.totalBalance?.signum() ?: 0) > 0 }?.tokenSlug
    }

    private fun balanceInBaseCurrency(
        slug: String,
        balance: BigInteger?,
        selector: MTokenBalance.() -> Double?
    ): Double {
        return MTokenBalance.fromParameters(TokenStore.getToken(slug), balance)
            ?.let(selector) ?: 0.0
    }

    fun totalBalanceInBaseCurrency(): Double {
        return balanceInBaseCurrency(TONCOIN_SLUG, totalTonBalance) { toBaseCurrency } +
            balanceInBaseCurrency(MYCOIN_SLUG, totalMycoinBalance) { toBaseCurrency } +
            balanceInBaseCurrency(USDE_SLUG, totalUSDeBalance) { toBaseCurrency }
    }

    fun totalBalanceInUSD(): Double {
        return balanceInBaseCurrency(TONCOIN_SLUG, totalTonBalance) { toUsdBaseCurrency } +
            balanceInBaseCurrency(MYCOIN_SLUG, totalMycoinBalance) { toUsdBaseCurrency } +
            balanceInBaseCurrency(USDE_SLUG, totalUSDeBalance) { toUsdBaseCurrency }
    }

    fun totalBalanceInBaseCurrency24h(): Double {
        return balanceInBaseCurrency(TONCOIN_SLUG, totalTonBalance) { toBaseCurrency24h } +
            balanceInBaseCurrency(MYCOIN_SLUG, totalMycoinBalance) { toBaseCurrency24h } +
            balanceInBaseCurrency(USDE_SLUG, totalUSDeBalance) { toBaseCurrency24h }
    }
}
