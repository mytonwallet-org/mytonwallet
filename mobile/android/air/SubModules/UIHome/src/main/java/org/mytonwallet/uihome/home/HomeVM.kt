package org.mytonwallet.uihome.home

import android.content.Context
import android.os.Handler
import android.os.Looper
import org.mytonwallet.app_air.walletcore.STAKING_SLUGS
import org.mytonwallet.app_air.walletcore.TONCOIN_SLUG
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.api.fetchAccount
import org.mytonwallet.app_air.walletcore.api.requestDAppList
import org.mytonwallet.app_air.walletcore.api.swapGetAssets
import org.mytonwallet.app_air.walletcore.helpers.ActivityLoader
import org.mytonwallet.app_air.walletcore.helpers.IActivityLoader
import org.mytonwallet.app_air.walletcore.models.MBlockchain
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import org.mytonwallet.app_air.walletcore.stores.BalanceStore
import org.mytonwallet.app_air.walletcore.stores.TokenStore
import org.mytonwallet.app_air.walletbasecontext.logger.Logger
import org.mytonwallet.uihome.home.views.UpdateStatusView
import java.lang.ref.WeakReference
import java.util.concurrent.Executors

class HomeVM(val context: Context, delegate: Delegate) : WalletCore.EventObserver,
    IActivityLoader.Delegate {

    interface Delegate {
        fun update(state: UpdateStatusView.State, animated: Boolean)
        fun updateBalance(balance: Double?, balance24h: Double?, accountChanged: Boolean)
        fun reloadCard()

        // instant update list
        fun transactionsLoaded()

        // animated update transactions
        fun transactionsUpdated(isUpdateEvent: Boolean)
        fun cacheNotFound()
        fun loadedAll()

        fun loadStakingData()
        fun stakingDataUpdated()

        // fun forceReload()
        fun instantScrollToTop()

        fun updateActionsView()
        fun reloadTabs(accountChanged: Boolean)
        fun accountNameChanged()
        fun accountConfigChanged()
    }

    val delegate: WeakReference<Delegate> = WeakReference(delegate)

    var waitingForNetwork = false

    // unique identifier to detect and ignore revoked requests
    internal var accountCode = 0L

    // Activities variables
    internal var activityLoaderHelper: IActivityLoader? = null
    internal var calledReady = false

    // loaded data
    private val balancesLoaded: Boolean
        get() {
            return !BalanceStore.getBalances(accountId = AccountStore.activeAccountId)
                .isNullOrEmpty()
        }

    private val handler = Handler(Looper.getMainLooper())
    private val updateRunnable = object : Runnable {
        override fun run() {
            checkUpdatingTimer = null
            updateStatus()
        }
    }
    private var checkUpdatingTimer: Runnable? = null
    private fun startUpdatingTimer() {
        if (checkUpdatingTimer == null) {
            checkUpdatingTimer = updateRunnable
            handler.postDelayed(updateRunnable, 2000)
        }
    }

    private fun stopUpdatingTimer() {
        checkUpdatingTimer?.let { handler.removeCallbacks(it) }
        checkUpdatingTimer = null
    }

    fun delegateIsReady() {
        WalletCore.registerObserver(this)
        if (!WalletCore.isConnected()) {
            connectionLost()
        }
        startUpdatingTimer()
    }

    val isGeneralDataAvailable: Boolean
        get() {
            return TokenStore.swapAssets != null &&
                TokenStore.loadedAllTokens &&
                !BalanceStore.getBalances(AccountStore.activeAccountId).isNullOrEmpty()
        }

    // Called on start or account change
    fun initWalletInfo() {
        // fetch all data
        val accountId = AccountStore.activeAccountId ?: return
        WalletCore.fetchAccount(accountId) { account, err ->
            accountCode = System.currentTimeMillis()
            activityLoaderHelper?.clean()
            activityLoaderHelper =
                ActivityLoader(context, accountId, null, WeakReference(this))
            activityLoaderHelper?.askForActivities()
        }
        // Load staking data
        delegate.get()?.loadStakingData()

        WalletCore.requestDAppList()
    }

    // called on pull to refresh / selected slug change / after network reconnection / when retrying failed tries
    private fun HomeVM.refreshTransactions() {
        // init requests
        initWalletInfo()
    }

    private fun dataUpdated() {
        // make sure balances are loaded
        if (!balancesLoaded) {
            Logger.i(Logger.LogTag.HomeVM, "Balances not loaded yet")
            return
        }

        // make sure tokens are loaded
        if (!TokenStore.loadedAllTokens) {
            Logger.i(Logger.LogTag.HomeVM, "tokens not loaded yet")
            return
        }

        // make sure default event for receiving native tokens of all chains is called
        val balances = BalanceStore.getBalances(AccountStore.activeAccountId)
        val account = AccountStore.activeAccount

        val missingNativeTokens = account?.byChain?.keys?.any { chain ->
            val blockchain = try {
                MBlockchain.valueOf(chain)
            } catch (_: IllegalArgumentException) {
                null
            }
            val nativeTokenSlug = blockchain?.nativeSlug
            nativeTokenSlug != null && balances?.get(nativeTokenSlug) == null
        } ?: false

        if (missingNativeTokens) {
            Logger.i(Logger.LogTag.HomeVM, "Native token balances not loaded yet for all chains")
            return
        }

        // make sure assets are loaded
        if (TokenStore.swapAssets == null) {
            Logger.i(Logger.LogTag.HomeVM, "swap assets are not loaded yet")
            Handler(Looper.getMainLooper()).postDelayed({
                if (TokenStore.swapAssets == null) {
                    WalletCore.swapGetAssets(true) { assets, err ->
                        dataUpdated()
                    }
                }
            }, 5000)
            return
        }

        updateBalanceView(false)

        delegate.get()?.transactionsLoaded()
    }

    private fun updateBalanceView(accountChanged: Boolean) {
        if (!balancesLoaded || TokenStore.getToken(TONCOIN_SLUG)?.price == null) {
            delegate.get()?.updateBalance(null, null, accountChanged)
            return
        }

        // update balance view
        Executors.newSingleThreadExecutor().execute {
            val walletTokens = AccountStore.assetsAndActivityData.getAllTokens()
                .filter { !STAKING_SLUGS.contains(it.token) }.toMutableList()

            val stakingData = AccountStore.stakingData
            val totalBalance =
                walletTokens.sumOf { it.toBaseCurrency ?: 0.0 } +
                    (stakingData?.totalBalanceInBaseCurrency() ?: 0.0)
            val totalBalanceYesterday = walletTokens.sumOf { it.toBaseCurrency24h ?: 0.0 } +
                (stakingData?.totalBalanceInBaseCurrency24h() ?: 0.0)

            Handler(Looper.getMainLooper()).post {
                // reload balance
                delegate.get()?.updateBalance(
                    balance = totalBalance,
                    balance24h = totalBalanceYesterday,
                    accountChanged
                )
            }
        }
    }

    private fun baseCurrencyChanged() {
        delegate.get()?.updateBalance(null, null, false)
        // reload tableview to make it clear as the tokens are not up to date
        delegate.get()?.transactionsLoaded()
        // make header empty like initialization view
        updateBalanceView(false)
    }

    private fun updateStatus(animated: Boolean = true) {
        if (waitingForNetwork) {
            // It's either `waiting for network` or `not specified` yet!
            return
        }
        if (AccountStore.updatingActivities || AccountStore.updatingBalance) {
            delegate.get()?.update(UpdateStatusView.State.Updating, animated)
        } else {
            delegate.get()?.update(UpdateStatusView.State.Updated, animated)
        }
    }

    private fun connectionLost() {
        waitingForNetwork = true
        delegate.get()?.update(UpdateStatusView.State.WaitingForNetwork, true)
    }

    private fun accountChanged() {
        calledReady = false

        activityLoaderHelper?.clean()
        activityLoaderHelper = null
        // reload tableview to make it clear as the tokens are not up to date
        delegate.get()?.transactionsLoaded()
        // get all data again
        initWalletInfo()
        // make header empty like initialization view
        updateBalanceView(true)
        delegate.get()?.instantScrollToTop()
        updateStatus(false)

        // update actions view
        delegate.get()?.updateActionsView()
        delegate.get()?.reloadTabs(true)
        delegate.get()?.accountNameChanged()
        delegate.get()?.accountConfigChanged()

        dataUpdated()
    }

    override fun onWalletEvent(walletEvent: WalletEvent) {
        when (walletEvent) {
            WalletEvent.BalanceChanged, WalletEvent.TokensChanged -> {
                dataUpdated()
            }

            WalletEvent.BaseCurrencyChanged -> {
                baseCurrencyChanged()
            }

            is WalletEvent.AccountChanged -> {
                accountChanged()
            }

            WalletEvent.AccountNameChanged -> {
                delegate.get()?.accountNameChanged()
                dataUpdated()
            }

            WalletEvent.AccountSavedAddressesChanged -> {
                dataUpdated()
            }

            WalletEvent.StakingDataUpdated -> {
                delegate.get()?.stakingDataUpdated()
            }

            WalletEvent.AssetsAndActivityDataUpdated -> {
                dataUpdated()
            }

            WalletEvent.NetworkConnected -> {
                if (waitingForNetwork) {
                    waitingForNetwork = false
                    refreshTransactions()
                } else {
                    waitingForNetwork = false
                    updateStatus()
                }
            }

            WalletEvent.NetworkDisconnected -> {
                connectionLost()
            }

            WalletEvent.NftCardUpdated -> {
                delegate.get()?.reloadCard()
            }

            WalletEvent.NftsUpdated, WalletEvent.HomeNftCollectionsUpdated -> {
                delegate.get()?.reloadTabs(false)
            }

            WalletEvent.UpdatingStatusChanged -> {
                startUpdatingTimer()
            }

            WalletEvent.AccountConfigReceived -> {
                delegate.get()?.accountConfigChanged()
            }

            else -> {}
        }
    }

    override fun activityLoaderDataLoaded(isUpdateEvent: Boolean) {
        delegate.get()?.transactionsUpdated(isUpdateEvent = isUpdateEvent)
        dataUpdated()
        updateStatus()
    }

    override fun activityLoaderCacheNotFound() {
        delegate.get()?.cacheNotFound()
    }

    override fun activityLoaderLoadedAll() {
        delegate.get()?.loadedAll()
    }

    fun destroy() {
        stopUpdatingTimer()
        WalletCore.unregisterObserver(this)
    }
}
