package org.mytonwallet.app_air.uisettings.viewControllers.connectedApps

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.filterNotNull
import kotlinx.coroutines.launch
import org.mytonwallet.app_air.uicomponents.adapter.BaseListItem
import org.mytonwallet.app_air.walletcore.JSWebViewBridge
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.api.requestDAppList
import org.mytonwallet.app_air.walletcore.moshi.ApiDapp
import org.mytonwallet.app_air.walletcore.moshi.api.ApiMethod
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import org.mytonwallet.app_air.walletcore.stores.DappsStore

class ConnectedAppsViewModel : ViewModel(), WalletCore.EventObserver {
    private val _accountIdFlow = MutableStateFlow(AccountStore.activeAccountId)

    val uiItemsFlow =
        combine(_accountIdFlow, DappsStore.dAppsFlow, ::buildUiItems)
            .filterNotNull()

    override fun onWalletEvent(walletEvent: WalletEvent) {
        if (walletEvent is WalletEvent.AccountChanged) {
            _accountIdFlow.value = walletEvent.accountId
        }
    }

    init {
        WalletCore.registerObserver(this)
        WalletCore.requestDAppList()
    }

    override fun onCleared() {
        WalletCore.unregisterObserver(this)
        super.onCleared()
    }


    fun deleteConnectedApp(dapp: ApiDapp) {
        val accountId = _accountIdFlow.value ?: return
        viewModelScope.launch {
            try {
                dapp.url?.let { dappUrl ->
                    WalletCore.call(
                        ApiMethod.DApp.DeleteDapp(
                            accountId,
                            dapp.sse?.appClientId ?: "jsbridge",
                            dappUrl,
                        )
                    )
                }
                WalletCore.notifyEvent(WalletEvent.DappRemoved(dapp))
                WalletCore.requestDAppList()
            } catch (_: JSWebViewBridge.ApiError) {

            } catch (_: IllegalArgumentException) {

            }
        }
    }

    fun deleteAllConnectedApp() {
        val accountId = _accountIdFlow.value ?: return
        viewModelScope.launch {
            try {
                WalletCore.call(ApiMethod.DApp.DeleteAllDapps(accountId))
                WalletCore.requestDAppList()
            } catch (e: JSWebViewBridge.ApiError) {

            } catch (e: IllegalArgumentException) {

            }
        }
    }

    private fun buildUiItems(
        accountId: String?,
        dApps: Map<String, List<ApiDapp>>?
    ): List<BaseListItem>? {
        val accId = accountId ?: return null
        val dAppsList = dApps?.get(accId) ?: return null

        val list: MutableList<BaseListItem> = dAppsList.mapIndexed { index, apiDapp ->
            Item.DApp(
                app = apiDapp,
                isLastItem = index == dAppsList.size - 1
            )
        }.toMutableList()
        list.add(0, Item.Header(""))
        return list
    }
}
