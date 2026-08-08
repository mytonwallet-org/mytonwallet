package org.mytonwallet.app_air.walletcore.moshi.ledger

import com.squareup.moshi.JsonClass
import java.math.BigInteger
import org.mytonwallet.app_air.walletcore.models.MAccount

@JsonClass(generateAdapter = true)
data class MLedgerWalletInfo(
    val balance: BigInteger,
    val wallet: WalletItem,
    val driver: MAccount.Ledger.Driver,
    val deviceId: String?,
    val deviceName: String?
) {
    @JsonClass(generateAdapter = true)
    data class WalletItem(
        val index: Int,
        val address: String,
        val publicKey: String?,

        val version: String,
        val isInitialized: Boolean?,
        val authToken: String?
    )
}
