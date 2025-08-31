package org.mytonwallet.app_air.walletcore.moshi.ledger

import com.squareup.moshi.JsonClass
import java.math.BigInteger

@JsonClass(generateAdapter = true)
data class MLedgerReadyToSignTransaction(
    val to: String?,
    val sendMode: Int,
    val seqno: Int,
    val timeout: Long,
    val bounce: Boolean,
    val amount: BigInteger,
    val payload: Map<String, Any?>?,
    val walletSpecifiers: Map<String, Any?>?
)
