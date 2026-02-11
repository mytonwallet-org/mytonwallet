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

// Interface ///////////////////////////////////////////////////////////////////////////////////
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

/**
 * ActivityLoader manages the pagination and display of activities for a specific account/token.
 *
 * ## Architecture Overview:
 * - Coordinates between ActivityStore (data layer) and UI (delegate)
 * - Implements a "budget" pre-fetching mechanism for smooth scrolling
 * - Handles real-time activity updates via WalletEvent observer
 *
 * ## Data Flow:
 * 1. UI calls askForActivities() -> loads first page from cache/network
 * 2. After first page, prepareBudgetActivities() pre-fetches next page
 * 3. When user scrolls near end, UI calls useBudgetTransactions() to consume pre-fetched data
 * 4. Real-time updates come via onWalletEvent() -> ReceivedNewActivities
 *
 * ## Transaction Lists:
 * - ActivityStore holds all transaction data (via getAllTransactions)
 * - showingTransactions: Filtered activities shown to user (excludes tiny/scam if enabled)
 * - budgetTransactions: Pre-fetched activities waiting to be consumed (IDs only)
 */
class ActivityLoader(
    val context: Context,
    override val accountId: String,
    private val selectedSlug: String?,
    private var delegate: WeakReference<IActivityLoader.Delegate>?
) : IActivityLoader, WalletCore.EventObserver {

    companion object {
        private const val MIN_BUDGET_SIZE = 60
    }

    // State ///////////////////////////////////////////////////////////////////////////////////////
    // Current state of budget (pre-fetch) operations
    private sealed class BudgetState {
        data object Idle : BudgetState()      // No budget operation in progress
        data object Preparing : BudgetState() // Currently fetching budget transactions
        data object Consuming : BudgetState() // Currently moving budget to showing list
    }

    private val processorQueue = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    // Transaction lists
    @Volatile
    override var showingTransactions: List<MApiTransaction>? = null

    // Pre-fetched transaction IDs waiting to be consumed (for smooth scrolling)
    private var allTransactionIds: List<String> = listOf()
    private var budgetIds: MutableList<String> = mutableListOf()

    // Pagination state
    @Volatile
    override var loadedAll = false

    @Volatile
    private var paginationActivity: MApiTransaction? = null

    // Budget state management
    @Volatile
    private var budgetState: BudgetState = BudgetState.Idle

    @Volatile
    private var budgetRequestPending = false

    @Volatile
    private var isCleared = false

    // Lifecycle ///////////////////////////////////////////////////////////////////////////////////
    init {
        WalletCore.registerObserver(this)
    }

    override fun clean() {
        isCleared = true
        delegate = null
        WalletCore.unregisterObserver(this)
    }

    // Public API //////////////////////////////////////////////////////////////////////////////////
    // Request the first page of activities
    override fun askForActivities() {
        Logger.d(Logger.LogTag.ACTIVITY_LOADER, "askForActivities: accountId=$accountId slug=$selectedSlug")
        ActivityStore.fetchTransactions(
            context = context,
            accountId = accountId,
            tokenSlug = selectedSlug,
            before = null,
            isCancelled = { isCleared }
        ) { result ->
            handleFirstPageResult(result)
        }
    }

    // Consume pre-fetched budget transactions. Called when user scrolls near the end.
    override fun useBudgetTransactions() {
        processorQueue.execute {
            // If budget operation is in progress, mark that we want to consume when ready
            if (budgetState != BudgetState.Idle) {
                budgetRequestPending = true
                return@execute
            }
            consumeBudgetTransactionsInternal()
        }
    }

    // First Page Loading //////////////////////////////////////////////////////////////////////////
    private fun handleFirstPageResult(result: ActivityStore.FetchResult) {
        val (transactions, isFromCache, resultLoadedAll) = result

        Logger.d(
            Logger.LogTag.ACTIVITY_LOADER,
            "handleFirstPageResult: slug=$selectedSlug isFromCache=$isFromCache count=${transactions.size} loadedAll=$resultLoadedAll"
        )

        // Notify UI if cache is empty (so it can show loading state)
        if (transactions.isEmpty() && isFromCache && !resultLoadedAll) {
            mainHandler.post {
                delegate?.get()?.activityLoaderCacheNotFound()
            }
            return
        }

        // Update pagination cursor
        transactions.lastOrNull()?.let { paginationActivity = it }

        // Process the received transactions
        processReceivedActivities(
            newActivities = transactions,
            eventType = WalletEvent.ReceivedNewActivities.EventType.PAGINATE,
            isFromCache = isFromCache,
            loadedAll = resultLoadedAll
        )

        // Start pre-fetching next page if more data available
        if (!resultLoadedAll) {
            processorQueue.execute {
                prepareBudgetActivities()
            }
        }
    }

    // Budget (Pre-fetch) Management ///////////////////////////////////////////////////////////////
    /**
     * Pre-fetch the next page of activities for smooth scrolling.
     *
     * The "budget" system works by fetching activities ahead of user scroll position.
     * When the user scrolls near the end of the current list, useBudgetTransactions()
     * is called to instantly append the pre-fetched activities, avoiding loading delays.
     *
     * @return true if a fetch request was started, false otherwise
     */
    private fun prepareBudgetActivities(): Boolean {
        // Guard: Don't prepare if already in progress
        if (budgetState == BudgetState.Preparing) return false

        if (!shouldFetchMoreBudget())
            return false

        // Find the activity to paginate from
        val lastActivity = findLastPaginationActivity() ?: return false

        budgetState = BudgetState.Preparing

        Logger.d(
            Logger.LogTag.ACTIVITY_LOADER,
            "prepareBudgetActivities: accountId=$accountId slug=$selectedSlug budgetSize=${budgetIds.size} before=${paginationActivity?.dt ?: lastActivity.dt}"
        )

        ActivityStore.fetchTransactions(
            context = context,
            accountId = accountId,
            tokenSlug = selectedSlug,
            before = paginationActivity ?: lastActivity,
            isCancelled = { isCleared }
        ) { result ->
            handleBudgetFetchResult(result, lastActivity)
        }

        return true
    }

    /**
     * Handle result from budget fetch request.
     *
     * Validates that the list hasn't changed during the async fetch.
     * If invalidated (e.g., by a real-time update), discards results and re-fetches.
     */
    private fun handleBudgetFetchResult(
        result: ActivityStore.FetchResult,
        lastActivityBeforeFetch: MApiTransaction
    ) {
        processorQueue.execute {
            // Validate that the list hasn't changed during fetch (may happen with real-time updates)
            val currentLastActivity = findLastPaginationActivity()
            if (lastActivityBeforeFetch.id != currentLastActivity?.id) {
                Logger.d(
                    Logger.LogTag.ACTIVITY_LOADER,
                    "handleBudgetFetchResult: Budget invalidated accountId=$accountId slug=$selectedSlug"
                )
                budgetState = BudgetState.Idle
                prepareBudgetActivities()
                return@execute
            }

            Logger.d(
                Logger.LogTag.ACTIVITY_LOADER,
                "handleBudgetFetchResult: accountId=$accountId slug=$selectedSlug isFromCache=${result.isFromCache} loaded=${result.transactions.size} loadedAll=${result.loadedAll}"
            )

            // Update pagination cursor
            result.transactions.lastOrNull()?.let { paginationActivity = it }

            // Add to budget IDs (sorted by timestamp desc, then by id desc)
            val sortedIds = result.transactions
                .sortedWith(ActivityHelpers::sorter)
                .map { it.id }
            budgetIds.addAll(sortedIds)

            // Handle end of history
            if (result.loadedAll) {
                this.loadedAll = true
                mainHandler.post {
                    delegate?.get()?.activityLoaderLoadedAll()
                }
            }

            // Persist if loaded from network
            if (shouldPersist(
                    isFromCache = result.isFromCache,
                    eventType = WalletEvent.ReceivedNewActivities.EventType.PAGINATE
                )
            ) {
                persistTransactionList()
            }

            budgetState = BudgetState.Idle

            // Check if UI is waiting for budget
            if (budgetRequestPending) {
                consumeBudgetTransactionsInternal()
            }

            // Continue fetching if budget is still small
            processorQueue.execute { prepareBudgetActivities() }
        }
    }

    /**
     * Move budget transactions to the showing list.
     *
     * Called when user scrolls near the end of current list.
     * Immediately appends pre-fetched activities for seamless experience.
     */
    private fun consumeBudgetTransactionsInternal() {
        budgetRequestPending = false

        if (budgetIds.isNotEmpty()) {
            Logger.d(
                Logger.LogTag.ACTIVITY_LOADER,
                "consumeBudgetTransactionsInternal: accountId=$accountId slug=$selectedSlug budgetSize=${budgetIds.size}"
            )

            // Transfer budget IDs to showing list
            allTransactionIds = allTransactionIds + budgetIds
            budgetState = BudgetState.Consuming
            budgetIds.clear()

            // Update UI with latest data from ActivityStore
            updateShowingTransactions(isUpdateEvent = false)

            // Reset state and start pre-fetching next batch
            processorQueue.execute {
                budgetState = BudgetState.Idle
                prepareBudgetActivities()
            }
        } else if (!loadedAll) {
            // No budget available - start fetching and mark pending
            val requestInProgress = prepareBudgetActivities()
            if (requestInProgress) {
                budgetRequestPending = true
            }
        }
    }

    /**
     * Find the oldest activity suitable for pagination cursor.
     *
     * Searches from the end (oldest) of both budget and showing lists.
     * Only returns activities suitable for timestamp-based pagination
     * (excludes local/pending transactions that lack valid timestamps).
     */
    private fun findLastPaginationActivity(): MApiTransaction? {
        // First check budget (contains newer activities that haven't been shown yet)
        for (i in budgetIds.indices.reversed()) {
            val tx = ActivityStore.getTransaction(accountId, budgetIds[i])
            if (tx != null && isSuitableToGetTimestamp(tx)) {
                return tx
            }
        }

        // Then check showing list
        for (i in allTransactionIds.indices.reversed()) {
            val tx = ActivityStore.getTransaction(accountId, allTransactionIds[i])
            if (tx != null && isSuitableToGetTimestamp(tx)) {
                return tx
            }
        }

        return null
    }

    /**
     * Check if more budget activities should be fetched.
     *
     * Returns true if:
     * - Filtered budget size is below MIN_BUDGET_SIZE threshold
     * - AND history end hasn't been reached yet
     */
    private fun shouldFetchMoreBudget(): Boolean {
        val budgetTransactions =
            budgetIds.mapNotNull { ActivityStore.getTransaction(accountId, it) }
        val filteredBudgetSize = ActivityHelpers.filter(
            accountId = accountId,
            array = budgetTransactions,
            hideTinyIfRequired = true,
            checkSlug = null
        )?.size ?: 0
        return filteredBudgetSize < MIN_BUDGET_SIZE && !loadedAll
    }

    // Activity Processing /////////////////////////////////////////////////////////////////////////
    /**
     * Process newly received activities (from cache, network, or real-time events).
     *
     * Handles different event types:
     * - PAGINATE: Regular pagination load (first page or budget fetch)
     * - ACCOUNT_INITIALIZE: Initial load from SDK (resets budget state)
     * - UPDATE: Real-time update from SDK polling
     *
     * Updates allTransactionIds, persists if needed, and refreshes UI.
     */
    private fun processReceivedActivities(
        newActivities: List<MApiTransaction>,
        eventType: WalletEvent.ReceivedNewActivities.EventType,
        isFromCache: Boolean,
        loadedAll: Boolean?
    ) {
        processorQueue.execute {
            val isMainActivitiesInitialize = isAccountInitializeEvent(eventType)

            // Handle AccountInitialize special case
            if (isMainActivitiesInitialize) {
                allTransactionIds =
                    ActivityStore.getAllTransactions(accountId, selectedSlug)?.toMutableList()
                        ?: mutableListOf()
                handleAccountInitialize(newActivities.isEmpty())
            } else {
                allTransactionIds =
                    (newActivities.filter {
                        ActivityHelpers.activityBelongsToSlug(
                            it,
                            selectedSlug
                        )
                    }.map { it.id } + allTransactionIds).distinct()
                // Handle loadedAll flag
                handleLoadedAllFlag(loadedAll)
            }

            // Persist to storage if needed
            if (shouldPersist(isFromCache, eventType)) {
                persistTransactionList()
            }

            // Update UI
            val isUpdateEvent = eventType != WalletEvent.ReceivedNewActivities.EventType.PAGINATE
            updateShowingTransactions(isUpdateEvent)

            // Start budget preparation for AccountInitialize
            if (eventType == WalletEvent.ReceivedNewActivities.EventType.ACCOUNT_INITIALIZE) {
                val activityCount = ActivityStore.getActivityCount(accountId, selectedSlug)
                if (selectedSlug == null && activityCount > 0) {
                    // Must reload budget after merging mainActivities
                    prepareBudgetActivities()
                } else if (selectedSlug != null) {
                    if (activityCount == 0) {
                        // No activities received on initial, load token activity list.
                        askForActivities()
                    } else {
                        prepareBudgetActivities()
                    }
                }
            }
        }
    }

    private fun isAccountInitializeEvent(eventType: WalletEvent.ReceivedNewActivities.EventType): Boolean {
        return eventType == WalletEvent.ReceivedNewActivities.EventType.ACCOUNT_INITIALIZE &&
            selectedSlug == null
    }

    /**
     * Reset loader state for account initialization.
     *
     * Clears budget, resets pagination cursor, and updates history end flag.
     * If no transactions exist (empty account), marks history as fully loaded.
     * Called when SDK provides initial activities (e.g., re-login, account switch).
     */
    private fun handleAccountInitialize(newChainIsEmpty: Boolean) {
        budgetIds.clear()
        if (allTransactionIds.isEmpty()) {
            this.loadedAll = true
        } else if (!newChainIsEmpty) {
            this.loadedAll = false
        }
        paginationActivity = findLastPaginationActivity()
    }

    private fun handleLoadedAllFlag(loadedAll: Boolean?) {
        if (loadedAll == true && !this.loadedAll) {
            mainHandler.post {
                delegate?.get()?.activityLoaderLoadedAll()
            }
            this.loadedAll = true
        }
    }

    private fun shouldPersist(
        isFromCache: Boolean,
        eventType: WalletEvent.ReceivedNewActivities.EventType
    ): Boolean {
        return !isFromCache && eventType == WalletEvent.ReceivedNewActivities.EventType.PAGINATE
    }

    // Persistence /////////////////////////////////////////////////////////////////////////////////
    /**
     * Persist the current transaction list to storage via ActivityStore.
     *
     * Combines showing transactions and budget, sorts by timestamp,
     * and delegates to ActivityStore for actual persistence.
     */
    private fun persistTransactionList() {
        // Get all transactions from ActivityStore plus budget
        val storeTransactions =
            allTransactionIds.mapNotNull { ActivityStore.getTransaction(accountId, it) }
        val budgetTransactions =
            budgetIds.mapNotNull { ActivityStore.getTransaction(accountId, it) }
        val allActivities = (storeTransactions + budgetTransactions)
            .distinctBy { it.id }
            .sortedWith(ActivityHelpers::sorter)

        Logger.d(
            Logger.LogTag.ACTIVITY_LOADER,
            "persistTransactionList: accountId=$accountId slug=$selectedSlug count=${allActivities.size}"
        )

        ActivityStore.setListTransactions(
            accountId = accountId,
            slug = selectedSlug,
            activitiesToSave = allActivities,
            afterPaginate = true,
            loadedAll = loadedAll
        )
    }

    // UI Update ///////////////////////////////////////////////////////////////////////////////////
    /**
     * Refresh the showingTransactions list and notify the delegate.
     *
     * Fetches latest data from ActivityStore, applies filters (tiny/scam),
     * and includes local/pending transactions at the top.
     *
     * @param isUpdateEvent true if this is a real-time update (not pagination)
     */
    private fun updateShowingTransactions(isUpdateEvent: Boolean) {
        val allTransactions =
            allTransactionIds
                .mapNotNull { ActivityStore.getTransaction(accountId, it) } +
                ActivityStore.getLocalAndPendingActivities(accountId, selectedSlug).orEmpty()
        val filtered = ActivityHelpers.filter(
            accountId = accountId,
            array = allTransactions,
            hideTinyIfRequired = true,
            checkSlug = null,
        )?.sortedWith(ActivityHelpers::sorter)
        this.showingTransactions = filtered

        mainHandler.post {
            delegate?.get()?.activityLoaderDataLoaded(isUpdateEvent)
        }
    }

    // Event Handling //////////////////////////////////////////////////////////////////////////////
    override fun onWalletEvent(walletEvent: WalletEvent) {
        when (walletEvent) {
            is WalletEvent.ReceivedNewActivities -> handleReceivedNewActivities(walletEvent)
            WalletEvent.HideTinyTransfersChanged -> handleHideTinyTransfersChanged()
            else -> {}
        }
    }

    private fun handleReceivedNewActivities(event: WalletEvent.ReceivedNewActivities) {
        if (event.accountId != accountId) return

        Logger.d(
            Logger.LogTag.ACTIVITY_LOADER,
            "handleReceivedNewActivities: accountId=$accountId slug=$selectedSlug count=${event.newActivities?.size}"
        )

        processReceivedActivities(
            newActivities = event.newActivities?.toList() ?: emptyList(),
            eventType = event.eventType,
            isFromCache = false,
            loadedAll = null
        )
    }

    private fun handleHideTinyTransfersChanged() {
        processorQueue.execute {
            updateShowingTransactions(isUpdateEvent = false)
        }
    }
}
