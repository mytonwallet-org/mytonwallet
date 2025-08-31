package org.mytonwallet.app_air.walletcore.moshi.ledger

import com.squareup.moshi.JsonClass
import java.math.BigInteger

@JsonClass(generateAdapter = true)
data class MLedgerReadyToSignTransferData(
    val path: List<Int>,
    val normalizedAddress: String,
    val fromAddress: String,
    val comment: String?,
    val accountId: String,
    val realFee: BigInteger?,
    val pendingTransferId: String,
    val transaction: MLedgerReadyToSignTransaction
)
