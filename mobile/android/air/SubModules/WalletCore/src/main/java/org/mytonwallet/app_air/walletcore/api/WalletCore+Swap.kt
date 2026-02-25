package org.mytonwallet.app_air.walletcore.api

import com.squareup.moshi.Types
import org.json.JSONObject
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.models.blockchain.MBlockchain
import org.mytonwallet.app_air.walletcore.moshi.MApiSubmitMultiTransferResult
import org.mytonwallet.app_air.walletcore.moshi.MApiSubmitTransferOptions
import org.mytonwallet.app_air.walletcore.moshi.MApiSwapBuildRequest
import org.mytonwallet.app_air.walletcore.moshi.MApiSwapBuildResponse
import org.mytonwallet.app_air.walletcore.moshi.MApiSwapCexCreateTransactionRequest
import org.mytonwallet.app_air.walletcore.moshi.MApiSwapCexCreateTransactionResponse
import org.mytonwallet.app_air.walletcore.moshi.MApiSwapCexEstimateRequest
import org.mytonwallet.app_air.walletcore.moshi.MApiSwapCexEstimateResponse
import org.mytonwallet.app_air.walletcore.moshi.MApiSwapEstimateRequest
import org.mytonwallet.app_air.walletcore.moshi.MApiSwapEstimateResponse
import org.mytonwallet.app_air.walletcore.moshi.MApiSwapHistoryItem
import org.mytonwallet.app_air.walletcore.moshi.MApiSwapPairAsset
import org.mytonwallet.app_air.walletcore.moshi.MApiSwapTransfer
import org.mytonwallet.app_air.walletcore.moshi.MSwapCexValidateAddressParams
import org.mytonwallet.app_air.walletcore.moshi.MSwapCexValidateAddressResult

/*
suspend fun WalletCore.Swap.swapGetAssets() =
    WalletCore.bridge!!.callApiAsync<List<ApiSwapAsset>>(
        "swapGetAssets",
        "[]",
        Types.newParameterizedType(List::class.java, ApiSwapAsset::class.java))
*/

suspend fun swapGetPairs(slug: String) =
    WalletCore.bridge!!.callApiAsync<List<MApiSwapPairAsset>>(
        "swapGetPairs",
        ArgumentsBuilder()
            .string(slug)
            .build(),
        Types.newParameterizedType(List::class.java, MApiSwapPairAsset::class.java)
    )

suspend fun WalletCore.Swap.swapEstimate(
    accountId: String,
    request: MApiSwapEstimateRequest
) = run {
    WalletCore.bridge!!.callApiAsync<MApiSwapEstimateResponse>(
        "swapEstimate",
        ArgumentsBuilder()
            .string(accountId)
            .jsObject(request, MApiSwapEstimateRequest::class.java)
            .build(),
        MApiSwapEstimateResponse::class.java
    )
}

suspend fun WalletCore.Swap.swapCexEstimate(request: MApiSwapCexEstimateRequest) = run {
    WalletCore.bridge!!.callApiAsync<MApiSwapCexEstimateResponse>(
        "swapCexEstimate",
        ArgumentsBuilder()
            .jsObject(request, MApiSwapCexEstimateRequest::class.java)
            .build(),
        MApiSwapCexEstimateResponse::class.java
    )
}

suspend fun WalletCore.Swap.swapCexCreateTransaction(
    accountId: String,
    passcode: String,
    request: MApiSwapCexCreateTransactionRequest
) = run {
    val moshi = WalletCore.moshi
    val arg = moshi.adapter(MApiSwapCexCreateTransactionRequest::class.java).toJson(request)

    val quotedAccountId = JSONObject.quote(accountId)
    val quotedPasscode = JSONObject.quote(passcode)

    WalletCore.bridge!!.callApiAsync<MApiSwapCexCreateTransactionResponse>(
        "swapCexCreateTransaction",
        "[$quotedAccountId,$quotedPasscode,$arg]",
        MApiSwapCexCreateTransactionResponse::class.java
    )
}

suspend fun WalletCore.Swap.swapBuildTransfer(
    accountId: String,
    passcode: String,
    request: MApiSwapBuildRequest
) = run {
    val moshi = WalletCore.moshi
    val arg = moshi.adapter(MApiSwapBuildRequest::class.java).toJson(request)

    val quotedAccountId = JSONObject.quote(accountId)
    val quotedPasscode = JSONObject.quote(passcode)

    WalletCore.bridge!!.callApiAsync<MApiSwapBuildResponse>(
        "swapBuildTransfer",
        "[$quotedAccountId,$quotedPasscode,$arg]",
        MApiSwapBuildResponse::class.java
    )
}

suspend fun WalletCore.Swap.swapSubmit(
    accountId: String,
    passcode: String,
    transfers: List<MApiSwapTransfer>,
    historyItem: MApiSwapHistoryItem,
    withDiesel: Boolean
) = run {
    val moshi = WalletCore.moshi
    val argT = moshi.adapter<List<MApiSwapTransfer>>(
        Types.newParameterizedType(
            List::class.java,
            MApiSwapTransfer::class.java
        )
    )
        .toJson(transfers)
    val argH = moshi.adapter(MApiSwapHistoryItem::class.java)
        .toJson(historyItem)

    val quotedAccountId = JSONObject.quote(accountId)
    val quotedPasscode = JSONObject.quote(passcode)

    WalletCore.bridge!!.callApiAsync<MApiSubmitMultiTransferResult>(
        "swapSubmit",
        "[$quotedAccountId,$quotedPasscode,$argT,$argH,$withDiesel]",
        MApiSubmitMultiTransferResult::class.java
    )
}

suspend fun WalletCore.Swap.swapCexValidateAddress(params: MSwapCexValidateAddressParams) = run {
    WalletCore.bridge!!.callApiAsync<MSwapCexValidateAddressResult>(
        "swapCexValidateAddress",
        ArgumentsBuilder()
            .jsObject(params, MSwapCexValidateAddressParams::class.java)
            .build(),
        MSwapCexValidateAddressResult::class.java
    )
}

suspend fun WalletCore.Transfer.swapCexSubmit(
    chain: MBlockchain,
    options: MApiSubmitTransferOptions,
    swapId: String
): Any = run {
    val moshi = WalletCore.moshi
    val arg = moshi.adapter(MApiSubmitTransferOptions::class.java).toJson(options)
    val args = "[\"${chain.name}\", $arg, ${JSONObject.quote(swapId)}]"

    WalletCore.bridge!!.callApiAsync("swapCexSubmit", args, Any::class.java)
}
