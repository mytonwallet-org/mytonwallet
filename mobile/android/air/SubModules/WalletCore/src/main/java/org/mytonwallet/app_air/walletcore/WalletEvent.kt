package org.mytonwallet.app_air.walletcore

import org.json.JSONObject
import org.mytonwallet.app_air.walletcore.moshi.ApiDapp
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

    data object NftsUpdated : WalletEvent()
    data object ReceivedNewNFT : WalletEvent()
    data class AccountChanged(
        val accountId: String? = null
    ) : WalletEvent()

    data object AccountNameChanged : WalletEvent()
    data object AccountSavedAddressesChanged : WalletEvent()
    data object AddNewWalletCompletion : WalletEvent()
    data object AccountChangedInApp : WalletEvent()
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
}
