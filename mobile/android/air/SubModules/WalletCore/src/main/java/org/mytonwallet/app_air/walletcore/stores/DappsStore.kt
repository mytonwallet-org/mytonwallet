package org.mytonwallet.app_air.walletcore.stores

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import org.mytonwallet.app_air.walletcore.moshi.ApiDapp

object DappsStore {

    // Observable Flow
    private val _dAppsFlow = MutableStateFlow<Map<String, List<ApiDapp>>>(emptyMap())
    val dApps get() = _dAppsFlow.value
    val dAppsFlow = _dAppsFlow.asStateFlow()
    fun setDapps(accountId: String, apps: List<ApiDapp>) {
        _dAppsFlow.value = _dAppsFlow.value.toMutableMap().apply {
            put(accountId, apps)
        }
    }
    /////

}
