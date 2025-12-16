package org.mytonwallet.app_air.walletcore.models

import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.stores.AccountStore

sealed class MScreenMode {
    object Default : MScreenMode()
    data class SingleWallet(val accountId: String) : MScreenMode()

    val isScreenActive: Boolean
        get() {
            return (this == Default && !AccountStore.isPushedTemporary && WalletCore.nextAccountIsPushedTemporary != true) ||
                (this is SingleWallet && AccountStore.activeAccountId == accountId && WalletCore.nextAccountId == null)
        }
}
