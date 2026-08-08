package org.mytonwallet.app_air.walletcore.moshi

import java.math.BigInteger
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.mytonwallet.app_air.walletcore.MYCOIN_SLUG
import org.mytonwallet.app_air.walletcore.models.MToken

class MycoinStakingAvailabilityTest {

    @Test
    fun mycoinDoesNotAcceptNewStakes() {
        assertFalse(MToken.isEarnAvailableSlug(MYCOIN_SLUG))
    }

    @Test
    fun emptyMycoinStakingIsHidden() {
        val data = makeStakingData(balance = BigInteger.ZERO, unclaimedRewards = BigInteger.ZERO)

        assertFalse(data.hasActiveStaking(MYCOIN_SLUG))
    }

    @Test
    fun existingMycoinStakeRemainsVisible() {
        val data = makeStakingData(balance = BigInteger.ONE, unclaimedRewards = BigInteger.ZERO)

        assertTrue(data.hasActiveStaking(MYCOIN_SLUG))
    }

    @Test
    fun unclaimedMycoinRewardsRemainVisible() {
        val data = makeStakingData(balance = BigInteger.ZERO, unclaimedRewards = BigInteger.ONE)

        assertTrue(data.hasActiveStaking(MYCOIN_SLUG))
    }

    private fun makeStakingData(balance: BigInteger, unclaimedRewards: BigInteger): MUpdateStaking {
        val state = StakingState.Jetton(
            id = "mycoin-staking-pool",
            tokenSlug = MYCOIN_SLUG,
            annualYield = 10f,
            yieldType = StakingState.YieldType.APY,
            balance = balance,
            pool = "mycoin-staking-pool",
            isUnstakeRequested = false,
            tokenAddress = "token-address",
            unclaimedRewards = unclaimedRewards,
            stakeWalletAddress = "stake-wallet-address",
            tokenAmount = "0",
            period = 0.0,
            tvl = "0",
            dailyReward = "0",
            poolWallets = null
        )
        return MUpdateStaking(
            accountId = "mycoin-staking-test",
            states = listOf(state),
            totalProfit = BigInteger.ZERO,
            shouldUseNominators = null
        )
    }
}
