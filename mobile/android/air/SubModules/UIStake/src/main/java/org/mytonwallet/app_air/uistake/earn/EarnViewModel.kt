package org.mytonwallet.app_air.uistake.earn

import android.os.Handler
import android.os.Looper
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.channels.BufferOverflow
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import org.mytonwallet.app_air.uistake.earn.models.EarnItem
import org.mytonwallet.app_air.uistake.util.toViewItem
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.utils.doubleAbsRepresentation
import org.mytonwallet.app_air.walletbasecontext.utils.smartDecimalsCount
import org.mytonwallet.app_air.walletbasecontext.utils.toString
import org.mytonwallet.app_air.walletcontext.utils.CoinUtils
import org.mytonwallet.app_air.walletcore.JSWebViewBridge
import org.mytonwallet.app_air.walletcore.TONCOIN_SLUG
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.api.getStakingHistory
import org.mytonwallet.app_air.walletcore.tokenSlugToStakingSlug
import org.mytonwallet.app_air.walletcore.models.MToken
import org.mytonwallet.app_air.walletcore.moshi.MApiTransaction
import org.mytonwallet.app_air.walletcore.moshi.MStakeHistoryItem
import org.mytonwallet.app_air.walletcore.moshi.MUpdateStaking
import org.mytonwallet.app_air.walletcore.moshi.StakingState
import org.mytonwallet.app_air.walletcore.moshi.api.ApiMethod
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import org.mytonwallet.app_air.walletcore.stores.BalanceStore
import org.mytonwallet.app_air.walletcore.stores.TokenStore
import java.math.BigInteger

class EarnViewModel(val tokenSlug: String) : ViewModel(), WalletCore.EventObserver {

    companion object {
        fun alias(slug: String) = "EarnViewModel_$slug"
    }

    //
    private val _viewState: MutableSharedFlow<EarnViewState> =
        MutableSharedFlow(replay = 1, onBufferOverflow = BufferOverflow.DROP_OLDEST)
    val viewState = _viewState.asSharedFlow()
    private var historyItems: MutableList<EarnItem>? = null
    private val historyItemsMutex = Mutex()
    var apy: Float? = null
    var amountToClaim: BigInteger? = null
    var token: MToken? = null
        get() {
            if (field == null) {
                field = TokenStore.getToken(tokenSlug)
            }
            return field
        }
    private val stakedTokenSlug = tokenSlugToStakingSlug(tokenSlug) ?: ""

    init {
        WalletCore.registerObserver(this)

        // initial view state
        _viewState.tryEmit(EarnViewState(canAddStake = false, canUnstake = false))
    }

    private fun clearMainVariables() {
        _viewState.tryEmit(EarnViewState(canAddStake = false, canUnstake = false))
        historyItems = null
        apy = null
        amountToClaim = null
        token = TokenStore.getToken(tokenSlug)
    }

    fun loadOrRefreshStakingData() {
        if (!allLoadedOnce) {
            AccountStore.activeAccountId?.let {
                requestStakingState(it)
            }
        } else {
            refreshStakingHistoryLatestChanges()
        }
    }

    private var isLoadingStakingState = false
    private fun requestStakingState(accountId: String) {
        if (isLoadingStakingState || token == null || AccountStore.stakingData == null) return

        viewModelScope.launch {
            isLoadingStakingState = true

            try {
                updateViewState(AccountStore.stakingData!!)

                requestStakingHistory(accountId, page = 1)
                requestTokenActivitiesForUnstakedItems(null)
                requestTokenActivitiesForStakedItems(null)

                isLoadingStakingState = false
            } catch (_: JSWebViewBridge.ApiError) {
                isLoadingStakingState = false

                // retry
                delay(2000)
                resetPage()
                requestStakingState(accountId)
            } catch (_: Throwable) {
                isLoadingStakingState = false

                // retry
                delay(2000)
                resetPage()
                requestStakingState(accountId)
            }
        }
    }

    private fun updateViewState(updateStaking: MUpdateStaking) {
        val stakingState = updateStaking.stakingState(tokenSlug)

        apy = stakingState?.annualYield
        amountToClaim = stakingState?.amountToClaim

        val stakingBalanceValue = stakingState?.totalBalance
        val stakingBalance = stakingBalanceValue?.toString(
            token!!.decimals,
            "",
            stakingBalanceValue.smartDecimalsCount(token!!.decimals),
            showPositiveSign = false,
            forceCurrencyToRight = true,
            roundUp = false
        )
        val stakingBalanceIsLarge = stakingBalanceValue?.doubleAbsRepresentation(token!!.decimals)?.let { it >= 10 } ?: false

        val totalProfitAmount = when {
            tokenSlug == TONCOIN_SLUG -> updateStaking.totalProfit
            stakingState is StakingState.Jetton -> stakingState.unclaimedRewards
            stakingState is StakingState.Ethena -> null
            else -> BigInteger.ZERO
        }
        val totalProfit = totalProfitAmount?.toString(
            token!!.decimals,
            token!!.symbol,
            totalProfitAmount.smartDecimalsCount(9),
            showPositiveSign = false,
            forceCurrencyToRight = true
        )

        _viewState.tryEmit(
            viewStateValue().copy(
                stakingBalance = stakingBalance,
                stakingBalanceIsLarge = stakingBalanceIsLarge,
                totalProfit = totalProfit,
                showAddStakeButton = true,
                showUnstakeButton = stakingState?.shouldShowWithdrawButton ?: false,
                showBiggerUnstakeButton = stakingState?.isUnstakeRequestAmountUnlocked != true,
                enableAddStakeButton = getTokenBalance() > BigInteger.ZERO,
                unclaimedReward = amountToClaim
            )
        )
    }

    private fun refreshStakingHistoryLatestChanges() {
        val activeAccountId = AccountStore.activeAccountId ?: return
        requestStakingHistory(activeAccountId, 1, true)
        requestTokenActivitiesForUnstakedItems(null, true)
        requestTokenActivitiesForStakedItems(null, true)
    }

    private var isLoadingStakingHistory = false
    private var hasLoadedAllStakingHistoryItems = false
    private var lastLoadedPage = 0
    var lastStakingHistoryItem: EarnItem? = null
    private fun clearStakingHistoryVariables() {
        isLoadingStakingHistory = false
        hasLoadedAllStakingHistoryItems = false
        lastLoadedPage = 0
        lastStakingHistoryItem = null
    }

    private fun requestStakingHistory(
        accountId: String,
        page: Int,
        isCheckingLatestChanges: Boolean = false
    ) {
        if (isLoadingStakingHistory) return

        viewModelScope.launch() {
            isLoadingStakingHistory = true
            try {
                when (tokenSlug) {
                    TONCOIN_SLUG -> {
                        if (!isCheckingLatestChanges) {
                            val result =
                                WalletCore.getStakingHistory(
                                    accountId = accountId,
                                    /*page = page,
                                    limit = 100*/
                                )
                            lastLoadedPage = page
                            if (result.isNotEmpty()) {
                                val distinctResult = result.distinctBy { it.timestamp }
                                lastStakingHistoryItem = distinctResult.last().toViewItem()
                                mergeHistory(distinctResult)
                                //requestStakingHistory(accountId, page + 1)
                            } else if (viewStateValue().historyListState is HistoryListState.InitialState) {
                                _viewState.tryEmit(
                                    viewStateValue().copy(historyListState = HistoryListState.NoItem)
                                )
                            }
                            hasLoadedAllStakingHistoryItems = result.isEmpty()
                        } else {
                            val result =
                                WalletCore.getStakingHistory(
                                    accountId = accountId,
                                    /*page = 1,
                                    limit = 100*/
                                )
                            if (result.isNotEmpty()) {
                                val distinctResult = result.distinctBy { it.timestamp }
                                mergeHistory(distinctResult)
                            }
                        }
                    }

                    else -> {
                        // MY Coin
                        hasLoadedAllStakingHistoryItems = true
                        lastLoadedPage = page
                        if (historyItems.isNullOrEmpty()) showNoItemView()
                    }
                }
                isLoadingStakingHistory = false
            } catch (_: JSWebViewBridge.ApiError) {
                isLoadingStakingHistory = false

                // retry
                delay(2000)
                if (page == 1) {
                    requestStakingHistory(accountId, page)
                }
            } catch (_: Throwable) {
                isLoadingStakingHistory = false

                // retry
                delay(2000)
                if (page == 1) {
                    requestStakingHistory(accountId, page)
                }
            }
            isLoadingStakingHistory = false
        }
    }

    fun loadMoreStakingHistoryItems() {
        if (hasLoadedAllStakingHistoryItems) return
        AccountStore.activeAccountId?.let { activeAccountId ->
            requestStakingHistory(activeAccountId, lastLoadedPage + 1)
        }
    }

    var lastUnstakedActivityTimestamp: Long? = null
    private var hasLoadedAllUnstakedActivityItems = false
    private var isLoadingUnstakedActivityItems = false
    private fun clearUnstakedItemsVariables() {
        lastUnstakedActivityTimestamp = null
        hasLoadedAllUnstakedActivityItems = false
        isLoadingUnstakedActivityItems = false
    }

    private fun requestTokenActivitiesForUnstakedItems(
        fromTimestamp: Long?,
        isCheckingLatestChanges: Boolean = false
    ) {
        if (isLoadingUnstakedActivityItems) return
        isLoadingUnstakedActivityItems = true
        val activeAccountId = AccountStore.activeAccountId ?: return
        WalletCore.call(
            ApiMethod.WalletData.FetchPastActivities(
                accountId = activeAccountId,
                limit = 100,
                slug = tokenSlug,
                toTimestamp = fromTimestamp
            )
        ) { result, err ->
            if (activeAccountId != AccountStore.activeAccountId) return@call
            val transactions = result?.activities
            val isHistoryEndReached = result?.hasMore == false
            if (!transactions.isNullOrEmpty()) {
                if (!isCheckingLatestChanges) {
                    hasLoadedAllUnstakedActivityItems = isHistoryEndReached
                    lastUnstakedActivityTimestamp = transactions.last().timestamp
                }
                viewModelScope.launch {
                    mergeTransaction(transactions)
                    isLoadingUnstakedActivityItems = false
                }
            } else if (err != null) {
                Handler(Looper.getMainLooper()).postDelayed({
                    requestTokenActivitiesForUnstakedItems(
                        fromTimestamp,
                        isCheckingLatestChanges
                    )
                }, 2000)
                isLoadingUnstakedActivityItems = false
            } else {
                hasLoadedAllUnstakedActivityItems = isHistoryEndReached
                if (hasLoadedAllUnstakedActivityItems && historyItems.isNullOrEmpty()) {
                    showNoItemView()
                }
                isLoadingUnstakedActivityItems = false
            }
        }
    }

    fun loadMoreUnstakeActivityItem() {
        if (hasLoadedAllUnstakedActivityItems) return
        val timeStamp = lastUnstakedActivityTimestamp ?: return
        requestTokenActivitiesForUnstakedItems(fromTimestamp = timeStamp)
    }


    var lastStakedActivityTimestamp: Long? = null
    private var hasLoadedAllStakedActivityItems = false
    private var isLoadingStakedActivityItems = false
    private fun clearStakedItemsVariables() {
        lastStakedActivityTimestamp = null
        hasLoadedAllStakedActivityItems = false
        isLoadingStakedActivityItems = false
    }

    private fun requestTokenActivitiesForStakedItems(
        fromTimestamp: Long?,
        isCheckingLatestChanges: Boolean = false
    ) {
        if (isLoadingStakedActivityItems) return

        if (AccountStore.stakingData?.stakingState(stakedTokenSlug)?.balance == null) {
            hasLoadedAllStakedActivityItems = true
            if (historyItems.isNullOrEmpty()) {
                showNoItemView()
            }
            return
        }
        val activeAccountId = AccountStore.activeAccountId ?: return
        isLoadingStakedActivityItems = true
        WalletCore.call(
            ApiMethod.WalletData.FetchPastActivities(
                accountId = activeAccountId,
                limit = 100,
                slug = stakedTokenSlug,
                toTimestamp = fromTimestamp
            )
        ) { result, err ->
            val transactions = result?.activities
            val isHistoryEndReached = result?.hasMore == false
            if (!transactions.isNullOrEmpty()) {
                if (!isCheckingLatestChanges) {
                    hasLoadedAllStakedActivityItems = isHistoryEndReached
                    lastStakedActivityTimestamp = transactions.last().timestamp
                }
                viewModelScope.launch {
                    mergeTransaction(transactions)
                    isLoadingStakedActivityItems = false
                }
            } else if (err != null) {
                Handler(Looper.getMainLooper()).postDelayed({
                    requestTokenActivitiesForStakedItems(fromTimestamp, isCheckingLatestChanges)
                }, 2000)
                isLoadingStakedActivityItems = false
            } else {
                hasLoadedAllStakedActivityItems = isHistoryEndReached
                if (hasLoadedAllStakedActivityItems && historyItems.isNullOrEmpty()) {
                    showNoItemView()
                }
                isLoadingStakedActivityItems = false
            }
        }
    }

    fun loadMoreStakeActivityItems() {
        if (hasLoadedAllStakedActivityItems) return
        val timeStamp = lastStakedActivityTimestamp ?: return
        requestTokenActivitiesForStakedItems(fromTimestamp = timeStamp)
    }

    //
    private val allLoadedOnce: Boolean
        get() {
            return (lastLoadedPage > 0 &&
                (lastUnstakedActivityTimestamp != null || hasLoadedAllUnstakedActivityItems) &&
                (lastStakedActivityTimestamp != null || hasLoadedAllStakedActivityItems))
        }

    private suspend fun mergeTransaction(newTransactions: List<MApiTransaction>) =
        historyItemsMutex.withLock {
            val mergedItems = withContext(Dispatchers.Default) {
                val currentItems = historyItems?.toMutableList() ?: mutableListOf()

                newItemsLoop@ for (transaction in newTransactions.filterIsInstance<MApiTransaction.Transaction>()) {
                    val item =
                        transaction.toViewItem(tokenSlug, stakedTokenSlug)
                            .updateAmountInBaseCurrency()
                    if (item is EarnItem.None) {
                        continue
                    }

                    var added = false
                    for ((i, historyItem) in currentItems.withIndex()) {
                        if (
                            historyItem.timestamp == transaction.timestamp
                            && historyItem::class == item::class
                            && historyItem.amount == item.amount
                        ) {
                            // Is duplicate. This happens when checking for latest changes.
                            continue@newItemsLoop
                        } else if (historyItem.timestamp < transaction.timestamp) {
                            currentItems.add(i, item)
                            added = true
                            break
                        }
                    }
                    if (!added) {
                        currentItems.add(item)
                    }
                }
                currentItems
            }

            historyItems = mergedItems

            if (historyItems.isNullOrEmpty()) {
                showNoItemView()
            } else if (allLoadedOnce) {
                val currentHistoryItems = historyItems ?: return@withLock
                _viewState.tryEmit(
                    viewStateValue().updateHistoryItems(
                        newHistoryItems = groupConsecutiveProfitItems(currentHistoryItems),
                        replace = true
                    )
                )
            }

        }

    private suspend fun mergeHistory(newHistoryItems: List<MStakeHistoryItem>) =
        historyItemsMutex.withLock {
            val mergedItems = withContext(Dispatchers.Default) {
                val currentItems = historyItems?.toMutableList() ?: mutableListOf()

                newItemsLoop@ for (newHistoryItem in newHistoryItems) {
                    val item = newHistoryItem.toViewItem().updateAmountInBaseCurrency()

                    var added = false
                    for ((i, historyItem) in currentItems.withIndex()) {
                        if (historyItem.timestamp == newHistoryItem.timestamp
                            && historyItem::class == item::class
                            && historyItem.amount == item.amount
                        ) {
                            // Is duplicate. This happens when checking for latest changes.
                            continue@newItemsLoop
                        } else if (historyItem.timestamp < newHistoryItem.timestamp) {
                            currentItems.add(i, item)
                            added = true
                            break
                        }
                    }
                    if (!added) {
                        currentItems.add(item)
                    }
                }
                currentItems
            }

            historyItems = mergedItems

            if (allLoadedOnce) {
                val currentHistoryItems = historyItems ?: return@withLock
                _viewState.tryEmit(
                    viewStateValue().updateHistoryItems(
                        newHistoryItems = groupConsecutiveProfitItems(currentHistoryItems),
                        replace = true
                    )
                )
            }

        }

    //
    fun getHistoryItems(): List<EarnItem> {
        return if (viewStateValue().historyListState is HistoryListState.HasItem) {
            (viewStateValue().historyListState as HistoryListState.HasItem).historyItems
        } else listOf()
    }

    fun getTotalProfitFormatted() = viewStateValue().totalProfit

    fun viewStateValue() = viewState.replayCache.last()

    private fun showNoItemView() {
        if (allLoadedOnce) {
            _viewState.tryEmit(
                viewStateValue().copy(historyListState = HistoryListState.NoItem)
            )
        }
    }

    //
    private fun getTokenBalance(): BigInteger {
        return if (token == null) BigInteger.ZERO
        else {
            if (token?.isEarnAvailable == true) {
                AccountStore.activeAccountId?.let { activeAccountId ->
                    BalanceStore.getBalances(activeAccountId)?.get(token!!.slug)
                        ?: BigInteger.valueOf(0)
                } ?: BigInteger.valueOf(0)
            } else
                AccountStore.stakingData?.stakingState(token!!.slug)?.balance
                    ?: BigInteger.valueOf(0)
        }
    }

    private fun EarnItem.updateAmountInBaseCurrency(): EarnItem {
        amountInBaseCurrency = token?.price?.let { price ->
            (price * amount.doubleAbsRepresentation(decimals = token?.decimals)).toString(
                9,
                WalletCore.baseCurrency.sign,
                9,
                true
            )
        } ?: ""
        return this
    }

    private fun resetPage() {
        lastLoadedPage = 1
    }

    private fun groupConsecutiveProfitItems(rawList: MutableList<EarnItem>): MutableList<EarnItem> {
        val result = mutableListOf<EarnItem>()

        val consecutiveProfitList = mutableListOf<EarnItem.Profit>()
        var isFirstAdded = false
        rawList.forEachIndexed { index, earnItem ->
            when (earnItem) {
                is EarnItem.Profit -> {
                    if (!isFirstAdded) {
                        result.add(earnItem)
                        isFirstAdded = true
                    } else {
                        consecutiveProfitList.add(earnItem)
                    }
                }

                else -> {
                    addProfitItems(result, consecutiveProfitList)
                    consecutiveProfitList.clear()
                    result.add(earnItem)
                }
            }
        }
        addProfitItems(result, consecutiveProfitList)

        return result
    }

    private fun addProfitItems(
        result: MutableList<EarnItem>,
        consecutiveProfitList: MutableList<EarnItem.Profit>
    ) {
        if (consecutiveProfitList.size == 1) {
            result.add(consecutiveProfitList.first())
        } else if (consecutiveProfitList.size > 1) {
            val lastItem = consecutiveProfitList.last()
            val totalAmount = consecutiveProfitList.sumOf {
                CoinUtils.fromDecimal(it.profit, 9) ?: BigInteger.ZERO
            }
            val newProfitGroup = EarnItem.ProfitGroup(
                id = "${lastItem.timestamp}|${lastItem.profit}",
                timestamp = lastItem.timestamp,
                amount = totalAmount,
                formattedAmount = totalAmount.toString(
                    9,
                    "",
                    totalAmount.smartDecimalsCount(9),
                    false,
                    true
                ),
                profit = CoinUtils.toDecimalString(totalAmount, 9),
                profitItems = mutableListOf<EarnItem.Profit>().apply {
                    addAll(consecutiveProfitList)
                },
                itemTitle = LocaleController.getString("Earned") + " ×${consecutiveProfitList.size}"
            ).apply { updateAmountInBaseCurrency() }
            result.add(newProfitGroup)
        }
    }

    override fun onWalletEvent(walletEvent: WalletEvent) {
        when (walletEvent) {
            is WalletEvent.AccountChanged -> {
                clearMainVariables()
                clearStakingHistoryVariables()
                clearUnstakedItemsVariables()
                clearStakedItemsVariables()
                AccountStore.activeAccountId?.let { activeAccountId ->
                    requestStakingState(activeAccountId)
                }
            }

            WalletEvent.BalanceChanged -> {
                _viewState.tryEmit(
                    viewStateValue().copy(
                        enableAddStakeButton = getTokenBalance() > BigInteger.ZERO
                    )
                )
            }

            WalletEvent.NetworkConnected -> {
                loadOrRefreshStakingData()
            }

            WalletEvent.TokensChanged,
            WalletEvent.BaseCurrencyChanged -> {
                token = TokenStore.getToken(tokenSlug)!!
                viewModelScope.launch {
                    historyItemsMutex.withLock {
                        val updatedItems = withContext(Dispatchers.Default) {
                            historyItems?.map { earnItem ->
                                earnItem.updateAmountInBaseCurrency()
                            }?.toMutableList()
                        }
                        historyItems = updatedItems
                        if (!historyItems.isNullOrEmpty()) {
                            _viewState.tryEmit(
                                viewStateValue().updateHistoryItems(
                                    newHistoryItems = groupConsecutiveProfitItems(historyItems!!),
                                    replace = true
                                )
                            )
                        }
                    }
                }
            }

            WalletEvent.StakingDataUpdated -> {
                AccountStore.stakingData?.let { stakingData ->
                    updateViewState(stakingData)
                    if (token == null || allLoadedOnce) return
                    loadOrRefreshStakingData()
                }
            }

            else -> {}
        }
    }

    override fun onCleared() {
        WalletCore.unregisterObserver(this)

        super.onCleared()
    }
}

class EarnViewModelFactory(private val tokenSlug: String) :
    ViewModelProvider.NewInstanceFactory() {
    override fun <T : ViewModel> create(modelClass: Class<T>): T {
        return EarnViewModel(tokenSlug) as T
    }
}
