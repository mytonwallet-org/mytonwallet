package org.mytonwallet.app_air.ledger.screens.ledgerWallets

import android.os.Handler
import android.os.Looper
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import org.mytonwallet.app_air.walletbasecontext.logger.LogMessage
import org.mytonwallet.app_air.walletbasecontext.logger.Logger
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.models.MBlockchainNetwork
import org.mytonwallet.app_air.walletcore.TON_CHAIN
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.api.activateAccount
import org.mytonwallet.app_air.walletcore.models.MAccount
import org.mytonwallet.app_air.walletcore.models.blockchain.MBlockchain
import org.mytonwallet.app_air.walletcore.moshi.MApiLedgerAccountInfo
import org.mytonwallet.app_air.walletcore.moshi.MApiLedgerDriver
import org.mytonwallet.app_air.walletcore.moshi.api.ApiMethod
import org.mytonwallet.app_air.walletcore.moshi.ledger.MLedgerWalletInfo
import org.mytonwallet.app_air.walletcore.pushNotifications.AirPushNotifications
import org.mytonwallet.app_air.walletcore.utils.jsonObject
import java.lang.ref.WeakReference

class LedgerWalletsVM(delegate: Delegate) {
    interface Delegate {
        fun finalizeFailed()
        fun finalizedWallets()
        fun loaded(wallets: List<MLedgerWalletInfo>)
    }

    val delegate: WeakReference<Delegate> = WeakReference(delegate)

    fun finalizeImport(
        network: MBlockchainNetwork,
        newWallets: List<MLedgerWalletInfo>
    ) {
        CoroutineScope(Dispatchers.IO).launch {
            val finalizedWallets = mutableListOf<String>()
            newWallets.forEach { newWallet ->
                try {
                    val result = WalletCore.call(
                        ApiMethod.Auth.ImportLedgerWallet(
                            network, MApiLedgerAccountInfo(
                                byChain = mapOf(
                                    TON_CHAIN to newWallet.wallet,
                                ),
                                driver = MApiLedgerDriver.HID,
                                deviceId = newWallet.deviceId,
                                deviceName = newWallet.deviceName
                            )
                        )
                    )
                    Logger.d(
                        Logger.LogTag.ACCOUNT,
                        LogMessage.Builder()
                            .append(
                                "finalizeImport: accountId=${result.accountId}",
                                LogMessage.MessagePartPrivacy.PUBLIC
                            )
                            .append(
                                " address=",
                                LogMessage.MessagePartPrivacy.PUBLIC
                            )
                            .append(
                                "${result.byChain}",
                                LogMessage.MessagePartPrivacy.REDACTED
                            ).build()
                    )
                    WGlobalStorage.addAccount(
                        accountId = result.accountId,
                        accountType = MAccount.AccountType.HARDWARE.value,
                        byChain = result.byChain.jsonObject,
                        importedAt = null,
                    )
                    finalizedWallets.add(result.accountId)
                    AirPushNotifications.subscribe(result.accountId, ignoreIfLimitReached = true)
                } catch (_: Throwable) {
                }
            }
            Handler(Looper.getMainLooper()).post {
                if (finalizedWallets.isEmpty()) {
                    delegate.get()?.finalizeFailed()
                } else {
                    /*if (addedWallets != newWallets.size) {
                    // TODO:: Handle partial added situation
                    }*/
                    WalletCore.activateAccount(
                        accountId = finalizedWallets.first(),
                        notifySDK = true
                    ) { _, err ->
                        if (err != null) {
                            // Should not happen
                            Logger.e(
                                Logger.LogTag.ACCOUNT,
                                LogMessage.Builder()
                                    .append(
                                        "activateAccount: Failed on ledger connect err=$err",
                                        LogMessage.MessagePartPrivacy.PUBLIC
                                    ).build()
                            )
                            delegate.get()?.finalizeFailed()
                            return@activateAccount
                        }
                        Handler(Looper.getMainLooper()).post {
                            delegate.get()?.finalizedWallets()
                        }
                    }
                }
            }
        }
    }

    private var isLoadingMore = false
    fun loadMore(network: MBlockchainNetwork, index: Int) {
        if (isLoadingMore)
            return
        isLoadingMore = true
        WalletCore.call(
            ApiMethod.Auth.GetLedgerWallets(
                MBlockchain.ton,
                network,
                index,
                5
            )
        ) { res, err ->
            res?.let {
                delegate.get()?.loaded(res.toList())
            } ?: run {
                delegate.get()?.finalizeFailed()
            }
            isLoadingMore = false
        }
    }

}
