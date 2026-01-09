package org.mytonwallet.app_air.walletcore.helpers

import android.content.Context
import android.os.Handler
import android.os.Looper
import org.mytonwallet.app_air.walletbasecontext.logger.Logger
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.helpers.ActivityHelpers.Companion.isSuitableToGetTimestamp
import org.mytonwallet.app_air.walletcore.moshi.MApiTransaction
import org.mytonwallet.app_air.walletcore.stores.ActivityStore
import java.lang.ref.WeakReference
import java.util.concurrent.Executors

interface IActivityLoader {
    interface Delegate {
        fun activityLoaderDataLoaded(isUpdateEvent: Boolean)
        fun activityLoaderCacheNotFound()
        fun activityLoaderLoadedAll()
    }

    val accountId: String
    var showingTransactions: List<MApiTransaction>?
    var loadedAll: Boolean
    fun askForActivities()
    fun useBudgetTransactions()
    fun clean()
}

class ActivityLoader(
    val context: Context,
    override val accountId: String,
    private val selectedSlug: String?,
    private var delegate: WeakReference<IActivityLoader.Delegate>?
) : IActivityLoader, WalletCore.EventObserver {

    private val processorQueue = Executors.newSingleThreadExecutor()

    init {
        WalletCore.registerObserver(this)
    }

    override fun clean() {
        delegate = null
        WalletCore.unregisterObserver(this)
    }

    @Volatile
    override var showingTransactions: List<MApiTransaction>? = null

    @Volatile
    private var allTransactions: List<MApiTransaction>? = null

    private var budgetTransactions: MutableList<MApiTransaction> = mutableListOf()

    @Volatile
    override var loadedAll = false

    @Volatile
    private var isPreparingBudget = false

    @Volatile
    private var isWaitingForBudget = false

    @Volatile
    private var isConsumingBudget = false

    @Volatile
    private var paginationActivity: MApiTransaction? = null

    override fun askForActivities() {
        Logger.d(Logger.LogTag.ACTIVITY_LOADER, "$selectedSlug $this Request to load first page")
        ActivityStore.fetchTransactions(context, accountId, selectedSlug, null, { res ->
            val isFromCache = res.isFromCache
            val transactions = res.transactions
            val loadedAll = res.loadedAll
            Logger.d(
                Logger.LogTag.ACTIVITY_LOADER,
                "$selectedSlug First page - isFromCache: $isFromCache - transactionsCount: ${transactions.size} - loadedAll: $loadedAll"
            )
            // Check if cache not found to notify ui layer
            if (transactions.isEmpty() && isFromCache && !loadedAll) {
                Handler(Looper.getMainLooper()).post {
                    delegate?.get()?.activityLoaderCacheNotFound()
                }
                return@fetchTransactions
            }
            // Add transactions to the existing list
            transactions.lastOrNull()?.let {
                paginationActivity = it
            }
            received(transactions.toList(), false, isFromCache, loadedAll)
            if (!loadedAll) {
                processorQueue.execute {
                    Logger.d(Logger.LogTag.ACTIVITY_LOADER, "$selectedSlug Loaded first page")
                    prepareBudgetActivities()
                }
            }
        })
    }

    override fun useBudgetTransactions() {
        if (isPreparingBudget || isConsumingBudget) {
            isWaitingForBudget = true
            return
        }

        Logger.d(Logger.LogTag.ACTIVITY_LOADER, "$selectedSlug $this Use budget transactions")
        processorQueue.execute {
            isWaitingForBudget = false
            if (budgetTransactions.isNotEmpty()) {
                isConsumingBudget = true
                val budget = budgetTransactions.toList()
                budgetTransactions.clear()
                if (budget.isNotEmpty())
                    received(
                        budget,
                        isUpdateEvent = false,
                        isFromCache = false,
                        loadedAll = loadedAll
                    )
                processorQueue.execute {
                    isConsumingBudget = false
                    prepareBudgetActivities()
                }
            } else {
                if (loadedAll) return@execute
                prepareBudgetActivities()
            }
        }
    }

    private fun prepareBudgetActivities() {
        if (isPreparingBudget) return
        val lastActivity = budgetTransactions.lastOrNull(::isSuitableToGetTimestamp)
            ?: allTransactions?.lastOrNull(::isSuitableToGetTimestamp) ?: return
        val budgetLen = budgetTransactions.size

        if (loadedAll) return
        isPreparingBudget = true

        Logger.d(
            Logger.LogTag.ACTIVITY_LOADER,
            "$selectedSlug / Prepare budget / Budget now: $budgetLen / Loading before: ${paginationActivity?.dt ?: lastActivity.dt}"
        )
        ActivityStore.fetchTransactions(
            context,
            accountId,
            selectedSlug,
            paginationActivity ?: lastActivity
        ) { res ->
            val transactions = res.transactions
            val loadedAll = res.loadedAll
            processorQueue.execute {
                val lastActivityAfterLoad =
                    budgetTransactions.lastOrNull(::isSuitableToGetTimestamp)
                        ?: allTransactions?.lastOrNull(::isSuitableToGetTimestamp)
                if (lastActivity.id != lastActivityAfterLoad?.id) {
                    // Cache invalidated/modified before, this loader method call is not valid anymore.
                    isPreparingBudget = false
                    prepareBudgetActivities()
                    return@execute
                }
                Logger.d(
                    Logger.LogTag.ACTIVITY_LOADER,
                    "$selectedSlug $this Loaded budget: ${transactions.size} / LoadedAll: ${res.loadedAll}"
                )
                transactions.lastOrNull()?.let {
                    paginationActivity = it
                }
                budgetTransactions.addAll(transactions.sortedWith(::sorter))
                if (loadedAll) {
                    this@ActivityLoader.loadedAll = true
                    Handler(Looper.getMainLooper()).post {
                        delegate?.get()?.activityLoaderLoadedAll()
                    }
                }
                if (!res.isFromCache) {
                    Logger.d(
                        Logger.LogTag.ACTIVITY_LOADER,
                        "$selectedSlug Store list after prepare budget"
                    )
                    storeListActivityIds()
                }
                val fetchMore =
                    (ActivityHelpers.filter(accountId, budgetTransactions, true, null)?.size ?: 0) < 60
                isPreparingBudget = false
                if (isWaitingForBudget) {
                    useBudgetTransactions()
                }
                if (fetchMore) {
                    processorQueue.execute {
                        prepareBudgetActivities()
                    }
                }
            }
        }
    }

    private fun received(
        newActivities: List<MApiTransaction>,
        isUpdateEvent: Boolean,
        isFromCache: Boolean,
        loadedAll: Boolean?
    ) {
        processorQueue.execute {
            val currentAllTransactions: ArrayList<MApiTransaction> =
                ArrayList(allTransactions ?: mutableListOf())

            newActivities.forEach { newActivity ->
                val index = currentAllTransactions.indexOfFirst { it.id == newActivity.id }
                if (index != -1) {
                    currentAllTransactions[index] = newActivity
                } else {
                    if (ActivityHelpers.activityBelongsToSlug(newActivity, selectedSlug)) {
                        currentAllTransactions.add(newActivity)
                    }
                }
            }

            currentAllTransactions.removeAll { it.isLocal() }
            currentAllTransactions.removeAll {
                it.isPending()
            }

            ActivityStore.getLocalTransactions()[accountId]?.let {
                currentAllTransactions.addAll(it)
            }
            ActivityStore.getPendingTransactions(accountId).let { pendingTransactions ->
                val pendingIds = pendingTransactions.map { it.getTxHash() }
                currentAllTransactions.removeAll {
                    pendingIds.contains(it.getTxHash())
                }
                currentAllTransactions.addAll(pendingTransactions.filter {
                    ActivityHelpers.activityBelongsToSlug(it, selectedSlug)
                })
            }

            allTransactions = currentAllTransactions.sortedWith(::sorter)
            if (loadedAll == true && !this.loadedAll) {
                Logger.d(Logger.LogTag.ACTIVITY_LOADER, "$selectedSlug received / loadedAll: true")
                Handler(Looper.getMainLooper()).post {
                    delegate?.get()?.activityLoaderLoadedAll()
                }
                this.loadedAll = true
            }

            if (!isFromCache && !isUpdateEvent) {
                Logger.d(
                    Logger.LogTag.ACTIVITY_LOADER,
                    "$selectedSlug - Store list after load from network"
                )
                storeListActivityIds()
            }
            sortAndUpdateShowingTransactions(isUpdateEvent)
        }
    }

    private fun storeListActivityIds() {
        (allTransactions.orEmpty() + budgetTransactions).sortedWith(::sorter).let { transactions ->
            ActivityStore.setListTransactions(
                accountId = accountId,
                slug = selectedSlug,
                activitiesToSave = transactions,
                insertBeforeExistingItems = false,
                overrideLoadedAll = loadedAll
            )
        }
    }

    private fun sortAndUpdateShowingTransactions(isUpdateEvent: Boolean) {
        val showingTransactions = ActivityHelpers.filter(accountId, allTransactions, true, null)
        this.showingTransactions = showingTransactions
        Handler(Looper.getMainLooper()).post {
            delegate?.get()?.activityLoaderDataLoaded(isUpdateEvent)
        }
    }

    private fun sorter(t1: MApiTransaction, t2: MApiTransaction): Int {
        return when {
            t1.timestamp != t2.timestamp -> t2.timestamp.compareTo(t1.timestamp)
            else -> t2.id.compareTo(t1.id)
        }
    }

    override fun onWalletEvent(walletEvent: WalletEvent) {
        when (walletEvent) {
            is WalletEvent.ReceivedNewActivities -> {
                if (walletEvent.accountId == accountId) {
                    Logger.d(
                        Logger.LogTag.ACTIVITY_LOADER,
                        "$selectedSlug $this ReceivedNewActivities: ${walletEvent.newActivities?.size}"
                    )
                    received(
                        walletEvent.newActivities?.toList() ?: emptyList(),
                        isUpdateEvent = walletEvent.isUpdateEvent == true,
                        isFromCache = false,
                        loadedAll = walletEvent.loadedAll
                    )
                }
            }

            is WalletEvent.InvalidateCache -> {
                if (walletEvent.accountId == accountId && walletEvent.tokenSlug == selectedSlug) {
                    processorQueue.execute {
                        allTransactions = emptyList()
                        budgetTransactions.clear()
                        paginationActivity = null
                        loadedAll = false
                    }
                }
            }

            WalletEvent.HideTinyTransfersChanged -> {
                processorQueue.execute {
                    sortAndUpdateShowingTransactions(false)
                }
            }

            else -> {}
        }
    }
}
