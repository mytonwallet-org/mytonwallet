package org.mytonwallet.app_air.uipasscode

import kotlinx.coroutines.launch
import org.mytonwallet.app_air.walletbasecontext.logger.Logger
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import org.mytonwallet.app_air.walletcore.stores.AuthStore

object ProtectedActionAuth {
    fun confirm(onConfirmed: (String) -> Unit, onPasscodeRequired: () -> Unit): Boolean {
        if (!WalletCore.isBridgeReady) return false
        val token = AuthStore.getAutoConfirmToken()
        if (token == null) {
            onPasscodeRequired()
        } else {
            refreshMfa()
            onConfirmed(token)
        }
        return true
    }

    fun refreshMfa() {
        AccountStore.activeAccountId?.let { accountId ->
            WalletCore.scope.launch {
                try {
                    AccountStore.refreshMfa(accountId)
                } catch (t: Throwable) {
                    Logger.e(
                        Logger.LogTag.PASSCODE_CONFIRM,
                        "refreshStoredMfa before protected action failed: $t"
                    )
                }
            }
        }
    }
}
