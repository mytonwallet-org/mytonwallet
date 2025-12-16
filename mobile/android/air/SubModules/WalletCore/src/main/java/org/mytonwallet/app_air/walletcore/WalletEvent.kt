package org.mytonwallet.app_air.walletcore

import org.json.JSONObject
import org.mytonwallet.app_air.walletcore.moshi.ApiDapp
import org.mytonwallet.app_air.walletcore.moshi.ApiNft
import org.mytonwallet.app_air.walletcore.moshi.MApiTransaction

sealed class WalletEvent {
    data object UpdatingStatusChanged : WalletEvent()
    data object BalanceChanged : WalletEvent()
    data object NotActiveAccountBalanceChanged : WalletEvent()

    data object TokensChanged : WalletEvent()

    data object BaseCurrencyChanged : WalletEvent()

    data class ReceivedNewActivities(
        val accountId: String? = null,
        val newActivities: List<MApiTransaction>? = null,
        val isUpdateEvent: Boolean? = null,
        val loadedAll: Boolean?
    ) : WalletEvent()

    data class ReceivedPendingActivities(
        val accountId: String? = null,
        val pendingActivities: List<MApiTransaction>? = null,
    ) : WalletEvent()

    data object NftsUpdated : WalletEvent()
    data class CollectionNftsReceived(
        val accountId: String,
        val collectionAddress: String,
        val nfts: List<ApiNft>
    ) : WalletEvent()

    data object ReceivedNewNFT : WalletEvent()

    // TODO:: Merge these 2 account change events
    data class AccountChanged(
        val accountId: String? = null,
        val fromHome: Boolean = false,
        val isSavingTemporaryAccount: Boolean = false,
    ) : WalletEvent()

    data class AccountChangedInApp(val persistedAccountsModified: Boolean) : WalletEvent()

    data class AccountRemoved(val accountId: String) : WalletEvent()

    data object AccountNameChanged : WalletEvent()
    data object AccountsReordered : WalletEvent()
    data object AccountSavedAddressesChanged : WalletEvent()
    data object AddNewWalletCompletion : WalletEvent()
    data class TemporaryAccountSaved(val accountId: String) : WalletEvent()
    data object AccountWillChange : WalletEvent()
    data object DappsCountUpdated : WalletEvent()
    data class DappRemoved(val dapp: ApiDapp) : WalletEvent()
    data object StakingDataUpdated : WalletEvent()
    data object AssetsAndActivityDataUpdated : WalletEvent()
    data object HideTinyTransfersChanged : WalletEvent()
    data object NetworkConnected : WalletEvent()
    data object NetworkDisconnected : WalletEvent()
    data class InvalidateCache(
        val accountId: String? = null,
        val tokenSlug: String? = null
    ) : WalletEvent()

    data class OpenUrl(
        val url: String
    ) : WalletEvent()

    data class OpenActivity(
        val activity: MApiTransaction
    ) : WalletEvent()

    data object NftCardUpdated : WalletEvent()
    data object NftDomainDataUpdated : WalletEvent()
    data class LedgerDeviceModelRequest(
        val onResponse: (response: JSONObject?) -> Unit
    ) : WalletEvent()

    data class LedgerWriteRequest(
        val apdu: String,
        val onResponse: (response: String?) -> Unit
    ) : WalletEvent()

    data object ConfigReceived : WalletEvent()
    data object AccountConfigReceived : WalletEvent()

    data object NftsReordered : WalletEvent()
    data object HomeNftCollectionsUpdated : WalletEvent()
    data object ByChainUpdated : WalletEvent()
}
