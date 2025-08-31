package org.mytonwallet.app_air.walletcore.moshi.ledger

import com.squareup.moshi.JsonClass

@JsonClass(generateAdapter = true)
data class MLedgerReadyToSignNftTransferData(
    val path: List<Int>,
    val fromAddress: String,
    val comment: String?,
    val accountId: String,
    val pendingTransferId: String,
    val transaction: MLedgerReadyToSignTransaction
)
