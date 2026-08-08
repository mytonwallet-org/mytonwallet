package org.mytonwallet.app_air.walletcore.helpers

import android.app.Activity
import java.lang.ref.WeakReference
import java.math.BigInteger
import org.mytonwallet.app_air.walletbasecontext.logger.LogMessage
import org.mytonwallet.app_air.walletbasecontext.logger.Logger
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.models.MBlockchainNetwork
import org.mytonwallet.app_air.walletcore.ALL_DEFAULT_TOKENS
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.api.activateAccount
import org.mytonwallet.app_air.walletcore.api.enclaveImportSecrets
import org.mytonwallet.app_air.walletcore.api.importWallet
import org.mytonwallet.app_air.walletcore.models.MAccount
import org.mytonwallet.app_air.walletcore.models.MBridgeError
import org.mytonwallet.app_air.walletcore.pushNotifications.AirPushNotifications
import org.mytonwallet.app_air.walletcore.stores.BalanceStore
import org.mytonwallet.app_air.walletcore.utils.jsonObject

class WalletCreationVM(delegate: Delegate) {
    interface Delegate {
        fun showError(error: MBridgeError?)
        fun finalizedCreation(createdAccount: MAccount, importedAccountsCount: Int)
    }

    val delegate: WeakReference<Delegate> = WeakReference(delegate)

    // Create and add the account into logics
    fun finalizeAccount(
        window: Activity,
        network: MBlockchainNetwork,
        words: Array<String>,
        retriesLeft: Int,
        enclaveToken: String
    ) {
        WalletCore.importWallet(network, words, true) { accounts, error ->
            if (accounts.isNullOrEmpty() || error != null) {
                if (retriesLeft > 0) {
                    finalizeAccount(
                        window,
                        network,
                        words,
                        retriesLeft - 1,
                        enclaveToken
                    )
                } else {
                    delegate.get()?.showError(error)
                }
            } else {
                val primaryAccount = accounts[0]
                Logger.d(
                    Logger.LogTag.ACCOUNT,
                    LogMessage.Builder()
                        .append(
                            "finalizeAccount: accountId=${primaryAccount.accountId}",
                            LogMessage.MessagePartPrivacy.PUBLIC
                        )
                        .append(
                            " address=",
                            LogMessage.MessagePartPrivacy.PUBLIC
                        )
                        .append(
                            "${primaryAccount.tonAddress}",
                            LogMessage.MessagePartPrivacy.REDACTED
                        ).build()
                )
                val secret = words.joinToString(" ")
                val importError = WalletCore.enclaveImportSecrets(
                    accounts.map { it.accountId },
                    secret,
                    enclaveToken
                )
                if (importError != null) {
                    delegate.get()?.showError(importError)
                    return@importWallet
                }
                accounts.forEach { account ->
                    WGlobalStorage.addAccount(
                        accountId = account.accountId,
                        accountType = MAccount.AccountType.MNEMONIC.value,
                        byChain = account.byChain.jsonObject,
                        importedAt = account.importedAt
                    )
                    WGlobalStorage.setIsHistoryEndReached(account.accountId, null, true)
                    val seededBalances = HashMap<String, BigInteger>().apply {
                        ALL_DEFAULT_TOKENS[account.network]?.forEach { slug ->
                            put(slug, BigInteger.ZERO)
                        }
                    }
                    BalanceStore.setBalances(account.accountId, seededBalances, true)
                    AirPushNotifications.subscribe(account, ignoreIfLimitReached = true)
                }
                WalletCore.activateAccount(
                    primaryAccount.accountId,
                    notifySDK = false
                ) { res, err ->
                    if (res == null || err != null) {
                        // Should not happen!
                        Logger.e(
                            Logger.LogTag.ACCOUNT,
                            LogMessage.Builder()
                                .append(
                                    "activateAccount: Failed after wallet creation err=$err",
                                    LogMessage.MessagePartPrivacy.PUBLIC
                                ).build()
                        )
                    } else {
                        delegate.get()?.finalizedCreation(primaryAccount, accounts.size)
                    }
                }
            }
        }
    }
}
