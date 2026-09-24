@file:Suppress("ktlint:standard:backing-property-naming")

package org.mytonwallet.app_air.uisettings.viewControllers.connectedApps

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.filterNotNull
import kotlinx.coroutines.launch
import org.mytonwallet.app_air.uicomponents.adapter.BaseListItem
import org.mytonwallet.app_air.walletcore.JSWebViewBridge
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.models.MBridgeError
import org.mytonwallet.app_air.walletcore.moshi.ApiDapp
import org.mytonwallet.app_air.walletcore.moshi.api.ApiMethod
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import org.mytonwallet.app_air.walletcore.stores.DappsStore

class ConnectedAppsViewModel :
    ViewModel(),
    WalletCore.EventObserver {
    private val _accountIdFlow = MutableStateFlow(AccountStore.activeAccountId)
    private val _errorFlow = MutableSharedFlow<MBridgeError?>(extraBufferCapacity = 1)
    val errorFlow = _errorFlow.asSharedFlow()

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
        DappsStore.refresh()
    }

    override fun onCleared() {
        WalletCore.unregisterObserver(this)
        super.onCleared()
    }

    fun deleteConnectedApp(dapp: ApiDapp, onSuccess: (() -> Unit)? = null) {
        val accountId = _accountIdFlow.value ?: return
        val url = dapp.url ?: return
        val uniqueId = dapp.connectionUniqueId
        viewModelScope.launch {
            var deletionError: MBridgeError? = null
            try {
                WalletCore.call(ApiMethod.DApp.DeleteDapp(accountId, url, uniqueId))
            } catch (e: JSWebViewBridge.ApiError) {
                deletionError = e.parsed
            } catch (_: IllegalArgumentException) {
                deletionError = MBridgeError.Type.UNKNOWN
            }

            val dapps = try {
                DappsStore.refreshNow(accountId)
            } catch (e: JSWebViewBridge.ApiError) {
                if (_accountIdFlow.value == accountId) _errorFlow.emit(e.parsed)
                return@launch
            } catch (_: IllegalArgumentException) {
                if (_accountIdFlow.value == accountId) _errorFlow.emit(null)
                return@launch
            }

            if (_accountIdFlow.value != accountId) return@launch
            if (dapps.any { it.url == url && it.connectionUniqueId == uniqueId }) {
                _errorFlow.emit(deletionError)
            } else {
                WalletCore.notifyEvent(WalletEvent.DappRemoved(dapp))
                onSuccess?.invoke()
            }
        }
    }

    fun deleteAllConnectedApp() {
        val accountId = _accountIdFlow.value ?: return
        viewModelScope.launch {
            var deletionError: MBridgeError? = null
            try {
                WalletCore.call(ApiMethod.DApp.DeleteAllDapps(accountId))
            } catch (e: JSWebViewBridge.ApiError) {
                deletionError = e.parsed
            } catch (_: IllegalArgumentException) {
                deletionError = MBridgeError.Type.UNKNOWN
            }

            val dapps = try {
                DappsStore.refreshNow(accountId)
            } catch (e: JSWebViewBridge.ApiError) {
                if (_accountIdFlow.value == accountId) _errorFlow.emit(e.parsed)
                return@launch
            } catch (_: IllegalArgumentException) {
                if (_accountIdFlow.value == accountId) _errorFlow.emit(null)
                return@launch
            }

            if (_accountIdFlow.value == accountId && dapps.isNotEmpty()) {
                _errorFlow.emit(deletionError)
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
