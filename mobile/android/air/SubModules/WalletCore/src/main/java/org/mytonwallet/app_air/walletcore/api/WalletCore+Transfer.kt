package org.mytonwallet.app_air.walletcore.api

import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.models.blockchain.MBlockchain
import org.mytonwallet.app_air.walletcore.moshi.MApiCheckTransactionDraftOptions
import org.mytonwallet.app_air.walletcore.moshi.MApiCheckTransactionDraftResult

suspend fun WalletCore.Transfer.checkTransactionDraft(
    chain: MBlockchain,
    options: MApiCheckTransactionDraftOptions
) = run {
    val moshi = WalletCore.moshi
    val arg = moshi.adapter(MApiCheckTransactionDraftOptions::class.java).toJson(options)

    WalletCore.bridge!!.callApiAsync<MApiCheckTransactionDraftResult>(
        "checkTransactionDraft",
        "[\"${chain.name}\", $arg]",
        MApiCheckTransactionDraftResult::class.java
    )
}
