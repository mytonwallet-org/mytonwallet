package org.mytonwallet.app_air.walletcore.api

import com.squareup.moshi.Types
import org.json.JSONObject
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.moshi.ApiSubmitTransferResult
import org.mytonwallet.app_air.walletcore.moshi.MStakeHistoryItem
import org.mytonwallet.app_air.walletcore.moshi.MStakingStateResponse
import org.mytonwallet.app_air.walletcore.moshi.StakingState
import org.mytonwallet.app_air.walletcore.moshi.api.ApiMethod
import java.math.BigInteger


suspend fun WalletCore.getBackendStakingState(accountId: String) = run {
    val quotedAccountId = JSONObject.quote(accountId)

    bridge!!.callApiAsync<MStakingStateResponse>(
        "getStakingState",
        "[$quotedAccountId]",
        MStakingStateResponse::class.java
    )
}

suspend fun WalletCore.getStakingHistory(
    accountId: String,
) = run {
    val quotedAccountId = JSONObject.quote(accountId)

    bridge!!.callApiAsync<List<MStakeHistoryItem>>(
        "getStakingHistory",
        "[$quotedAccountId]",
        Types.newParameterizedType(List::class.java, MStakeHistoryItem::class.java)
    )
}

suspend fun WalletCore.submitStake(
    accountId: String,
    amount: BigInteger,
    stakingState: StakingState,
    passcode: String,
    realFee: BigInteger,
) = run {
    val quotedAccountId = JSONObject.quote(accountId)
    val quotedPasscode = JSONObject.quote(passcode)
    val stakingStateArgument = moshi.adapter(StakingState::class.java).toJson(stakingState)
    val args =
        "[$quotedAccountId,$quotedPasscode,\"bigint:$amount\",$stakingStateArgument,\"bigint:$realFee\"]"
    bridge!!.callApiAsync<ApiSubmitTransferResult>(
        "submitStake",
        args,
        ApiSubmitTransferResult::class.java
    )
}

suspend fun WalletCore.submitUnstake(
    accountId: String,
    amount: BigInteger,
    stakingState: StakingState,
    passcode: String,
    realFee: BigInteger,
) = run {
    val unstakeDraft = call(ApiMethod.Staking.CheckUnstakeDraft(accountId, amount, stakingState))
    val quotedAccountId = JSONObject.quote(accountId)
    val quotedPasscode = JSONObject.quote(passcode)
    val argumentStakingState = moshi.adapter(StakingState::class.java).toJson(stakingState)
    val args =
        "[$quotedAccountId,$quotedPasscode,\"bigint:${unstakeDraft.tokenAmount}\",$argumentStakingState,\"bigint:$realFee\"]"
    bridge!!.callApiAsync<ApiSubmitTransferResult>(
        "submitUnstake",
        args,
        ApiSubmitTransferResult::class.java
    )
}
