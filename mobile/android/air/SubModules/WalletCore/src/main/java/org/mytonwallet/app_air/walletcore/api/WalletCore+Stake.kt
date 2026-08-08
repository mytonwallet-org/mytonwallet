@file:Suppress("ktlint:standard:filename")

package org.mytonwallet.app_air.walletcore.api

import com.squareup.moshi.Types
import java.math.BigInteger
import org.json.JSONObject
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.moshi.ApiSubmitTransferResult
import org.mytonwallet.app_air.walletcore.moshi.MStakeHistoryItem
import org.mytonwallet.app_air.walletcore.moshi.MStakingStateResponse
import org.mytonwallet.app_air.walletcore.moshi.StakingState
import org.mytonwallet.app_air.walletcore.moshi.api.ApiMethod

suspend fun WalletCore.getBackendStakingState(accountId: String) = run {
    val quotedAccountId = JSONObject.quote(accountId)

    requiredBridge.callApiAsync<MStakingStateResponse>(
        "getStakingState",
        "[$quotedAccountId]",
        MStakingStateResponse::class.java
    )
}

suspend fun WalletCore.getStakingHistory(accountId: String) = run {
    val quotedAccountId = JSONObject.quote(accountId)

    requiredBridge.callApiAsync<List<MStakeHistoryItem>>(
        "getStakingHistory",
        "[$quotedAccountId]",
        Types.newParameterizedType(List::class.java, MStakeHistoryItem::class.java)
    )
}

suspend fun WalletCore.submitStake(
    accountId: String,
    amount: BigInteger,
    stakingState: StakingState,
    enclaveToken: String,
    realFee: BigInteger
) = run {
    val quotedAccountId = JSONObject.quote(accountId)
    val quotedEnclaveToken = JSONObject.quote(enclaveToken)
    val stakingStateArgument = moshi.adapter(StakingState::class.java).toJson(stakingState)
    val args =
        "[$quotedAccountId,$quotedEnclaveToken,\"bigint:$amount\",$stakingStateArgument,\"bigint:$realFee\"]"
    requiredBridge.callApiAsync<ApiSubmitTransferResult>(
        "submitStake",
        args,
        ApiSubmitTransferResult::class.java
    )
}

suspend fun WalletCore.submitUnstake(
    accountId: String,
    amount: BigInteger,
    stakingState: StakingState,
    enclaveToken: String,
    realFee: BigInteger
) = run {
    val unstakeDraft = call(ApiMethod.Staking.CheckUnstakeDraft(accountId, amount, stakingState))
    val quotedAccountId = JSONObject.quote(accountId)
    val quotedEnclaveToken = JSONObject.quote(enclaveToken)
    val argumentStakingState = moshi.adapter(StakingState::class.java).toJson(stakingState)
    val args =
        "[$quotedAccountId,$quotedEnclaveToken,\"bigint:${unstakeDraft.tokenAmount}\",$argumentStakingState,\"bigint:$realFee\"]"
    requiredBridge.callApiAsync<ApiSubmitTransferResult>(
        "submitUnstake",
        args,
        ApiSubmitTransferResult::class.java
    )
}
