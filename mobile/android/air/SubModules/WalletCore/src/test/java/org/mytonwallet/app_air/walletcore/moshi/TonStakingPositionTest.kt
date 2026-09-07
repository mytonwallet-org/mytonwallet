package org.mytonwallet.app_air.walletcore.moshi

import java.math.BigInteger
import org.junit.Assert.assertEquals
import org.junit.Test
import org.mytonwallet.app_air.walletcore.TONCOIN_SLUG

class TonStakingPositionTest {

    @Test
    fun loneLiquidPositionAnswersForTon() {
        val data =
            makeStakingData(
                liquidBalance = BigInteger.ZERO,
                nominatorsBalance = null,
                shouldUseNominators = true
            )

        assertEquals("liquid", data.tonStakingState?.id)
    }

    @Test
    fun forcedAccountWithEmptyLiquidStaysInNominators() {
        val data = makeStakingData(
            liquidBalance = BigInteger.ZERO,
            nominatorsBalance = BigInteger.ZERO,
            shouldUseNominators = true
        )

        assertEquals("nominators", data.tonStakingState?.id)
    }

    @Test
    fun activeNominatorsStakeWinsWhileLiquidIsEmpty() {
        val data = makeStakingData(
            liquidBalance = BigInteger.ZERO,
            nominatorsBalance = BigInteger("10000000000000"),
            shouldUseNominators = true
        )

        assertEquals("nominators", data.tonStakingState?.id)
    }

    @Test
    fun activeLiquidStakeWinsWhenBothAreActive() {
        val data = makeStakingData(
            liquidBalance = BigInteger("5000000000"),
            nominatorsBalance = BigInteger("10000000000000"),
            shouldUseNominators = true
        )

        assertEquals("liquid", data.tonStakingState?.id)
    }

    @Test
    fun liquidStakeWaitingToUnstakeStillWinsTheTie() {
        // A fully unstaked liquid position keeps its money in the pending request, not in the balance.
        val data = makeStakingData(
            liquidBalance = BigInteger.ZERO,
            nominatorsBalance = BigInteger("10000000000000"),
            shouldUseNominators = true,
            liquidUnstakeRequestAmount = BigInteger("5000000000")
        )

        assertEquals("liquid", data.tonStakingState?.id)
    }

    @Test
    fun nominatorsPositionAnswersEvenWhenTheFlagContradictsIt() {
        // The API builds the position from a wider condition than the flag shipped beside it.
        val data = makeStakingData(
            liquidBalance = BigInteger.ZERO,
            nominatorsBalance = BigInteger("10000000000000"),
            shouldUseNominators = false
        )

        assertEquals("nominators", data.tonStakingState?.id)
    }

    private fun makeStakingData(
        liquidBalance: BigInteger,
        nominatorsBalance: BigInteger?,
        shouldUseNominators: Boolean?,
        liquidUnstakeRequestAmount: BigInteger? = null
    ): MUpdateStaking {
        val liquid = StakingState.Liquid(
            id = "liquid",
            tokenSlug = TONCOIN_SLUG,
            annualYield = 13.62f,
            yieldType = StakingState.YieldType.APY,
            balance = liquidBalance,
            pool = "liquid-pool",
            isUnstakeRequested = liquidUnstakeRequestAmount != null,
            unstakeRequestAmount = liquidUnstakeRequestAmount,
            tokenBalance = "0",
            loyaltyBalance = null,
            instantAvailable = BigInteger.ZERO,
            end = 0L,
            totalStakers = null,
            tvl = null
        )
        val nominators = nominatorsBalance?.let {
            StakingState.Nominators(
                id = "nominators",
                tokenSlug = TONCOIN_SLUG,
                annualYield = 9.58f,
                yieldType = StakingState.YieldType.APY,
                balance = it,
                pool = "nominators-pool",
                isUnstakeRequested = false,
                unstakeRequestAmount = null,
                end = 0L
            )
        }

        return MUpdateStaking(
            accountId = "ton-staking-test",
            states = listOfNotNull(liquid, nominators),
            totalProfit = BigInteger.ZERO,
            shouldUseNominators = shouldUseNominators
        )
    }
}
