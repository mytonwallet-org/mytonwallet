package org.mytonwallet.app_air.ledger.connectionManagers

import org.mytonwallet.app_air.ledger.LedgerManager
import org.mytonwallet.app_air.walletcore.models.LedgerAppInfo

interface ILedgerConnectionManager {
    fun startConnection(onUpdate: (LedgerManager.ConnectionState) -> Unit)
    fun stopConnection()

    fun getPublicKey(walletIndex: Int, onCompletion: (publicKey: List<Int>?) -> Unit)
    fun appInfo(): LedgerAppInfo
    fun write(
        apdu: String,
        onSuccess: (String) -> Unit,
        onError: (String) -> Unit
    )
}
