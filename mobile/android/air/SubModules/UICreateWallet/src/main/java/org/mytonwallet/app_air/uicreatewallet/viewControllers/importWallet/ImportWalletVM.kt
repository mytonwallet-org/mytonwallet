package org.mytonwallet.app_air.uicreatewallet.viewControllers.importWallet

import android.app.Activity
import android.os.Handler
import android.os.Looper
import java.lang.ref.WeakReference
import org.mytonwallet.app_air.walletbasecontext.logger.LogMessage
import org.mytonwallet.app_air.walletbasecontext.logger.Logger
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.models.MBlockchainNetwork
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.api.enclaveImportSecrets
import org.mytonwallet.app_air.walletcore.api.importPrivateKey
import org.mytonwallet.app_air.walletcore.api.importWallet
import org.mytonwallet.app_air.walletcore.api.refreshStoredMfaIfPossible
import org.mytonwallet.app_air.walletcore.api.validateMnemonic
import org.mytonwallet.app_air.walletcore.helpers.PrivateKeyHelper
import org.mytonwallet.app_air.walletcore.models.MAccount
import org.mytonwallet.app_air.walletcore.models.MBridgeError
import org.mytonwallet.app_air.walletcore.pushNotifications.AirPushNotifications
import org.mytonwallet.app_air.walletcore.utils.jsonObject

class ImportWalletVM(delegate: Delegate) {
    interface Delegate {
        fun walletCanBeImported(words: Array<String>)
        fun finalizedImport(accountId: String, importedAccountsCount: Int)
        fun showError(error: MBridgeError?)
    }

    val delegate: WeakReference<Delegate> = WeakReference(delegate)

    // Called to import a wallet into js-logic accounts
    fun importWallet(words: Array<String>) {
        val privateKeyWords = PrivateKeyHelper.normalizeMnemonicPrivateKey(words)
        if (privateKeyWords != null) {
            delegate.get()?.walletCanBeImported(privateKeyWords)
            return
        }
        WalletCore.doOnBridgeReady {
            WalletCore.validateMnemonic(words) { success, error ->
                if (!success || error != null) {
                    delegate.get()?.showError(error)
                } else {
                    delegate.get()?.walletCanBeImported(words)
                }
            }
        }
    }

    // Add the account into logics
    fun finalizeAccount(
        window: Activity,
        network: MBlockchainNetwork,
        words: Array<String>,
        biometricsActivated: Boolean?,
        retriesLeft: Int = 3,
        enclaveToken: String
    ) {
        fun onResult(importedAccounts: List<MAccount>?, error: MBridgeError?) {
            if (error != null) {
                if (retriesLeft > 0) {
                    Handler(Looper.getMainLooper()).postDelayed({
                        finalizeAccount(
                            window,
                            network,
                            words,
                            biometricsActivated,
                            retriesLeft - 1,
                            enclaveToken
                        )
                    }, 3000)
                } else {
                    delegate.get()?.showError(error)
                }
                return
            }
            val primaryAccount = importedAccounts?.firstOrNull() ?: return
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
                importedAccounts.map { it.accountId },
                secret,
                enclaveToken
            )
            if (importError != null) {
                delegate.get()?.showError(importError)
                return
            }
            importedAccounts.forEach { account ->
                WGlobalStorage.addAccount(
                    accountId = account.accountId,
                    accountType = MAccount.AccountType.MNEMONIC.value,
                    byChain = account.byChain.jsonObject,
                    importedAt = account.importedAt
                )
                AirPushNotifications.subscribe(account, ignoreIfLimitReached = true)
            }
            WalletCore.refreshStoredMfaIfPossible(
                importedAccounts.map { it.accountId },
                enclaveToken
            )
            delegate.get()?.finalizedImport(primaryAccount.accountId, importedAccounts.size)
        }

        val privateKeyWords = PrivateKeyHelper.normalizeMnemonicPrivateKey(words)
        if (privateKeyWords != null) {
            WalletCore.importPrivateKey(network, privateKeyWords[0]) { account, error ->
                onResult(account?.let { listOf(it) }, error)
            }
        } else {
            WalletCore.importWallet(network, words, false) { accounts, error ->
                onResult(accounts, error)
            }
        }
    }
}
