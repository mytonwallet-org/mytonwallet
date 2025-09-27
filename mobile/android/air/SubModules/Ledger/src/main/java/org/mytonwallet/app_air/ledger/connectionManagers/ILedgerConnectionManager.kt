package org.mytonwallet.app_air.ledger.connectionManagers

import org.mytonwallet.app_air.ledger.LedgerManager

interface ILedgerConnectionManager {
    fun startConnection(onUpdate: (LedgerManager.ConnectionState) -> Unit)
    fun stopConnection()

    fun write(
        apdu: String,
        onSuccess: (String) -> Unit,
        onError: (String) -> Unit
    )
}
