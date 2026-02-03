package org.mytonwallet.app_air.uicreatewallet.viewControllers.importWallet

import android.app.Activity
import android.os.Handler
import android.os.Looper
import org.mytonwallet.app_air.walletbasecontext.logger.LogMessage
import org.mytonwallet.app_air.walletbasecontext.logger.Logger
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.models.MBlockchainNetwork
import org.mytonwallet.app_air.walletcontext.secureStorage.WSecureStorage
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.api.importWallet
import org.mytonwallet.app_air.walletcore.api.validateMnemonic
import org.mytonwallet.app_air.walletcore.models.MAccount
import org.mytonwallet.app_air.walletcore.models.MBridgeError
import org.mytonwallet.app_air.walletcore.pushNotifications.AirPushNotifications
import java.lang.ref.WeakReference


class ImportWalletVM(delegate: Delegate) {
    interface Delegate {
        fun walletCanBeImported(words: Array<String>)
        fun finalizedImport(accountId: String)
        fun showError(error: MBridgeError?)
    }

    val delegate: WeakReference<Delegate> = WeakReference(delegate)

    // Called to import a wallet into js-logic accounts
    fun importWallet(words: Array<String>) {
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
        passcode: String,
        biometricsActivated: Boolean?,
        retriesLeft: Int = 3
    ) {
        WalletCore.importWallet(network, words, passcode, false) { importedAccount, error ->
            if (error != null) {
                if (retriesLeft > 0) {
                    Handler(Looper.getMainLooper()).postDelayed({
                        finalizeAccount(
                            window,
                            network,
                            words,
                            passcode,
                            biometricsActivated,
                            retriesLeft - 1
                        )
                    }, 3000)
                } else {
                    delegate.get()?.showError(error)
                }
            } else {
                val importedAccountId = importedAccount?.accountId ?: return@importWallet
                Logger.d(
                    Logger.LogTag.ACCOUNT,
                    LogMessage.Builder()
                        .append(
                            "finalizeAccount: accountId=$importedAccountId",
                            LogMessage.MessagePartPrivacy.PUBLIC
                        )
                        .append(
                            " address=",
                            LogMessage.MessagePartPrivacy.PUBLIC
                        )
                        .append(
                            "${importedAccount.tonAddress}",
                            LogMessage.MessagePartPrivacy.REDACTED
                        ).build()
                )
                WGlobalStorage.addAccount(
                    accountId = importedAccountId,
                    accountType = MAccount.AccountType.MNEMONIC.value,
                    importedAccount.tonAddress,
                    importedAccount.tronAddress,
                    importedAt = importedAccount.importedAt
                )
                AirPushNotifications.subscribe(importedAccount, ignoreIfLimitReached = true)
                if (biometricsActivated != null) {
                    if (biometricsActivated) {
                        WSecureStorage.setBiometricPasscode(window, passcode)
                    } else {
                        WSecureStorage.deleteBiometricPasscode(window)
                    }
                    WGlobalStorage.setIsBiometricActivated(biometricsActivated)
                }
                delegate.get()?.finalizedImport(importedAccountId)
            }
        }
    }
}
