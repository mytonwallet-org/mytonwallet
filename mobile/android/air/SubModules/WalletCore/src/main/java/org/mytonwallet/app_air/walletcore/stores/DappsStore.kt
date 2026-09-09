package org.mytonwallet.app_air.walletcore.stores

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.moshi.ApiDapp
import org.mytonwallet.app_air.walletcore.moshi.api.ApiMethod

object DappsStore : IStore {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    // Observable Flow
    private val _dAppsFlow = MutableStateFlow<Map<String, List<ApiDapp>>>(emptyMap())
    val dApps get() = _dAppsFlow.value
    val dAppsFlow = _dAppsFlow.asStateFlow()
    fun setDapps(accountId: String, apps: List<ApiDapp>) {
        _dAppsFlow.value = _dAppsFlow.value.toMutableMap().apply {
            put(accountId, apps)
        }
    }
    // ///

    fun refresh(accountId: String? = null) {
        val accountId = accountId ?: AccountStore.activeAccountId ?: return
        scope.launch {
            try {
                val apps = WalletCore.call(ApiMethod.DApp.GetDapps(accountId))
                setDapps(accountId, apps)
                WalletCore.notifyEvent(WalletEvent.DappsCountUpdated)
            } catch (_: Throwable) {
            }
        }
    }

    fun removeAccount(accountId: String) {
        _dAppsFlow.value = _dAppsFlow.value.toMutableMap().apply {
            remove(accountId)
        }
    }

    override fun wipeData() {
        clearCache()
    }

    override fun clearCache() {
        _dAppsFlow.value = emptyMap()
    }
}
