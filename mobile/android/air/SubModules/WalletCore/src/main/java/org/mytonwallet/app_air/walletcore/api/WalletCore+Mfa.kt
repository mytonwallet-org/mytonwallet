package org.mytonwallet.app_air.walletcore.api

import android.util.Log
import kotlinx.coroutines.launch
import org.mytonwallet.app_air.walletbasecontext.logger.Logger
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.moshi.api.ApiMethod
import org.mytonwallet.app_air.walletcore.stores.AccountStore

suspend fun WalletCore.refreshStoredMfa(accountId: String, password: String? = null) {
    val result = WalletCore.call(ApiMethod.Mfa.RefreshMfaState(accountId, password))
    AccountStore.updateMfa(accountId, result.mfa)
}

fun WalletCore.refreshStoredMfaIfPossible(
    accountIds: Iterable<String>,
    password: String?,
) {
    scope.launch {
        for (accountId in accountIds) {
            try {
                refreshStoredMfa(accountId, password)
            } catch (t: Throwable) {
                Logger.e(
                    Logger.LogTag.WALLET_CORE,
                    "refreshStoredMfa failed for imported account $accountId: $t",
                )
            }
        }
    }
}
