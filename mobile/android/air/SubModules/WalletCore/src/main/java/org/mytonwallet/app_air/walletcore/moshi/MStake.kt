package org.mytonwallet.app_air.walletcore.moshi

import com.squareup.moshi.JsonClass
import java.math.BigInteger


// Stake state
@JsonClass(generateAdapter = true)
data class MStakingStateResponse(
    val backendState: MStakingBackendState,
    val state: MStakingState
)

@JsonClass(generateAdapter = true)
data class MStakingBackendState(
    val nominatorsPool: MNominatorsPool,
    // val shouldUseNominators: Boolean,
    val totalProfit: BigInteger,
    val balance: BigInteger,
    // val type: String,
    // val loyaltyBalance: String,
    // val stakedAt: Long,
)

@JsonClass(generateAdapter = true)
data class MStakingState(
    val amount: BigInteger,
    val apy: Float,
    val instantAvailable: BigInteger,

    val type: String,
    val tokenAmount: BigInteger,
    val unstakeRequestAmount: BigInteger,
)

@JsonClass(generateAdapter = true)
data class MNominatorsPool(
    val address: String,
    val apy: Double,
    val start: Long?,
    val end: Long?
)

// History
@JsonClass(generateAdapter = true)
data class MStakeHistoryItem(
    val timestamp: Long,
    val profit: String,
)
