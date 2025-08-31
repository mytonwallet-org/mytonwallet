package org.mytonwallet.app_air.walletcore.moshi

import com.squareup.moshi.JsonClass
import java.math.BigInteger

@JsonClass(generateAdapter = true)
data class MStakingData(
    val totalProfit: BigInteger,
    val stakingCommonData: MStakingCommonData,
    val stakingState: StakingState
)
