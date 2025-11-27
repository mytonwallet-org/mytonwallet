package org.mytonwallet.app_air.walletcore.stores

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.secureStorage.WSecureStorage
import org.mytonwallet.app_air.walletcore.WalletCore.notifyEvent
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.models.MAccount
import org.mytonwallet.app_air.walletcore.models.MAssetsAndActivityData
import org.mytonwallet.app_air.walletcore.moshi.MUpdateStaking
import org.mytonwallet.app_air.walletcore.moshi.api.ApiUpdate

object AccountStore : IStore {

    // Observable Flow
    private val _activeAccountIdFlow = MutableStateFlow<String?>(null)
    val activeAccountId get() = _activeAccountIdFlow.value
    val activeAccountIdFlow = _activeAccountIdFlow.asStateFlow()
    fun updateActiveAccount(accountId: String?) {
        isAccountInitialized = false
        _activeAccountIdFlow.value = accountId
    }
    /////

    // Account related data
    var activeAccount: MAccount? = null
    var updatingActivities: Boolean = false
    var updatingBalance: Boolean = false
    var isAccountInitialized: Boolean = false

    var assetsAndActivityData: MAssetsAndActivityData = MAssetsAndActivityData()
        private set

    @Synchronized
    fun updateAssetsAndActivityData(newValue: MAssetsAndActivityData, notify: Boolean) {
        assetsAndActivityData = newValue
        activeAccountId?.let { activeAccountId ->
            WGlobalStorage.setAssetsAndActivityData(activeAccountId, newValue.toJSON)
        }
        if (notify)
            notifyEvent(WalletEvent.AssetsAndActivityDataUpdated)
    }

    var walletVersionsData: ApiUpdate.ApiUpdateWalletVersions? = null

    val stakingData: MUpdateStaking?
        get() {
            activeAccountId?.let {
                return StakingStore.getStakingState(activeAccountId!!)
            }
            return null
        }

    fun accountIdByAddress(tonAddress: String?): String? {
        if (tonAddress == null)
            return null
        val accountIds = WGlobalStorage.accountIds()
        for (accountId in accountIds) {
            val accountObj = WGlobalStorage.getAccount(accountId)
            if (accountObj != null) {
                val account = MAccount(accountId, accountObj)
                if (account.tonAddress == tonAddress) {
                    return accountId
                }
            }
        }
        return null
    }

    fun accountById(accountId: String?): MAccount? {
        val accountId = accountId ?: return null
        val accountObj = WGlobalStorage.getAccount(accountId)
        accountObj?.let {
            return MAccount(accountId, accountObj)
        }
        return null
    }

    fun updateAccountData(update: ApiUpdate.ApiUpdateUpdateAccount) {
        // TODO::
    }

    override fun wipeData() {
        WGlobalStorage.deleteAllWallets()
        WSecureStorage.deleteAllWalletValues()
        clearCache()
    }

    override fun clearCache() {
        updateActiveAccount(null)
        updateAssetsAndActivityData(MAssetsAndActivityData(), notify = false)
        walletVersionsData = null
    }
}
