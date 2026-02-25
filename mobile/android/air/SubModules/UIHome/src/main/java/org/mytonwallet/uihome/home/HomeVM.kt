package org.mytonwallet.uihome.home

import android.os.Handler
import android.os.Looper
import org.mytonwallet.app_air.walletbasecontext.logger.Logger
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.models.MBlockchainNetwork
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.api.requestDAppList
import org.mytonwallet.app_air.walletcore.api.swapGetAssets
import org.mytonwallet.app_air.walletcore.models.MAccount
import org.mytonwallet.app_air.walletcore.models.blockchain.MBlockchain
import org.mytonwallet.app_air.walletcore.models.MScreenMode
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import org.mytonwallet.app_air.walletcore.stores.BalanceStore
import org.mytonwallet.app_air.walletcore.stores.StakingStore
import org.mytonwallet.app_air.walletcore.stores.TokenStore
import org.mytonwallet.uihome.home.views.UpdateStatusView
import java.lang.ref.WeakReference

class HomeVM(
    private val mode: MScreenMode,
    delegate: Delegate
) : WalletCore.EventObserver {

    interface Delegate {
        fun update(state: UpdateStatusView.State, animated: Boolean)
        fun updateHeaderCards(expand: Boolean)
        fun updateBalance(accountChangedFromOtherScreens: Boolean)
        fun reloadCard()
        fun reloadCardAddress(accountId: String)

        // animated update transactions
        fun transactionsUpdated(isUpdateEvent: Boolean)

        fun loadStakingData()
        fun stakingDataUpdated()

        fun configureAccountViews(shouldLoadNewWallets: Boolean, skipSkeletonOnCache: Boolean)
        fun reloadTabs()
        fun accountNameChanged(accountName: String, animated: Boolean)
        fun accountConfigChanged()
        fun seasonalThemeChanged()
        fun accountWillChange(fromHome: Boolean)
        fun removeScreenFromStack()

        fun pop()
        fun popToRoot()
    }

    // PUBLIC VARIABLES ////////////////////////////////////////////////////////////////////////////
    internal var calledReady = false

    val showingAccount: MAccount?
        get() {
            return when (mode) {
                MScreenMode.Default -> {
                    AccountStore.permanentActiveAccount
                }

                is MScreenMode.SingleWallet -> {
                    AccountStore.accountById(mode.accountId)
                }
            }
        }

    // Tokens, Balance and Staking data are loaded or not
    val isGeneralDataAvailable: Boolean
        get() {
            return TokenStore.swapAssets != null &&
                TokenStore.loadedAllTokens &&
                !BalanceStore.getBalances(showingAccountId).isNullOrEmpty() &&
                (showingAccount?.network != MBlockchainNetwork.MAINNET ||
                    StakingStore.getStakingState(showingAccountId ?: "") != null ||
                    WGlobalStorage.getAccountTonAddress(showingAccountId ?: "") == null)
        }

    // Called on bridge ready to setup the observer
    fun setupObservers() {
        WalletCore.registerObserver(this)
        if (!WalletCore.isConnected()) {
            connectionLost()
        }
        startUpdatingTimer()
    }

    fun destroy() {
        stopUpdatingTimer()
        WalletCore.unregisterObserver(this)
    }

    // Remove temporary account
    fun removeTemporaryAccount() {
        val removingAccountId = showingAccountId ?: return
        val shouldRemoveCurrentAccount =
            WGlobalStorage.temporaryAddedAccountIds.contains(removingAccountId)
        if (!shouldRemoveCurrentAccount)
            return
        Logger.d(Logger.LogTag.ACCOUNT, "removeTemporaryAccount: accountId=$removingAccountId")
        AccountStore.removeAccount(removingAccountId, null, null) { _, _ ->
            WGlobalStorage.temporaryAddedAccountIds.remove(removingAccountId)
        }
    }

    // PRIVATE VARIABLES ///////////////////////////////////////////////////////////////////////////
    private val delegate: WeakReference<Delegate> = WeakReference(delegate)

    private var waitingForNetwork = false

    // The account that should be shown on the home screen
    private val showingAccountId: String?
        get() {
            return when (mode) {
                MScreenMode.Default -> {
                    WGlobalStorage.getActiveAccountId()
                }

                is MScreenMode.SingleWallet -> {
                    mode.accountId
                }
            }
        }

    // The account showing on the home screen
    var loadedAccountId: String? = null
    val loadedAccount: MAccount?
        get() {
            return when (mode) {
                MScreenMode.Default -> {
                    if (loadedAccountId == AccountStore.activeAccountId)
                        AccountStore.activeAccount
                    else
                        AccountStore.accountById(loadedAccountId)
                }

                is MScreenMode.SingleWallet -> {
                    AccountStore.accountById(mode.accountId)
                }
            }
        }

    // Is balance loaded for the account or not
    private val balancesLoaded: Boolean
        get() {
            return !BalanceStore.getBalances(accountId = showingAccountId).isNullOrEmpty()
        }

    // UpdateStatusView handler
    private val handler = Handler(Looper.getMainLooper())
    private val updateRunnable = Runnable {
        checkUpdatingTimer = null
        updateStatus()
    }
    private var checkUpdatingTimer: Runnable? = null
    private fun startUpdatingTimer() {
        val checkUpdatingTimer = checkUpdatingTimer
        if (checkUpdatingTimer != null)
            handler.removeCallbacks(checkUpdatingTimer)
        if (AccountStore.updatingActivities || AccountStore.updatingBalance) {
            this.checkUpdatingTimer = updateRunnable
            handler.postDelayed(this.checkUpdatingTimer!!, 2000)
        } else {
            updateRunnable.run()
        }
    }

    private fun stopUpdatingTimer() {
        checkUpdatingTimer?.let { handler.removeCallbacks(it) }
        checkUpdatingTimer = null
    }

    // Check if everything is ready and notify transaction list to reload
    private fun dataUpdated(updateBalance: Boolean = true) {
        // make sure balances are loaded
        if (!balancesLoaded) {
            Logger.d(Logger.LogTag.HomeVM, "dataUpdated: Balances not loaded yet")
            return
        }

        // make sure tokens are loaded
        if (!TokenStore.loadedAllTokens) {
            Logger.d(Logger.LogTag.HomeVM, "dataUpdated: Tokens not loaded yet")
            return
        }

        // make sure default event for receiving native tokens of all chains is called
        val balances = BalanceStore.getBalances(showingAccountId)
        val account = showingAccount

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
            Logger.d(
                Logger.LogTag.HomeVM,
                "dataUpdated: Native token balances not loaded yet for all chains"
            )
            return
        }

        // make sure assets are loaded
        if (TokenStore.swapAssets == null) {
            Logger.d(Logger.LogTag.HomeVM, "dataUpdated: Swap assets not loaded yet")
            Handler(Looper.getMainLooper()).postDelayed({
                if (TokenStore.swapAssets == null) {
                    WalletCore.swapGetAssets(true) { assets, err ->
                        dataUpdated(updateBalance)
                    }
                }
            }, 5000)
            return
        }

        if (updateBalance) {
            updateBalanceView(false)
        }

        delegate.get()?.transactionsUpdated(isUpdateEvent = false)
    }

    private fun updateBalanceView(accountChangedFromOtherScreens: Boolean) {
        delegate.get()?.updateBalance(accountChangedFromOtherScreens)
        return
    }

    private fun baseCurrencyChanged() {
        // Reload balance view
        updateBalanceView(false)
        // Reload tableview to make it clear as the tokens are not up to date
        delegate.get()?.transactionsUpdated(isUpdateEvent = false)
    }

    private fun updateStatus(animated: Boolean = true) {
        if (waitingForNetwork) {
            // It's either `waiting for network` or `not specified` yet!
            return
        }
        if (AccountStore.updatingActivities || AccountStore.updatingBalance) {
            delegate.get()?.update(UpdateStatusView.State.Updating, animated)
        } else {
            delegate.get()
                ?.update(UpdateStatusView.State.Updated(loadedAccount?.name ?: ""), animated)
        }
    }

    private fun connectionLost() {
        waitingForNetwork = true
        delegate.get()?.update(UpdateStatusView.State.WaitingForNetwork, true)
    }

    private fun accountChanged(fromHome: Boolean, isSavingTemporaryWallet: Boolean) {
        calledReady = false

        // make header empty like initialization view
        if (!fromHome) {
            delegate.get()?.updateHeaderCards(isSavingTemporaryWallet)
        }

        // update actions view
        delegate.get()?.configureAccountViews(
            shouldLoadNewWallets = !fromHome,
            skipSkeletonOnCache = fromHome
        )
        delegate.get()?.updateBalance(accountChangedFromOtherScreens = !fromHome)
    }

    override fun onWalletEvent(walletEvent: WalletEvent) {
        when (walletEvent) {
            WalletEvent.BalanceChanged, WalletEvent.TokensChanged -> {
                dataUpdated()
            }

            WalletEvent.BaseCurrencyChanged -> {
                baseCurrencyChanged()
            }

            is WalletEvent.AccountWillChange -> {
                if (!mode.isScreenActive || loadedAccountId == WalletCore.nextAccountId)
                    return
                delegate.get()?.accountWillChange(walletEvent.fromHome)
                updateBalanceView(!walletEvent.fromHome)
            }

            is WalletEvent.AccountChanged -> {
                if (!mode.isScreenActive || loadedAccountId == AccountStore.activeAccountId)
                    return
                accountChanged(walletEvent.fromHome, walletEvent.isSavingTemporaryAccount)
            }

            WalletEvent.AccountNameChanged -> {
                delegate.get()?.accountNameChanged(showingAccount?.name ?: "", false)
                dataUpdated()
            }

            WalletEvent.AccountSavedAddressesChanged -> {
                dataUpdated()
            }

            WalletEvent.StakingDataUpdated -> {
                delegate.get()?.stakingDataUpdated()
                dataUpdated()
            }

            WalletEvent.AssetsAndActivityDataUpdated -> {
                dataUpdated()
            }

            WalletEvent.NetworkConnected -> {
                if (waitingForNetwork) {
                    waitingForNetwork = false
                    delegate.get()?.loadStakingData()
                    WalletCore.requestDAppList(showingAccountId)
                } else {
                    waitingForNetwork = false
                    updateStatus()
                }
            }

            WalletEvent.NetworkDisconnected -> {
                connectionLost()
            }

            WalletEvent.NftCardUpdated -> {
                if (!mode.isScreenActive)
                    return
                delegate.get()?.reloadCard()
            }

            WalletEvent.NftsUpdated, WalletEvent.HomeNftCollectionsUpdated -> {
                if (!mode.isScreenActive)
                    return
                delegate.get()?.reloadTabs()
            }

            WalletEvent.UpdatingStatusChanged -> {
                startUpdatingTimer()
            }

            WalletEvent.AccountConfigReceived -> {
                delegate.get()?.accountConfigChanged()
            }

            WalletEvent.SeasonalThemeChanged -> {
                delegate.get()?.seasonalThemeChanged()
            }

            is WalletEvent.AccountRemoved -> {
                when (mode) {
                    MScreenMode.Default -> {
                        if (AccountStore.isPushedTemporary) {
                            if (walletEvent.accountId == loadedAccountId) {
                                delegate.get()?.accountWillChange(fromHome = false)
                                accountChanged(fromHome = false, isSavingTemporaryWallet = false)
                            } else {
                                delegate.get()?.updateHeaderCards(false)
                            }
                        } else {
                            delegate.get()?.updateHeaderCards(false)
                        }
                    }

                    is MScreenMode.SingleWallet -> {
                        if (walletEvent.accountId == loadedAccountId)
                            delegate.get()?.removeScreenFromStack()
                        // else: doesn't matter
                    }
                }
            }

            is WalletEvent.ByChainUpdated -> {
                delegate.get()?.apply {
                    reloadCardAddress(walletEvent.accountId)
                }
            }

            WalletEvent.AccountsReordered -> {
                delegate.get()?.updateHeaderCards(false)
                delegate.get()?.configureAccountViews(
                    shouldLoadNewWallets = true,
                    skipSkeletonOnCache = false
                )
            }

            else -> {}
        }
    }

}
