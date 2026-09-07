package org.mytonwallet.app_air.walletcore.moshi

import com.squareup.moshi.JsonClass
import java.math.BigInteger
import org.mytonwallet.app_air.walletcore.MYCOIN_SLUG
import org.mytonwallet.app_air.walletcore.STAKED_MYCOIN_SLUG
import org.mytonwallet.app_air.walletcore.STAKED_USDE_SLUG
import org.mytonwallet.app_air.walletcore.STAKE_SLUG
import org.mytonwallet.app_air.walletcore.TONCOIN_SLUG
import org.mytonwallet.app_air.walletcore.USDE_SLUG
import org.mytonwallet.app_air.walletcore.models.MTokenBalance
import org.mytonwallet.app_air.walletcore.stores.TokenStore

@JsonClass(generateAdapter = true)
data class MUpdateStaking(
    val accountId: String,
    val states: List<StakingState?>,
    val totalProfit: BigInteger,
    val shouldUseNominators: Boolean?
) {

    /**
     * An account gets a nominators position only when the API builds one for it, so the position's own
     * presence answers whether this account stakes through nominators - `shouldUseNominators` is derived
     * separately and can contradict the list. An active liquid stake wins the tie, nominators being legacy.
     */
    val tonStakingState: StakingState? by lazy {
        val matching = states.filterNotNull().filter { it.tokenSlug == TONCOIN_SLUG }
        if (matching.size < 2) {
            matching.firstOrNull()
        } else {
            val liquid = matching.firstOrNull { it is StakingState.Liquid }
            if (liquid != null && liquid.hasStakingPosition) {
                liquid
            } else {
                matching.firstOrNull { it is StakingState.Nominators } ?: matching.first()
            }
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

    fun stakingState(tokenSlug: String?): StakingState? = when (tokenSlug) {
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

    fun hasActiveStaking(tokenSlug: String?): Boolean =
        (stakingState(tokenSlug)?.totalBalance?.signum() ?: 0) > 0

    fun hasActiveStaking(): Boolean = states.any { (it?.totalBalance?.signum() ?: 0) > 0 }

    fun activeStakingTokenSlug(): String? = states.firstOrNull {
        (it?.totalBalance?.signum() ?: 0) > 0
    }?.tokenSlug

    private fun balanceInBaseCurrency(
        slug: String,
        balance: BigInteger?,
        selector: MTokenBalance.() -> Double?
    ): Double = MTokenBalance.fromParameters(TokenStore.getToken(slug), balance)
        ?.let(selector) ?: 0.0

    fun totalBalanceInBaseCurrency(): Double =
        balanceInBaseCurrency(TONCOIN_SLUG, totalTonBalance) {
            toBaseCurrency
        } +
            balanceInBaseCurrency(MYCOIN_SLUG, totalMycoinBalance) { toBaseCurrency } +
            balanceInBaseCurrency(USDE_SLUG, totalUSDeBalance) { toBaseCurrency }

    fun totalBalanceInUSD(): Double = balanceInBaseCurrency(TONCOIN_SLUG, totalTonBalance) {
        toUsdBaseCurrency
    } +
        balanceInBaseCurrency(MYCOIN_SLUG, totalMycoinBalance) { toUsdBaseCurrency } +
        balanceInBaseCurrency(USDE_SLUG, totalUSDeBalance) { toUsdBaseCurrency }

    fun totalBalanceInBaseCurrency24h(): Double =
        balanceInBaseCurrency(TONCOIN_SLUG, totalTonBalance) {
            toBaseCurrency24h
        } +
            balanceInBaseCurrency(MYCOIN_SLUG, totalMycoinBalance) { toBaseCurrency24h } +
            balanceInBaseCurrency(USDE_SLUG, totalUSDeBalance) { toBaseCurrency24h }
}
