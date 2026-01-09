package org.mytonwallet.app_air.walletcore.stores

import android.os.Handler
import android.os.Looper
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.logger.Logger
import org.mytonwallet.app_air.walletcontext.cacheStorage.WCacheStorage
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.secureStorage.WSecureStorage
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletCore.notifyEvent
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.api.removeAccount
import org.mytonwallet.app_air.walletcore.helpers.PoisoningCacheHelper
import org.mytonwallet.app_air.walletcore.models.MAccount
import org.mytonwallet.app_air.walletcore.models.MAccount.AccountChain
import org.mytonwallet.app_air.walletcore.models.MAssetsAndActivityData
import org.mytonwallet.app_air.walletcore.models.MBridgeError
import org.mytonwallet.app_air.walletcore.moshi.MUpdateStaking
import org.mytonwallet.app_air.walletcore.moshi.api.ApiUpdate
import org.mytonwallet.app_air.walletcore.pushNotifications.AirPushNotifications

object AccountStore : IStore {

    // Observable Flow /////////////////////////////////////////////////////////////////////////////
    private val _activeAccountIdFlow = MutableStateFlow<String?>(null)
    val activeAccountId get() = _activeAccountIdFlow.value
    val activeAccountIdFlow = _activeAccountIdFlow.asStateFlow()
    fun updateActiveAccount(accountId: String?) {
        isAccountInitialized = false
        _activeAccountIdFlow.value = accountId
    }

    // Account related data ////////////////////////////////////////////////////////////////////////
    var activeAccount: MAccount? = null
    var updatingActivities: Boolean = false
    var updatingBalance: Boolean = false
    var isAccountInitialized: Boolean = false

    // Indicates if the active account is pushed temporarily.
    //  It's set to false whenever switching to default wallet mode.
    var isPushedTemporary: Boolean = false
    val permanentActiveAccount: MAccount?
        get() {
            return if (!isPushedTemporary) activeAccount else accountById(WGlobalStorage.getActiveAccountId())
        }

    var assetsAndActivityData: MAssetsAndActivityData = MAssetsAndActivityData()
        private set

    @Synchronized
    fun updateAssetsAndActivityData(
        newValue: MAssetsAndActivityData,
        notify: Boolean,
        saveToStorage: Boolean
    ) {
        assetsAndActivityData = newValue
        if (saveToStorage)
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

    // Clear all the temporary account related data if exist
    fun removeTemporaryAccounts() {
        WGlobalStorage.temporaryAddedAccountIds.toList().forEach {
            removeAccount(it, null, false, null)
        }
        WGlobalStorage.temporaryAddedAccountIds.clear()
    }

    fun removeAccount(
        removingAccountId: String,
        nextAccountId: String?,
        isNextAccountPushedTemporary: Boolean?,
        onCompletion: ((Boolean?, MBridgeError?) -> Unit)?
    ) {
        WalletCore.removeAccount(
            removingAccountId,
            nextAccountId,
            isNextAccountPushedTemporary
        ) { done, error ->
            if (error != null || done != true) {
                Logger.d(Logger.LogTag.ACCOUNT, "Remove account failed: $removingAccountId / error: $error")
                onCompletion?.invoke(done, error)
                return@removeAccount
            }

            Logger.d(Logger.LogTag.ACCOUNT, "Remove account: $removingAccountId")
            val accountObj = WGlobalStorage.getAccount(removingAccountId)
            accountObj?.let {
                val account = MAccount(
                    removingAccountId,
                    accountObj
                )
                if (!account.isTemporary)
                    AirPushNotifications.unsubscribe(account) {}
            }
            ActivityStore.removeAccount(removingAccountId)
            PoisoningCacheHelper.removeAccount(removingAccountId)
            DappsStore.removeAccount(removingAccountId)
            NftStore.setNfts(
                null,
                removingAccountId,
                notifyObservers = false,
                isReorder = false
            )
            WGlobalStorage.removeAccount(removingAccountId)
            StakingStore.setStakingState(removingAccountId, null)
            BalanceStore.removeBalances(removingAccountId)
            WCacheStorage.clean(removingAccountId)
            notifyEvent(WalletEvent.AccountRemoved(removingAccountId))
            onCompletion?.invoke(done, error)
        }
    }

    fun renameAccount(account: MAccount, newWalletName: String) {
        account.name = newWalletName
        WGlobalStorage.save(
            account.accountId,
            newWalletName
        )
        AddressStore.updatedAccountName(
            account.accountId,
            newWalletName
        )
        if (activeAccountId == account.accountId) {
            activeAccount?.name = newWalletName
        }
        AirPushNotifications.accountNameChanged(account)
        notifyEvent(WalletEvent.AccountNameChanged)
    }

    fun saveTemporaryAccount(account: MAccount) {
        if (activeAccountId != account.accountId)
            return
        if (account.name == LocaleController.getString("Wallet")) {
            val newName = WGlobalStorage.getSuggestedName(account.accountType.value)
            renameAccount(account, newName)
        }
        activeAccount?.isTemporary = false
        account.isTemporary = false
        WGlobalStorage.saveTemporaryAccount(account.accountId)
        AirPushNotifications.subscribe(account, ignoreIfLimitReached = true)
        // Update home screen
        isPushedTemporary = false
        notifyEvent(WalletEvent.AccountChanged(account.accountId, isSavingTemporaryAccount = true))
        // Pop to home screen
        Handler(Looper.getMainLooper()).post {
            notifyEvent(WalletEvent.TemporaryAccountSaved(account.accountId))
            notifyEvent(WalletEvent.AccountChangedInApp(true))
        }
    }

    fun updateAccountByChain(accountId: String, byChain: Map<String, AccountChain>) {
        WGlobalStorage.saveAccountByChain(accountId, MAccount.byChainToJson(byChain))
        notifyEvent(WalletEvent.ByChainUpdated(accountId))
    }

    override fun wipeData() {
        WGlobalStorage.deleteAllWallets()
        WSecureStorage.deleteAllWalletValues()
        clearCache()
    }

    override fun clearCache() {
        updateActiveAccount(null)
        updateAssetsAndActivityData(MAssetsAndActivityData(), notify = false, saveToStorage = false)
        walletVersionsData = null
    }
}
