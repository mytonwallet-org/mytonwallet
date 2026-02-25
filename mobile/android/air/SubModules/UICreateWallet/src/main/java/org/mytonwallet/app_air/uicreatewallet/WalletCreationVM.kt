package org.mytonwallet.app_air.uicreatewallet

import android.app.Activity
import org.mytonwallet.app_air.walletbasecontext.logger.LogMessage
import org.mytonwallet.app_air.walletbasecontext.logger.Logger
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.models.MBlockchainNetwork
import org.mytonwallet.app_air.walletcontext.secureStorage.WSecureStorage
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.api.activateAccount
import org.mytonwallet.app_air.walletcore.api.importWallet
import org.mytonwallet.app_air.walletcore.models.MAccount
import org.mytonwallet.app_air.walletcore.models.MBridgeError
import org.mytonwallet.app_air.walletcore.pushNotifications.AirPushNotifications
import org.mytonwallet.app_air.walletcore.stores.BalanceStore
import org.mytonwallet.app_air.walletcore.utils.jsonObject
import java.lang.ref.WeakReference

class WalletCreationVM(delegate: Delegate) {
    interface Delegate {
        fun showError(error: MBridgeError?)
        fun finalizedCreation(createdAccount: MAccount)
    }

    val delegate: WeakReference<Delegate> = WeakReference(delegate)

    // Create and add the account into logics
    fun finalizeAccount(
        window: Activity,
        network: MBlockchainNetwork,
        words: Array<String>,
        passcode: String,
        biometricsActivated: Boolean?,
        retriesLeft: Int
    ) {
        WalletCore.importWallet(network, words, passcode, true) { account, error ->
            if (account == null || error != null) {
                if (retriesLeft > 0) {
                    finalizeAccount(window, network, words, passcode, biometricsActivated, retriesLeft - 1)
                } else {
                    delegate.get()?.showError(error)
                }
            } else {
                val createdAccountId = account.accountId
                Logger.d(
                    Logger.LogTag.ACCOUNT,
                    LogMessage.Builder()
                        .append(
                            "finalizeAccount: accountId=$createdAccountId",
                            LogMessage.MessagePartPrivacy.PUBLIC
                        )
                        .append(
                            " address=",
                            LogMessage.MessagePartPrivacy.PUBLIC
                        )
                        .append(
                            "${account.tonAddress}",
                            LogMessage.MessagePartPrivacy.REDACTED
                        ).build()
                )
                WGlobalStorage.addAccount(
                    accountId = createdAccountId,
                    accountType = MAccount.AccountType.MNEMONIC.value,
                    byChain = account.byChain.jsonObject,
                    importedAt = account.importedAt
                )
                BalanceStore.setBalances(createdAccountId, HashMap(), false)
                AirPushNotifications.subscribe(account, ignoreIfLimitReached = true)
                if (biometricsActivated != null) {
                    if (biometricsActivated) {
                        WSecureStorage.setBiometricPasscode(window, passcode)
                    } else {
                        WSecureStorage.deleteBiometricPasscode(window)
                    }
                    WGlobalStorage.setIsBiometricActivated(biometricsActivated)
                }
                WalletCore.activateAccount(account.accountId, notifySDK = false) { res, err ->
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
                        delegate.get()?.finalizedCreation(account)
                    }
                }
            }
        }
    }
}
