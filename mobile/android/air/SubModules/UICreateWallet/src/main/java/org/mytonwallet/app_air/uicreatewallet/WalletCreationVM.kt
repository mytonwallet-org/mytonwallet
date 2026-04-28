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
        fun finalizedCreation(createdAccount: MAccount, importedAccountsCount: Int)
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
        WalletCore.importWallet(network, words, passcode, true) { accounts, error ->
            if (accounts.isNullOrEmpty() || error != null) {
                if (retriesLeft > 0) {
                    finalizeAccount(
                        window,
                        network,
                        words,
                        passcode,
                        biometricsActivated,
                        retriesLeft - 1
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
                accounts.forEach { account ->
                    WGlobalStorage.addAccount(
                        accountId = account.accountId,
                        accountType = MAccount.AccountType.MNEMONIC.value,
                        byChain = account.byChain.jsonObject,
                        importedAt = account.importedAt
                    )
                    BalanceStore.setBalances(account.accountId, HashMap(), false)
                    AirPushNotifications.subscribe(account, ignoreIfLimitReached = true)
                }
                if (biometricsActivated != null) {
                    if (biometricsActivated) {
                        val activated = WSecureStorage.setBiometricPasscode(window, passcode)
                        WGlobalStorage.setIsBiometricActivated(activated)
                    } else {
                        WSecureStorage.deleteBiometricPasscode(window)
                        WGlobalStorage.setIsBiometricActivated(false)
                    }
                }
                WalletCore.activateAccount(primaryAccount.accountId, notifySDK = false) { res, err ->
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
