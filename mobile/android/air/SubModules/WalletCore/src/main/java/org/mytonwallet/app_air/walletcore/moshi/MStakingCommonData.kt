package org.mytonwallet.app_air.walletcore.moshi

import com.squareup.moshi.JsonClass
import org.mytonwallet.app_air.walletcore.MYCOIN_SLUG


@JsonClass(generateAdapter = true)
data class MStakingCommonData(
    val liquid: Liquid,
    val round: Round,
    val prevRound: Round,
    val jettonPools: List<JettonPool>
) {
    val MStakingCommonData.mycoinPool: JettonPool?
        get() = jettonPools.firstOrNull { it.token == MYCOIN_SLUG }
}

@JsonClass(generateAdapter = true)
data class Round(
    val start: Long,
    val end: Long,
    val unlock: Long
)

@JsonClass(generateAdapter = true)
data class Liquid(
    val currentRate: Double,
    val nextRoundRate: Double,
    //val collection: String,
    val apy: Double,
    val loyaltyApy: LoyaltyApy,
    val available: String
)

@JsonClass(generateAdapter = true)
data class LoyaltyApy(
    val black: Double?,
    val platinum: Double?,
    val gold: Double?,
    val silver: Double?,
    val standard: Double?
)

@JsonClass(generateAdapter = true)
data class JettonPool(
    val pool: String,
    val token: String,
    val periods: List<Period>
)

@JsonClass(generateAdapter = true)
data class Period(
    val period: Long,
    val unstakeCommission: Double,
    val token: String
)
