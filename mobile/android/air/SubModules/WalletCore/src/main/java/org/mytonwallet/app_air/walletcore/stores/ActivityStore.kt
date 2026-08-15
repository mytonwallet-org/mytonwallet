package org.mytonwallet.app_air.walletcore.stores

import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import java.util.Collections
import java.util.concurrent.ConcurrentHashMap
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.launch
import org.json.JSONObject
import org.mytonwallet.app_air.walletbasecontext.logger.Logger
import org.mytonwallet.app_air.walletbasecontext.utils.add
import org.mytonwallet.app_air.walletcontext.WalletContextManager
import org.mytonwallet.app_air.walletcontext.globalStorage.IGlobalStorageProvider
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.helpers.AudioHelpers
import org.mytonwallet.app_air.walletcontext.utils.ensureMainThread
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.helpers.ActivityHelpers
import org.mytonwallet.app_air.walletcore.helpers.ActivityHelpers.Companion.isSuitableToGetTimestamp
import org.mytonwallet.app_air.walletcore.helpers.PoisoningCacheHelper
import org.mytonwallet.app_air.walletcore.models.blockchain.MBlockchain
import org.mytonwallet.app_air.walletcore.moshi.ApiTransactionType
import org.mytonwallet.app_air.walletcore.moshi.MApiActivitiesPatch
import org.mytonwallet.app_air.walletcore.moshi.MApiFetchSwapItem
import org.mytonwallet.app_air.walletcore.moshi.MApiFetchSwapsResult
import org.mytonwallet.app_air.walletcore.moshi.MApiReconcileActivityUpdateResult
import org.mytonwallet.app_air.walletcore.moshi.MApiTransaction
import org.mytonwallet.app_air.walletcore.moshi.api.ApiMethod

/** Runs suspending store mutations FIFO so each reconciliation commits before the next snapshot is read. */
internal class SerialSuspendTaskQueue {
    private val tasks = Channel<suspend () -> Unit>(Channel.UNLIMITED)
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    init {
        scope.launch {
            for (task in tasks) {
                try {
                    task()
                } catch (error: CancellationException) {
                    throw error
                } catch (error: Exception) {
                    Logger.e(
                        Logger.LogTag.ACTIVITY_STORE,
                        "ActivityStore queue task failed: $error"
                    )
                }
            }
        }
    }

    fun execute(task: suspend () -> Unit) {
        if (tasks.trySend(task).isFailure) {
            Logger.e(Logger.LogTag.ACTIVITY_STORE, "ActivityStore queue is unavailable")
        }
    }
}

/** Keeps temporary and SDK-owned CEX state ahead of bulk history while enforcing the context limit. */
internal fun <T> selectBoundedCexRefreshContext(
    activeCexActivities: List<T>,
    cexProjectionActivities: List<T> = emptyList(),
    localActivities: List<T>,
    pendingActivities: List<T>,
    incomingActivities: List<T>,
    recentActivities: List<T>,
    limit: Int,
    getId: (T) -> String
): List<T> {
    val byId = LinkedHashMap<String, T>()
    fun include(activity: T) {
        if (byId.size < limit) byId.putIfAbsent(getId(activity), activity)
    }

    listOf(
        activeCexActivities,
        cexProjectionActivities,
        localActivities,
        pendingActivities,
        incomingActivities,
        recentActivities
    )
        .forEach { activities -> activities.forEach(::include) }
    return byId.values.toList()
}

/** Leaves incoming local rows with local-state ownership while forwarding SDK changes to all other rows. */
internal fun <T> excludeIncomingLocalPatchUpserts(
    upsert: List<T>,
    incomingLocalIds: Set<String>,
    getId: (T) -> String
): List<T> = upsert.filter { !incomingLocalIds.contains(getId(it)) }

/** Uses ordered main-list IDs for bounded local reconciliation instead of unordered cache-map iteration. */
internal fun <T> selectRecentNonLocalActivities(
    ids: List<String>,
    byId: Map<String, T>,
    maxCount: Int,
    isLocal: (T) -> Boolean
): List<T> {
    val result = mutableListOf<T>()
    for (id in ids) {
        if (result.size >= maxCount) break
        val activity = byId[id] ?: continue
        if (!isLocal(activity)) result.add(activity)
    }
    return result
}

/** Limits activity event payloads to rows that changed and remain visible. */
internal fun <T> selectUpdatedVisibleActivities(
    updatedIds: List<String>,
    byId: Map<String, T>,
    isVisible: (T) -> Boolean
): List<T> = updatedIds.mapNotNull(byId::get).filter(isVisible)

internal fun processReplacedStableIdsFromSdkPatch(
    previousActivities: List<MApiTransaction>,
    replacementActivities: List<MApiTransaction>,
    replacedIds: Map<String, String>,
    visibleReplacementActivities: List<MApiTransaction> = emptyList()
) {
    val previousById = previousActivities.associateBy { it.id }
    val visibleReplacementById = if (visibleReplacementActivities.isEmpty()) {
        emptyMap()
    } else {
        visibleReplacementActivities.associateBy { it.id }
    }
    val stableIdByNewId = HashMap<String, String>(replacedIds.size)

    for ((oldId, newId) in replacedIds) {
        val oldActivity = previousById[oldId] ?: continue
        stableIdByNewId[newId] =
            visibleReplacementById[newId]?.getStableId() ?: oldActivity.getStableId()
    }
    for (activity in replacementActivities) {
        activity.replacedStableId = stableIdByNewId[activity.id] ?: continue
    }
}

/** Applies the SDK by-ID patch verbatim; presentation indexes are updated separately. */
internal fun <T> applyAuthoritativePatchById(
    byId: MutableMap<String, T>,
    removeIds: List<String>,
    upserts: List<T>,
    getId: (T) -> String
): List<String> {
    val changedIds = linkedSetOf<String>()
    for (id in removeIds) {
        if (byId.remove(id) != null) changedIds.add(id)
    }
    for (activity in upserts) {
        val id = getId(activity)
        if (byId[id] != activity) changedIds.add(id)
        byId[id] = activity
    }
    return changedIds.toList()
}

/** Implements pending snapshot semantics: omitted keeps, empty clears, and non-empty replaces one chain. */
internal fun <K, T> replacePendingBucket(
    current: Map<K, List<T>>,
    key: K?,
    incoming: List<T>?
): Map<K, List<T>> {
    if (key == null || incoming == null) return current
    if (incoming.isEmpty()) return current - key
    return current + (key to incoming)
}

/** Selects the previous chain snapshot that an explicit pending update must evict before replacement. */
internal fun <K, T> selectPendingIdsToReplace(
    current: Map<K, List<T>>,
    key: K?,
    incoming: List<T>?,
    getId: (T) -> String
): Set<String> {
    if (key == null || incoming == null) return emptySet()
    return current[key].orEmpty().mapTo(linkedSetOf(), getId)
}

/** Propagates authoritative SDK removals and status changes through every pending-chain snapshot. */
internal fun <K, T> applyPatchToPendingBuckets(
    current: Map<K, List<T>>,
    removeIds: Set<String>,
    upsert: List<T>,
    getId: (T) -> String,
    isPending: (T) -> Boolean
): Map<K, List<T>> {
    val upsertById = upsert.associateBy(getId)
    return current.mapNotNull { (key, activities) ->
        activities
            .filterNot { removeIds.contains(getId(it)) }
            .map { upsertById[getId(it)] ?: it }
            .filter(isPending)
            .takeIf { it.isNotEmpty() }
            ?.let { key to it }
    }.toMap()
}

/**
 * ActivityStore is the central data store for transaction/activity data.
 *
 * ## Responsibilities:
 * - Caching activities in memory for fast access
 * - Persisting activities to WGlobalStorage
 * - Fetching activities from cache or network (lazy loading)
 * - Processing incoming activities from SDK events
 * - Playing notification sounds for incoming transactions
 * - Broadcasting activity events to observers (via WalletCore)
 *
 * ## Data Storage:
 * All per-account state is stored in AccountActivityState:
 * - cachedTransactions: In-memory map of all activities by ID (for quick lookups)
 * - localTransactions: Locally-created transactions (not yet confirmed on chain)
 * - pendingTransactionsByChain: Transactions in pending state (sent but not yet confirmed), grouped by chain
 * - newestActivitiesBySlug: Most recent activity for each token (for timestamp tracking)
 * - idsMain: Ordered activity IDs for main list (in-memory cache, persisted to WGlobalStorage)
 * - idsBySlug: Ordered activity IDs per token slug (in-memory cache, persisted to WGlobalStorage)
 *
 * ## Thread Safety:
 * - Write operations are queued via backgroundQueue (serial suspend queue)
 * - ConcurrentHashMap enables safe cross-thread reads
 * - beginTransaction/endTransaction manage WGlobalStorage sync boundaries
 *
 * ## Event Flow:
 * SDK Events → processReceivedActivitiesOnQueue() → cache update → WalletCore.notifyEvent() → ActivityLoader
 */
object ActivityStore : IStore, WalletCore.EventObserver {

    // Constants ///////////////////////////////////////////////////////////////////////////////////
    private const val DEFAULT_LIMIT = 60
    private const val MAX_ITEMS_TO_CACHE_IN_LIST = 200
    private const val NEW_TRANSACTION_THRESHOLD_SECONDS = 60
    private const val CEX_SWAP_REFRESH_INTERVAL_MS = 3_000L
    private const val CEX_SWAP_REFRESH_INTERVAL_NOT_FOCUSED_MS = 15_000L
    private const val CEX_SWAP_REFRESH_CONTEXT_LIMIT = 250

    // Thread management ///////////////////////////////////////////////////////////////////////////
    private val backgroundQueue = SerialSuspendTaskQueue()
    private val mainHandler = Handler(Looper.getMainLooper())

    // In-memory caches ////////////////////////////////////////////////////////////////////////////
    // All activity state indexed by accountId
    private var accountStates = ConcurrentHashMap<String, AccountActivityState>()

    private fun getOrCreateAccountState(accountId: String): AccountActivityState =
        accountStates.getOrPut(accountId) {
            AccountActivityState()
        }

    // CEX swap reconciliation state //////////////////////////////////////////////////////////////
    private val cexSwapRefreshTick = Runnable {
        backgroundQueue.execute { onCexSwapRefreshTick() }
    }

    @Volatile
    private var hasPendingCexSwapTick: Boolean = false

    @Volatile
    private var isAppFocused: Boolean = true

    // IDs of transactions that have already triggered a notification sound
    private val notifiedIds: MutableSet<String> =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            ConcurrentHashMap.newKeySet()
        } else {
            Collections.synchronizedSet(mutableSetOf())
        }

    // Data classes ////////////////////////////////////////////////////////////////////////////////

    /**
     * Holds all activity-related state for a single account.
     *
     * @property cachedTransactions In-memory map of all activities by ID (for quick lookups)
     * @property localTransactions Locally-created transactions (not yet confirmed on chain)
     * @property pendingTransactionsByChain Transactions in pending state, grouped by chain
     * @property newestActivitiesBySlug Most recent activity for each token (for timestamp tracking)
     * @property idsMain Ordered list of activity IDs for the main (all activities) list
     * @property idsBySlug Ordered list of activity IDs per token slug
     */
    data class AccountActivityState(
        var cachedTransactions: MutableMap<String, MApiTransaction> = ConcurrentHashMap(),
        @Volatile
        var localTransactions: List<MApiTransaction> = emptyList(),
        @Volatile
        var pendingTransactionsByChain: Map<MBlockchain, List<MApiTransaction>> = emptyMap(),
        var newestActivitiesBySlug: MutableMap<String, JSONObject> = mutableMapOf(),
        var idsMain: List<String> = emptyList(),
        var idsBySlug: MutableMap<String, List<String>> = HashMap()
    ) {
        val pendingTransactions: List<MApiTransaction>
            get() = pendingTransactionsByChain.values.flatten()
    }

    // Result of a fetch operation, indicating source and completion status
    data class FetchResult(
        val transactions: List<MApiTransaction>,
        val isFromCache: Boolean,
        val loadedAll: Boolean
    )

    // Lifecycle / Initialization //////////////////////////////////////////////////////////////////

    /**
     * Reload all cached data from global storage.
     * Called during app startup to restore persisted activities.
     */
    fun loadFromCache() {
        WalletCore.registerObserver(this)
        backgroundQueue.execute {
            for (accountId in WGlobalStorage.accountIds()) {
                loadAccountFromCache(accountId)
            }
            scheduleCexSwapRefreshIfNeeded()
        }
    }

    private fun loadAccountFromCache(accountId: String) {
        val existingDict = WGlobalStorage.getActivitiesDict(accountId) ?: JSONObject()
        val transactions = ArrayList<MApiTransaction>()

        for (key in existingDict.keys().asSequence().toList()) {
            MApiTransaction.fromJson(existingDict.getJSONObject(key))?.let {
                transactions.add(it)
            }
        }

        addCachedTransactions(accountId, transactions.toTypedArray())
        clearPendingTransactions(accountId)

        val accountState = getOrCreateAccountState(accountId)
        accountState.newestActivitiesBySlug =
            WGlobalStorage.getNewestActivitiesBySlug(accountId)?.toMutableMap() ?: mutableMapOf()

        // Load IDs from storage into memory
        accountState.idsMain =
            WGlobalStorage.getActivityIds(accountId, null)?.toList() ?: emptyList()
        // Load per-slug IDs (we'll load them lazily when needed)
    }

    override fun wipeData() {
        clearCache()
    }

    override fun clearCache() {
        backgroundQueue.execute { cancelCexSwapRefreshTick() }
        accountStates = ConcurrentHashMap()
    }

    fun removeAccount(removingAccountId: String) {
        backgroundQueue.execute {
            accountStates.remove(removingAccountId)
        }
    }

    // Public Data Access //////////////////////////////////////////////////////////////////////////
    fun getLocalTransactions(): Map<String, List<MApiTransaction>> = accountStates.mapValues {
        it.value.localTransactions
    }

    fun getNewestActivityTimestamps(accountId: String): JSONObject? {
        // Check if cache is valid. It may be cleared in CapacitorGlobalStorageProvider.
        if (!WGlobalStorage.hasCachedActivities(accountId, null)) {
            accountStates[accountId]?.newestActivitiesBySlug?.clear()
            return null
        }
        return accountStates[accountId]?.newestActivitiesBySlug
            ?.mapValues { (_, value) -> value.optLong("timestamp") }
            ?.let { JSONObject(it) }
    }

    fun getAllTransactions(accountId: String, slug: String?): List<String>? {
        val accountState = accountStates[accountId] ?: return null
        val ids = getActivityIds(accountId, slug)
        if (ids.isEmpty() && accountState.cachedTransactions.isEmpty()) return null

        return ids
    }

    fun getLocalAndPendingActivities(accountId: String, slug: String?): List<MApiTransaction>? {
        val accountState = accountStates[accountId] ?: return null
        return (accountState.pendingTransactions + accountState.localTransactions)
            .filter { ActivityHelpers.activityBelongsToSlug(it, slug) }.distinctBy { it.id }
    }

    /**
     * Get a cached transaction by ID.
     */
    fun getTransaction(accountId: String, transactionId: String): MApiTransaction? =
        accountStates[accountId]?.cachedTransactions?.get(transactionId)

    /**
     * Get the count of cached activity IDs for an account/slug.
     */
    fun getActivityCount(accountId: String, slug: String?): Int =
        getActivityIds(accountId, slug).size

    // Fetch Operations ////////////////////////////////////////////////////////////////////////////

    /**
     * Fetch transactions for display.
     *
     * Strategy:
     * 1. Check in-memory/storage cache first
     * 2. If cache miss and not end of history, fetch from network
     * 3. Network failures trigger automatic retry after 3s delay
     *
     * @param before Transaction to paginate from (null for first page)
     * @param isCancelled Cancellation check callback (e.g., when loader is cleared)
     * @param callback Returns FetchResult with transactions, source flag, and loadedAll flag
     */
    fun fetchTransactions(
        context: Context,
        accountId: String,
        tokenSlug: String?,
        before: MApiTransaction?,
        isCancelled: () -> Boolean = { false },
        callback: (FetchResult) -> Unit
    ) {
        backgroundQueue.execute {
            val shouldStopAfterCache = fetchFromCache(
                accountId = accountId,
                tokenSlug = tokenSlug,
                beforeId = before?.id,
                callback = callback
            )

            if (shouldStopAfterCache) return@execute

            when (before) {
                null if tokenSlug == null -> {
                    // First page of main activities will be received in InitialActivities event.
                    return@execute
                }

                null if accountStates[accountId]?.cachedTransactions.isNullOrEmpty() &&
                    !WGlobalStorage.isHistoryEndReached(accountId, null) -> {
                    // Waiting for InitialActivities yet, then request will be sent from ActivityLoader if necessary.
                    return@execute
                }

                else -> {
                    fetchFromNetwork(
                        context = context,
                        accountId = accountId,
                        tokenSlug = tokenSlug,
                        before = before,
                        isCancelled = isCancelled,
                        callback = callback
                    )
                }
            }
        }
    }

    // Returns true if we should stop (cache hit or end of history), false if network fetch needed
    private fun fetchFromCache(
        accountId: String,
        tokenSlug: String?,
        beforeId: String?,
        callback: (FetchResult) -> Unit
    ): Boolean {
        val transactions = getTransactionList(accountId, tokenSlug, beforeId)
        val isHistoryEndReached = WGlobalStorage.isHistoryEndReached(accountId, tokenSlug)

        // Cache hit - return cached data
        if (transactions.isNotEmpty()) {
            callback(FetchResult(transactions, isFromCache = true, loadedAll = isHistoryEndReached))
            return true
        }

        val isLoadingMore = beforeId != null

        // End of history reached during pagination - no more data
        if (isHistoryEndReached && isLoadingMore) {
            callback(FetchResult(emptyList(), isFromCache = true, loadedAll = true))
            return true
        }

        // First page with no cache - notify UI that we're waiting for network
        if (beforeId == null) {
            callback(FetchResult(emptyList(), isFromCache = true, loadedAll = isHistoryEndReached))
        }

        return false
    }

    private fun fetchFromNetwork(
        context: Context,
        accountId: String,
        tokenSlug: String?,
        before: MApiTransaction?,
        isCancelled: () -> Boolean,
        callback: (FetchResult) -> Unit
    ) {
        fun retry() {
            mainHandler.postDelayed({
                if (!isCancelled()) {
                    fetchFromNetwork(context, accountId, tokenSlug, before, isCancelled, callback)
                }
            }, 3000)
        }

        fun handleSuccess(result: ApiMethod.WalletData.FetchPastActivities.Result) {
            val fetchedTransactions = result.activities
            backgroundQueue.execute {
                try {
                    processReceivedActivitiesOnQueue(
                        context = context,
                        accountId = accountId,
                        newActivities = fetchedTransactions,
                        pendingActivities = null,
                        eventType = WalletEvent.ReceivedNewActivities.EventType.PAGINATE
                    )
                } finally {
                    callback(
                        FetchResult(
                            transactions = fetchedTransactions,
                            isFromCache = false,
                            loadedAll = !result.hasMore
                        )
                    )
                }
            }
        }

        mainHandler.post {
            if (isCancelled()) return@post

            WalletCore.call(
                ApiMethod.WalletData.FetchPastActivities(
                    accountId = accountId,
                    limit = DEFAULT_LIMIT,
                    slug = tokenSlug,
                    toTimestamp = before?.timestamp
                )
            ) { result, err ->
                if (result == null || err != null) {
                    retry()
                } else {
                    handleSuccess(result)
                }
            }
        }
    }

    // Activity Persistence ////////////////////////////////////////////////////////////////////////

    /**
     * Store a list of activities to global storage.
     *
     * Called after:
     * - SDK events (newActivities, newLocalActivities)
     * - List pagination from ActivityLoader
     *
     * Applies MAX_ITEMS_TO_CACHE_IN_LIST limit to prevent unbounded storage growth.
     */
    fun setListTransactions(
        accountId: String,
        slug: String?,
        activitiesToSave: List<MApiTransaction>,
        afterPaginate: Boolean,
        loadedAll: Boolean? = null
    ) {
        beginTransaction()
        backgroundQueue.execute {
            try {
                setListTransactionsOnQueue(
                    accountId = accountId,
                    slug = slug,
                    activitiesToSave = activitiesToSave,
                    afterPaginate = afterPaginate,
                    loadedAll = loadedAll
                )
            } finally {
                endTransaction()
            }
        }
    }

    private fun setListTransactionsOnQueue(
        accountId: String,
        slug: String?,
        activitiesToSave: List<MApiTransaction>,
        afterPaginate: Boolean,
        loadedAll: Boolean? = null
    ) {
        Logger.i(
            Logger.LogTag.ACTIVITY_STORE,
            "setListTransactions accountId=$accountId slug=$slug activities=${activitiesToSave.size}"
        )

        // Filter out local and pending transactions (they're handled separately)
        val filteredActivities = ActivityHelpers.filter(
            accountId,
            activitiesToSave.filter {
                !it.isLocal() &&
                    (it as? MApiTransaction.Transaction)?.isPending() != true
            },
            false,
            slug
        )

        // Get existing IDs from in-memory cache
        val existingIds = getActivityIds(accountId, slug)
        val listIsAlreadySaved = existingIds.size >= MAX_ITEMS_TO_CACHE_IN_LIST && afterPaginate
        if (listIsAlreadySaved) return

        // Merge IDs with existing list. `filteredActivities` is supplied as a fallback
        // because it may include activities that have not yet been added to
        // `cachedTransactions` (e.g. via the receivedLocalTransactions path), and the
        // comparator must resolve every id to stay transitive.
        val mergedIds = ActivityHelpers.mergeSortedActivityIds(
            filteredActivities.map { it.id },
            existingIds,
            accountStates[accountId]?.cachedTransactions ?: emptyMap(),
            filteredActivities
        )

        // Apply cache limit
        val limitedIds = mergedIds.take(MAX_ITEMS_TO_CACHE_IN_LIST).toTypedArray()
        val limitedActivities = filteredActivities.take(MAX_ITEMS_TO_CACHE_IN_LIST)

        // Persist to storage
        persistActivitiesToStorage(accountId, slug, limitedActivities, limitedIds)

        // Update newest activities tracking
        if (slug == null) {
            setNewestActivitiesBySlug(accountId)
        }

        // Update loadedAll flag
        loadedAll?.let {
            val actualLoadedAll = loadedAll && limitedIds.size == mergedIds.size
            WGlobalStorage.setIsHistoryEndReached(accountId, slug, actualLoadedAll)
        }
    }

    private fun persistActivitiesToStorage(
        accountId: String,
        slug: String?,
        activities: List<MApiTransaction>,
        ids: Array<String>
    ) {
        // Build activities dictionary
        val dict = JSONObject()
        for (activity in activities) {
            dict.put(activity.id, activity.toDictionary())
        }

        // Merge with existing dictionary
        val existingDict = WGlobalStorage.getActivitiesDict(accountId) ?: JSONObject()
        existingDict.add(dict)
        WGlobalStorage.setActivitiesDict(accountId, existingDict)

        // Update in-memory ID list
        val accountState = getOrCreateAccountState(accountId)
        val idsList = ids.toList()
        if (slug == null) {
            accountState.idsMain = idsList
        } else {
            accountState.idsBySlug[slug] = idsList
        }

        // Persist ID list to storage
        WGlobalStorage.setActivityIds(accountId, slug, ids)
    }

    // Incoming Activity Handlers //////////////////////////////////////////////////////////////////

    /**
     * Process initial activities received from SDK during account initialization.
     *
     * This is called once per account/chain when the SDK provides the initial batch of activities.
     * It sets up the base state for both main list and per-slug lists.
     */
    fun initialActivities(
        accountId: String,
        chain: MBlockchain,
        mainActivities: List<MApiTransaction>,
        bySlug: Map<String, List<MApiTransaction>>
    ) {
        beginTransaction()
        backgroundQueue.execute {
            Logger.i(
                Logger.LogTag.ACTIVITY_STORE,
                "InitialActivities accountId=$accountId chain=${chain.name} mainActivities=${mainActivities.size} bySlug=${bySlug.keys.size}"
            )

            val allActivities = mainActivities + bySlug.values.flatten()

            val accountState = getOrCreateAccountState(accountId)

            // Add all activities to cache
            for (activity in allActivities) {
                accountState.cachedTransactions[activity.id] = activity
                PoisoningCacheHelper.updatePoisoningCache(accountId, activity)
            }

            // Merge idsMain with cutoff (activities older than cutoff are filtered out)
            val newMainIds = mainActivities.map { it.id }
            accountState.idsMain = ActivityHelpers.mergeActivityIdsToMaxTime(
                newIds = newMainIds,
                existingIds = accountState.idsMain,
                cachedActivities = accountState.cachedTransactions
            )
            if (accountState.idsMain.isEmpty()) {
                WGlobalStorage.setIsHistoryEndReached(accountId, null, true)
            } else if (newMainIds.isNotEmpty()) {
                WGlobalStorage.setIsHistoryEndReached(accountId, null, false)
            }

            // Update idsBySlug for each token (replace, not merge)
            val newestActivitiesBySlug = mutableMapOf<String, JSONObject>()
            for ((slug, activities) in bySlug) {
                val slugIds = activities.map { it.id }
                accountState.idsBySlug[slug] = slugIds
                activities.firstOrNull(::isSuitableToGetTimestamp)?.toDictionary()?.let {
                    newestActivitiesBySlug[slug] = it
                }
            }

            // Persist to storage
            persistIdsToStorage(accountId)

            // Update newest activities by slug
            updateNewestActivitiesBySlug(accountId, newestActivitiesBySlug)
            setNewestActivitiesBySlug(accountId)

            // Notify observers
            val walletEvent = WalletEvent.ReceivedNewActivities(
                accountId = accountId,
                newActivities = allActivities,
                eventType = WalletEvent.ReceivedNewActivities.EventType.ACCOUNT_INITIALIZE
            )
            WalletCore.notifyEvent(walletEvent)

            scheduleCexSwapRefreshIfNeeded()

            endTransaction()
        }
    }

    private fun persistIdsToStorage(accountId: String) {
        val accountState = accountStates[accountId] ?: return

        // Build activities dictionary for storage
        val dict = JSONObject()
        for ((id, activity) in accountState.cachedTransactions) {
            dict.put(id, activity.toDictionary())
        }
        WGlobalStorage.setActivitiesDict(accountId, dict)

        // Persist main IDs
        WGlobalStorage.setActivityIds(accountId, null, accountState.idsMain.toTypedArray())

        // Persist per-slug IDs
        for ((slug, ids) in accountState.idsBySlug) {
            WGlobalStorage.setActivityIds(accountId, slug, ids.toTypedArray())
        }
    }

    // Process new activities received from SDK polling or events
    fun newActivities(
        context: Context,
        accountId: String,
        newActivities: List<MApiTransaction>,
        pendingActivities: List<MApiTransaction>?,
        chain: MBlockchain?
    ) {
        Logger.i(
            Logger.LogTag.ACTIVITY_STORE,
            "newActivities accountId=$accountId newActivities=${newActivities.size} pendingActivities=${pendingActivities?.size ?: "omitted"}"
        )

        backgroundQueue.execute {
            val previousActivities = selectTemporaryActivitiesForReconciliation(accountId, chain)
            val reconciliation = reconcileActivityUpdateOnSdk(
                accountId = accountId,
                previousActivities = previousActivities,
                confirmedActivities = newActivities,
                pendingActivities = pendingActivities,
                contextActivities = selectCexSwapRefreshContextActivities(
                    accountId,
                    pendingCexSwapActivities(accountId),
                    newActivities
                )
            )
            val confirmedActivities = reconciliation?.confirmedActivities ?: newActivities
            val reconciledPendingActivities = reconciliation?.pendingActivities ?: pendingActivities

            beginTransaction()
            try {
                processReceivedActivitiesOnQueue(
                    context = context,
                    accountId = accountId,
                    newActivities = confirmedActivities,
                    pendingActivities = reconciledPendingActivities,
                    eventType = WalletEvent.ReceivedNewActivities.EventType.UPDATE,
                    pendingChain = chain,
                    sdkPatch = reconciliation?.patch,
                    sdkRemoveIds = reconciliation?.patch?.removeIds,
                    sdkReplacedIds = reconciliation?.patch?.replacedIds,
                    sdkPreviousActivities = previousActivities
                )
                storeActivitiesBySlugOnQueue(
                    accountId,
                    confirmedActivities.filter {
                        it.shouldHide !=
                            true
                    }
                )
            } finally {
                endTransaction()
            }
        }
    }

    /**
     * Runs the pure TS SDK reconciler while the serial activity queue awaits its result. The bridge owns dispatch to the
     * main thread and the SDK owns reconciliation deadlines; Android must not introduce a second timeout or reorder a
     * later activity update ahead of this one.
     */
    private suspend fun reconcileActivityUpdateOnSdk(
        accountId: String,
        previousActivities: List<MApiTransaction>,
        confirmedActivities: List<MApiTransaction>,
        pendingActivities: List<MApiTransaction>?,
        contextActivities: List<MApiTransaction>? = null
    ): MApiReconcileActivityUpdateResult? = try {
        WalletCore.call(
            ApiMethod.WalletData.ReconcileActivityUpdate(
                accountId = accountId,
                previousActivities = previousActivities,
                confirmedActivities = confirmedActivities,
                pendingActivities = pendingActivities,
                contextActivities = contextActivities
            )
        )
    } catch (error: CancellationException) {
        throw error
    } catch (error: Exception) {
        Logger.e(Logger.LogTag.ACTIVITY_STORE, "reconcileActivityUpdate: $error")
        null
    }

    // Process locally-created transactions (e.g., from send flow before confirmation)
    fun receivedLocalTransactions(accountId: String, newLocalTransactions: Array<MApiTransaction>) {
        backgroundQueue.execute {
            Logger.i(
                Logger.LogTag.ACTIVITY_STORE,
                "receivedLocalTransactions accountId=$accountId localActivities=${newLocalTransactions.size}"
            )

            val accountState = getOrCreateAccountState(accountId)
            val existingChainActivities = selectRecentNonLocalActivities(
                ids = accountState.idsMain,
                byId = accountState.cachedTransactions,
                maxCount = newLocalTransactions.size + 20,
                isLocal = { it.isLocal() }
            )
            val reconciliation = reconcileActivityUpdateOnSdk(
                accountId = accountId,
                previousActivities = newLocalTransactions.toList(),
                confirmedActivities = existingChainActivities,
                pendingActivities = null
            )
            val patch = reconciliation?.patch
            val patchUpsertById = patch?.upsert?.associateBy { it.id } ?: emptyMap()
            val removeIds = patch?.removeIds?.toSet() ?: emptySet()
            val localTransactions = newLocalTransactions
                .filterNot { removeIds.contains(it.id) }
                .map { transaction -> patchUpsertById[transaction.id] ?: transaction }
                .toTypedArray()
            patch?.replacedIds?.let {
                processReplacedStableIdsFromSdkPatch(
                    previousActivities = newLocalTransactions.toList(),
                    replacementActivities = patch.upsert,
                    replacedIds = it,
                    visibleReplacementActivities = existingChainActivities
                )
            }

            val incomingLocalIds = newLocalTransactions.map { it.id }.toSet()
            val nonLocalPatch = patch?.let {
                MApiActivitiesPatch(
                    accountId = it.accountId,
                    upsert = excludeIncomingLocalPatchUpserts(
                        it.upsert,
                        incomingLocalIds
                    ) { activity ->
                        activity.id
                    },
                    removeIds = it.removeIds,
                    replacedIds = it.replacedIds
                )
            }
            val sdkUpdatedIds =
                nonLocalPatch?.let { applyActivitiesPatch(accountId, it) } ?: emptyList()

            addAccountLocalTransactions(accountId, localTransactions)

            val confirmedTransactions = localTransactions.filter {
                !it.isLocal() && !it.isPending()
            }
            if (confirmedTransactions.isNotEmpty()) {
                storeActivitiesBySlugOnQueue(accountId, confirmedTransactions)
            }

            // Notify observers
            val walletEvent = WalletEvent.ReceivedNewActivities(
                accountId = accountId,
                newActivities = localTransactions.toList() + sdkUpdatedIds.mapNotNull {
                    accountState.cachedTransactions[it]
                },
                eventType = WalletEvent.ReceivedNewActivities.EventType.UPDATE
            )
            WalletCore.notifyEvent(walletEvent)

            scheduleCexSwapRefreshIfNeeded()
        }
    }

    /**
     * Persist activities organized by token slug.
     *
     * Groups activities by slug and stores each group separately.
     * Also updates the main (all activities) list.
     * Called after newActivities and receivedLocalTransactions events.
     */
    private fun storeActivitiesBySlugOnQueue(
        accountId: String,
        newActivities: List<MApiTransaction>
    ) {
        beginTransaction()
        try {
            val newestActivitiesBySlug = mutableMapOf<String, JSONObject>()
            for ((slug, slugActivities) in groupActivitiesByTokenSlug(newActivities)) {
                setListTransactionsOnQueue(
                    accountId = accountId,
                    slug = slug,
                    activitiesToSave = slugActivities,
                    afterPaginate = false
                )
                slugActivities.firstOrNull(::isSuitableToGetTimestamp)?.toDictionary()?.let {
                    newestActivitiesBySlug[slug] = it
                }
            }
            updateNewestActivitiesBySlug(
                accountId,
                newestActivitiesBySlug
            )
            setListTransactionsOnQueue(
                accountId = accountId,
                slug = null,
                activitiesToSave = newActivities,
                afterPaginate = false
            )
        } finally {
            endTransaction()
        }
    }

    // Core Activity Processing ////////////////////////////////////////////////////////////////////

    /**
     * Core method that processes all received activities.
     *
     * Responsibilities:
     * - Apply SDK-provided replacement aliases (for smooth UI transitions)
     * - Update in-memory cache
     * - Play notification sounds for incoming transactions
     * - Broadcast events to observers (ActivityLoader)
     *
     * Called by: fetchFromNetwork, newActivities
     */
    private fun processReceivedActivitiesOnQueue(
        context: Context,
        accountId: String,
        newActivities: List<MApiTransaction>,
        pendingActivities: List<MApiTransaction>?,
        eventType: WalletEvent.ReceivedNewActivities.EventType,
        pendingChain: MBlockchain? = null,
        sdkPatch: MApiActivitiesPatch? = null,
        sdkRemoveIds: List<String>? = null,
        sdkReplacedIds: Map<String, String>? = null,
        sdkPreviousActivities: List<MApiTransaction>? = null
    ) {
        beginTransaction()
        try {
            val pendingAndNewActivities = pendingActivities.orEmpty() + newActivities

            // Apply the replacement aliases supplied by the SDK patch.
            if (sdkReplacedIds != null) {
                processReplacedStableIdsFromSdkPatch(
                    previousActivities = sdkPreviousActivities
                        ?: selectTemporaryActivitiesForReconciliation(accountId, pendingChain),
                    replacementActivities = pendingAndNewActivities + sdkPatch?.upsert.orEmpty(),
                    replacedIds = sdkReplacedIds
                )
            }

            val accountState = getOrCreateAccountState(accountId)
            val replacedPendingIds = selectPendingIdsToReplace(
                current = accountState.pendingTransactionsByChain,
                key = pendingChain,
                incoming = pendingActivities,
                getId = { it.id }
            )
            if (replacedPendingIds.isNotEmpty()) {
                replacedPendingIds.forEach(accountState.cachedTransactions::remove)
                removeActivityIdsFromLists(accountState, replacedPendingIds)
            }

            // Update pending transactions cache
            replacePendingTransactions(accountId, pendingChain, pendingActivities)

            // Apply filters
            val filteredActivities = ActivityHelpers.filter(
                accountId,
                newActivities,
                false,
                null
            )

            // Update in-memory cache
            updateInMemoryCache(
                accountId,
                filteredActivities,
                sdkRemoveIds
            )

            // The SDK patch is the final source of truth. Apply every upsert (including hidden sources) after generic
            // cache ingestion so no native status or metadata rule can rewrite the authoritative projection.
            val sdkUpdatedIds = sdkPatch?.let { applyActivitiesPatch(accountId, it) }.orEmpty()

            if (replacedPendingIds.isNotEmpty()) {
                persistIdsToStorage(accountId)
                setNewestActivitiesBySlug(accountId)
            }

            // Auto-install MTW card and unhide a bought NFT from an activity that carries an NFT.
            if (eventType == WalletEvent.ReceivedNewActivities.EventType.UPDATE) {
                applyNftsFromActivities(accountId, filteredActivities)
            }

            // Play notification sound for incoming transactions
            if (eventType != WalletEvent.ReceivedNewActivities.EventType.PAGINATE) {
                playIncomingTransactionSound(context, accountId, pendingAndNewActivities)
            }
            notifiedIds.addAll(pendingAndNewActivities.map { it.id })

            // Broadcast event to observers (not for pagination - handled by ActivityLoader)
            if (eventType != WalletEvent.ReceivedNewActivities.EventType.PAGINATE) {
                val updatedActivities = selectUpdatedVisibleActivities(
                    updatedIds = (filteredActivities.map { it.id } + sdkUpdatedIds).distinct(),
                    byId = accountState.cachedTransactions,
                    isVisible = { it.shouldHide != true }
                )
                notifyActivityEventOnQueue(accountId, updatedActivities, eventType)
            }

            scheduleCexSwapRefreshIfNeeded()
        } finally {
            endTransaction()
        }
    }

    private fun selectTemporaryActivitiesForReconciliation(
        accountId: String,
        chain: MBlockchain?
    ): List<MApiTransaction> {
        val accountState = accountStates[accountId]
        return accountState?.localTransactions.orEmpty() +
            chain?.let { accountState?.pendingTransactionsByChain?.get(it) }.orEmpty()
    }

    private fun updateInMemoryCache(
        accountId: String,
        filteredActivities: List<MApiTransaction>,
        sdkRemoveIds: List<String>? = null
    ) {
        val accountState = accountStates[accountId]
        val accountCache = accountState?.cachedTransactions

        // Apply SDK removals without deriving additional native matches.
        if (sdkRemoveIds != null) {
            for (id in sdkRemoveIds) {
                removeAccountLocalTransaction(accountId, id)
                accountCache?.remove(id)
            }
        }

        // Update or add to cache
        if ((accountCache?.keys?.size ?: 0) > 0) {
            val newActivities = mutableMapOf<String, MApiTransaction>()
            for (activity in filteredActivities) {
                val existing = accountCache?.get(activity.id)
                val activityToCache = ActivityHelpers.preserveStatusProgress(existing, activity)
                if (existing != null) {
                    if (activityToCache.isChanged(existing)) {
                        updateCachedTransaction(accountId, activityToCache)
                    }
                } else {
                    newActivities[activity.id] = activityToCache
                }
            }
            addCachedTransactions(accountId, newActivities.values.toTypedArray())
        } else {
            // First time - create new cache
            val newCache = HashMap(filteredActivities.associateBy { it.id })
            setCachedTransactions(accountId, newCache)
        }
    }

    private fun applyNftsFromActivities(accountId: String, activities: List<MApiTransaction>) {
        val incomingNfts = activities.mapNotNull { activity ->
            if (activity !is MApiTransaction.Transaction) return@mapNotNull null
            if (activity.isPending() || activity.isLocal()) return@mapNotNull null
            val nft = activity.nft ?: return@mapNotNull null
            // `nftTrade` (marketplace buy/sell) reports `isIncoming` for the TONCOIN leg,
            // not the NFT leg, so it must be inverted.
            val isNftIncoming = if (activity.type == ApiTransactionType.NFT_TRADE) {
                !activity.isIncoming
            } else {
                activity.isIncoming
            }
            if (!isNftIncoming) null else activity.type to nft
        }
        if (incomingNfts.isEmpty()) return
        ensureMainThread {
            for ((type, nft) in incomingNfts) {
                NftStore.applyIncomingMtwCard(accountId, nft)
                // Buying an NFT is an explicit intent to own it, so it stays visible even if its
                // collection is untrusted
                if (type == ApiTransactionType.NFT_TRADE) {
                    NftStore.showNft(accountId, nft)
                }
            }
        }
    }

    private fun playIncomingTransactionSound(
        context: Context,
        accountId: String,
        activities: List<MApiTransaction>
    ) {
        if (!isAppFocused) return
        if (accountId != AccountStore.activeAccountId) return
        if (!WGlobalStorage.getAreSoundsActive()) return
        if (WalletContextManager.delegate?.get()?.isAppUnlocked() != true) return

        val hasNewIncoming = activities.any { activity ->
            val isRecent =
                System.currentTimeMillis() / 1000 - activity.timestamp / 1000 <
                    NEW_TRANSACTION_THRESHOLD_SECONDS
            activity is MApiTransaction.Transaction &&
                activity.shouldHide != true &&
                activity.isIncoming &&
                !activity.isPending() &&
                !notifiedIds.contains(activity.id) &&
                isRecent &&
                !activity.isPoisoning(accountId) &&
                (!WGlobalStorage.getAreTinyTransfersHidden() || !activity.isTinyOrScam)
        }

        if (hasNewIncoming) {
            mainHandler.post {
                if (!isAppFocused) return@post
                AudioHelpers.play(context, AudioHelpers.Sound.IncomingTransaction)
            }
        }
    }

    private fun notifyActivityEventOnQueue(
        accountId: String,
        activities: List<MApiTransaction>,
        eventType: WalletEvent.ReceivedNewActivities.EventType
    ) {
        val walletEvent = WalletEvent.ReceivedNewActivities(
            accountId = accountId,
            newActivities = activities,
            eventType = eventType
        )
        WalletCore.notifyEvent(walletEvent)
    }

    // Cache Management ////////////////////////////////////////////////////////////////////////////
    private fun getCachedTransactions(): Map<String, Map<String, MApiTransaction>> =
        accountStates.mapValues {
            it.value.cachedTransactions
        }

    fun updateCachedTransaction(accountId: String, transaction: MApiTransaction) {
        getOrCreateAccountState(accountId).cachedTransactions[transaction.id] = transaction
        PoisoningCacheHelper.updatePoisoningCache(accountId, transaction)
    }

    private fun addCachedTransactions(accountId: String, transactions: Array<MApiTransaction>) {
        val accountState = getOrCreateAccountState(accountId)
        for (transaction in transactions) {
            accountState.cachedTransactions[transaction.id] = transaction
            PoisoningCacheHelper.updatePoisoningCache(accountId, transaction)
        }
    }

    private fun setCachedTransactions(
        accountId: String,
        transactions: Map<String, MApiTransaction>
    ) {
        getOrCreateAccountState(accountId).cachedTransactions = ConcurrentHashMap(transactions)
        transactions.values.forEach {
            PoisoningCacheHelper.updatePoisoningCache(accountId, it)
        }
    }

    // Local/Pending Transaction Management ////////////////////////////////////////////////////////
    private fun updateLocalTransactions(accountId: String, transactions: List<MApiTransaction>?) {
        if (transactions != null) {
            getOrCreateAccountState(accountId).localTransactions = transactions
        } else {
            accountStates[accountId]?.localTransactions = emptyList()
        }
    }

    private fun replacePendingTransactions(
        accountId: String,
        chain: MBlockchain?,
        transactions: List<MApiTransaction>?
    ) {
        if (chain == null || transactions == null) return
        val accountState = getOrCreateAccountState(accountId)
        accountState.pendingTransactionsByChain = replacePendingBucket(
            accountState.pendingTransactionsByChain,
            chain,
            transactions.filter { it.isPending() }
        )
    }

    private fun clearPendingTransactions(accountId: String) {
        accountStates[accountId]?.pendingTransactionsByChain = emptyMap()
    }

    private fun addAccountLocalTransactions(
        accountId: String,
        localTransactions: Array<MApiTransaction>
    ) {
        val localTransactionIds = localTransactions.map { it.id }
        updateLocalTransactions(
            accountId,
            (getLocalTransactions()[accountId] ?: emptyList())
                .filter { !localTransactionIds.contains(it.id) }
                .plus(localTransactions)
        )
    }

    private fun removeAccountLocalTransaction(accountId: String, id: String) {
        updateLocalTransactions(
            accountId = accountId,
            getLocalTransactions()[accountId]?.filter { it.id != id } ?: emptyList()
        )
    }

    // Newest Activities Tracking //////////////////////////////////////////////////////////////////
    private fun updateNewestActivitiesBySlug(
        accountId: String,
        newestActivitiesBySlug: MutableMap<String, JSONObject>
    ) {
        val accountState = getOrCreateAccountState(accountId)
        accountState.newestActivitiesBySlug.putAll(newestActivitiesBySlug)
    }

    private fun setNewestActivitiesBySlug(accountId: String) {
        WGlobalStorage.setNewestActivitiesBySlug(
            accountId,
            accountStates[accountId]?.newestActivitiesBySlug,
            IGlobalStorageProvider.PERSIST_NORMAL
        )
    }

    // Transaction List Retrieval //////////////////////////////////////////////////////////////////
    private fun getTransactionList(
        accountId: String,
        slug: String?,
        beforeId: String?
    ): List<MApiTransaction> {
        val transactionIds = getActivityIds(accountId, slug)

        // Apply pagination filter
        val filteredIds: List<String> = if (beforeId != null) {
            val index = transactionIds.lastIndexOf(beforeId)
            if (index != -1) {
                transactionIds.drop(index + 1)
            } else {
                return emptyList()
            }
        } else {
            transactionIds
        }

        // Apply limit and map to transactions
        val limitedIds = filteredIds.take(DEFAULT_LIMIT)
        val cachedTransactions = getCachedTransactions()[accountId]

        return limitedIds.mapNotNull { id -> cachedTransactions?.get(id) }
    }

    // Get activity IDs from in-memory cache, falling back to WGlobalStorage
    private fun getActivityIds(accountId: String, slug: String?): List<String> {
        val accountState = accountStates[accountId] ?: return emptyList()

        return if (slug == null) {
            // Main activity list - fallback to storage and cache the result
            accountState.idsMain.ifEmpty {
                val ids = WGlobalStorage.getActivityIds(accountId, null)?.toList() ?: emptyList()
                accountState.idsMain = ids
                ids
            }
        } else {
            // Per-slug activity list - fallback to storage and cache the result
            accountState.idsBySlug[slug] ?: run {
                val ids = WGlobalStorage.getActivityIds(accountId, slug)?.toList() ?: emptyList()
                if (ids.isNotEmpty()) {
                    accountState.idsBySlug[slug] = ids
                }
                ids
            }
        }
    }

    // Storage Transaction Helpers /////////////////////////////////////////////////////////////////

    /**
     * Begin a storage transaction.
     *
     * Prevents WGlobalStorage from syncing to disk until endTransaction() is called.
     * Used to batch multiple storage writes for better performance.
     */
    private fun beginTransaction() {
        WGlobalStorage.incDoNotSynchronize()
    }

    /**
     * End a storage transaction.
     *
     * Re-enables WGlobalStorage disk sync. All callers finish transactions on backgroundQueue.
     */
    private fun endTransaction() {
        WGlobalStorage.decDoNotSynchronize()
    }

    // CEX Swap Reconciliation /////////////////////////////////////////////////////////////////////
    // Periodically calls JS `fetchSwaps` for pending CEX swaps on the active account, then
    // applies returned status / cancellation and hides on-chain tx covered by a CEX swap's
    // hashes. All cache reads/writes run on `backgroundQueue`, matching the rest of this store;
    // `cexSwapScheduler` only posts ticks onto that queue, so no extra locking is needed.

    override fun onWalletEvent(walletEvent: WalletEvent) {
        when (walletEvent) {
            is WalletEvent.AccountChanged -> backgroundQueue.execute {
                cancelCexSwapRefreshTick()
                scheduleCexSwapRefreshIfNeeded(immediate = true)
            }

            WalletEvent.AppForeground -> {
                isAppFocused = true
                backgroundQueue.execute {
                    cancelCexSwapRefreshTick()
                    scheduleCexSwapRefreshIfNeeded(immediate = true)
                }
            }

            WalletEvent.AppBackground -> {
                isAppFocused = false
            }

            else -> {}
        }
    }

    private fun cancelCexSwapRefreshTick() {
        if (!hasPendingCexSwapTick) return
        mainHandler.removeCallbacks(cexSwapRefreshTick)
        hasPendingCexSwapTick = false
    }

    /**
     * Schedule the next CEX-swap refresh tick if the active account still has pending
     * CEX swaps. Idempotent — safe to call repeatedly. Must run on `backgroundQueue`.
     * @param immediate when true, fires the next tick with no delay (e.g. on
     *   account-switch / app-foreground) instead of waiting for the regular interval.
     */
    private fun scheduleCexSwapRefreshIfNeeded(immediate: Boolean = false) {
        if (hasPendingCexSwapTick) return

        val accountId = AccountStore.activeAccountId
        if (accountId == null || pendingCexSwapIds(accountId).isEmpty()) return

        val delay = when {
            immediate -> 0L
            isAppFocused -> CEX_SWAP_REFRESH_INTERVAL_MS
            else -> CEX_SWAP_REFRESH_INTERVAL_NOT_FOCUSED_MS
        }

        hasPendingCexSwapTick = true
        mainHandler.postDelayed(cexSwapRefreshTick, delay)
    }

    private fun onCexSwapRefreshTick() {
        hasPendingCexSwapTick = false
        refreshPendingCexSwaps()
        // `refreshPendingCexSwaps/applyCexSwapRefresh` will reschedule when its work completes;
        // if there's no fetch in-flight (no pending ids) the chain ends here.
    }

    /** Snapshot pending ids on backgroundQueue, then fire fetchSwaps; apply result on backgroundQueue. */
    private fun refreshPendingCexSwaps() {
        val accountId = AccountStore.activeAccountId ?: return
        val pendingCexSwaps = pendingCexSwapActivities(accountId)
        val items = ActivityHelpers.pendingCexSwapHashes(pendingCexSwaps)
            .map { MApiFetchSwapItem(id = it, chain = MBlockchain.ton) }
        if (items.isEmpty()) return
        val existingActivities = selectCexSwapRefreshContextActivities(accountId, pendingCexSwaps)

        mainHandler.post {
            WalletCore.call(
                ApiMethod.Swap.FetchSwaps(
                    accountId,
                    items,
                    existingActivities
                )
            ) { result, err ->
                if (err != null || result == null) {
                    Logger.e(Logger.LogTag.ACTIVITY_STORE, "refreshPendingCexSwaps: $err")
                    // Retry at the next regular interval.
                    backgroundQueue.execute { scheduleCexSwapRefreshIfNeeded() }
                    return@call
                }
                backgroundQueue.execute { applyCexSwapRefresh(accountId, result) }
            }
        }
    }

    private fun selectCexSwapRefreshContextActivities(
        accountId: String,
        pendingCexSwaps: List<MApiTransaction>,
        priorityActivities: List<MApiTransaction> = emptyList()
    ): List<MApiTransaction> {
        val accountState = accountStates[accountId]
        val cexProjectionActivities = accountState?.cachedTransactions?.values
            ?.filter { it.extra?.reconciliation?.reason == "cex-swap" }
            .orEmpty()
        val recentActivities = buildList {
            accountState?.idsMain?.forEach { id -> accountState.cachedTransactions[id]?.let(::add) }
            accountState?.idsBySlug?.values?.forEach { ids ->
                ids.forEach { id -> accountState.cachedTransactions[id]?.let(::add) }
            }
        }

        // Active CEX/local/pending rows must survive a large incoming batch: the SDK needs them to decide whether to
        // force-refresh and to project matching raw rows. Recent main/token-history rows remain as bounded fallback.
        return selectBoundedCexRefreshContext(
            activeCexActivities = pendingCexSwaps,
            cexProjectionActivities = cexProjectionActivities,
            localActivities = accountState?.localTransactions.orEmpty(),
            pendingActivities = accountState?.pendingTransactions.orEmpty(),
            incomingActivities = priorityActivities,
            recentActivities = recentActivities,
            limit = CEX_SWAP_REFRESH_CONTEXT_LIMIT
        ) { it.id }
    }

    private fun applyCexSwapRefresh(accountId: String, result: MApiFetchSwapsResult) {
        val patch = result.patch
        if (patch == null) {
            Logger.e(
                Logger.LogTag.ACTIVITY_STORE,
                "fetchSwaps returned no SDK reconciliation patch"
            )
            scheduleCexSwapRefreshIfNeeded()
            return
        }

        val updatedIds = applyActivitiesPatch(accountId, patch)
        if (updatedIds.isNotEmpty()) {
            val accountState = accountStates[accountId] ?: return
            val updatedActivities = selectUpdatedVisibleActivities(
                updatedIds = updatedIds,
                byId = accountState.cachedTransactions,
                isVisible = { it.shouldHide != true }
            )
            WalletCore.notifyEvent(
                WalletEvent.ReceivedNewActivities(
                    accountId = accountId,
                    newActivities = updatedActivities,
                    eventType = WalletEvent.ReceivedNewActivities.EventType.UPDATE
                )
            )
        }

        // Continue the refresh cycle if any pending CEX swaps remain.
        scheduleCexSwapRefreshIfNeeded()
    }

    private fun applyActivitiesPatch(accountId: String, patch: MApiActivitiesPatch): List<String> {
        val accountState = getOrCreateAccountState(accountId)
        val byId = accountState.cachedTransactions
        var changed = false
        val updatedIds = mutableListOf<String>()

        val presentationAliasChangedIds = mutableListOf<String>()
        for (activity in patch.upsert) {
            val existing = byId[activity.id]
            val nextStableId = activity.replacedStableId
                ?: existing?.takeIf {
                    it.id == activity.id && it.kind == activity.kind
                }?.replacedStableId
            if (existing?.replacedStableId !=
                nextStableId
            ) {
                presentationAliasChangedIds.add(activity.id)
            }
            activity.replacedStableId = nextStableId
        }
        val changedById = (
            applyAuthoritativePatchById(byId, patch.removeIds, patch.upsert) { it.id } +
                presentationAliasChangedIds
            ).distinct()
        if (changedById.isNotEmpty()) {
            changed = true
            updatedIds.addAll(changedById)
        }
        if (patch.removeIds.isNotEmpty()) {
            val removeIds = patch.removeIds.toSet()
            changed = removeActivityIdsFromLists(accountState, removeIds) || changed
        }
        if (patch.upsert.isNotEmpty()) {
            val upsertById = patch.upsert.associateBy { it.id }
            accountState.localTransactions =
                accountState.localTransactions.map { upsertById[it.id] ?: it }
            accountState.pendingTransactionsByChain = applyPatchToPendingBuckets(
                current = accountState.pendingTransactionsByChain,
                removeIds = emptySet(),
                upsert = patch.upsert,
                getId = { it.id },
                isPending = { it.isPending() }
            )
        }
        val visibleUpserts = mutableListOf<MApiTransaction>()
        val hiddenUpsertIds = mutableSetOf<String>()
        for (activity in patch.upsert) {
            // SDK patch upserts are authoritative. Native status/metadata rules must not rewrite them.
            PoisoningCacheHelper.updatePoisoningCache(accountId, activity)
            if (activity.shouldHide != true) {
                visibleUpserts.add(activity)
            } else {
                hiddenUpsertIds.add(activity.id)
            }
        }
        if (hiddenUpsertIds.isNotEmpty()) {
            changed = removeActivityIdsFromLists(accountState, hiddenUpsertIds) || changed
        }
        if (visibleUpserts.isNotEmpty()) {
            changed = indexVisibleActivitiesFromSdkPatch(
                accountId,
                accountState,
                visibleUpserts
            ) || changed
        }

        if (changed) {
            persistIdsToStorage(accountId)
            setNewestActivitiesBySlug(accountId)
        }

        return updatedIds.distinct()
    }

    private fun indexVisibleActivitiesFromSdkPatch(
        accountId: String,
        accountState: AccountActivityState,
        activities: List<MApiTransaction>
    ): Boolean {
        var changed = false
        val newMainIds = activities.map { it.id }
        val nextMainIds = ActivityHelpers.mergeSortedActivityIds(
            newIds = newMainIds,
            existingIds = accountState.idsMain,
            byId = accountState.cachedTransactions,
            fallback = activities
        )
        if (nextMainIds != accountState.idsMain) {
            accountState.idsMain = nextMainIds
            changed = true
        }

        val newestActivitiesBySlug = mutableMapOf<String, JSONObject>()
        for ((slug, slugActivities) in groupActivitiesByTokenSlug(activities)) {
            val nextSlugIds = ActivityHelpers.mergeSortedActivityIds(
                newIds = slugActivities.map { it.id },
                existingIds = accountState.idsBySlug[slug] ?: emptyList(),
                byId = accountState.cachedTransactions,
                fallback = slugActivities
            )
            if (nextSlugIds != accountState.idsBySlug[slug]) {
                accountState.idsBySlug[slug] = nextSlugIds
                changed = true
            }
            slugActivities.firstOrNull(::isSuitableToGetTimestamp)?.toDictionary()?.let {
                newestActivitiesBySlug[slug] = it
            }
        }
        if (newestActivitiesBySlug.isNotEmpty()) {
            updateNewestActivitiesBySlug(accountId, newestActivitiesBySlug)
        }

        return changed
    }

    private fun removeActivityIdsFromLists(
        accountState: AccountActivityState,
        deleteIds: Set<String>
    ): Boolean {
        var changed = false
        val affectedSlugs = mutableSetOf<String>()
        val nextMainIds = accountState.idsMain.filterNot { deleteIds.contains(it) }
        if (nextMainIds != accountState.idsMain) {
            accountState.idsMain = nextMainIds
            changed = true
        }

        for ((slug, ids) in accountState.idsBySlug.toMap()) {
            val nextIds = ids.filterNot { deleteIds.contains(it) }
            if (nextIds != ids) {
                accountState.idsBySlug[slug] = nextIds
                affectedSlugs.add(slug)
                changed = true
            }
        }

        for (slug in affectedSlugs) {
            val newestActivity = accountState.idsBySlug[slug]
                ?.asSequence()
                ?.mapNotNull(accountState.cachedTransactions::get)
                ?.firstOrNull(::isSuitableToGetTimestamp)
            if (newestActivity == null) {
                accountState.newestActivitiesBySlug.remove(slug)
            } else {
                accountState.newestActivitiesBySlug[slug] = newestActivity.toDictionary()
            }
        }

        val nextLocalTransactions =
            accountState.localTransactions.filterNot { deleteIds.contains(it.id) }
        if (nextLocalTransactions != accountState.localTransactions) {
            accountState.localTransactions = nextLocalTransactions
            changed = true
        }
        val nextPendingTransactionsByChain = applyPatchToPendingBuckets(
            current = accountState.pendingTransactionsByChain,
            removeIds = deleteIds,
            upsert = emptyList(),
            getId = { it.id },
            isPending = { it.isPending() }
        )
        if (nextPendingTransactionsByChain != accountState.pendingTransactionsByChain) {
            accountState.pendingTransactionsByChain = nextPendingTransactionsByChain
            changed = true
        }
        return changed
    }

    private fun groupActivitiesByTokenSlug(
        activities: List<MApiTransaction>
    ): Map<String, List<MApiTransaction>> {
        val bySlug = linkedMapOf<String, MutableList<MApiTransaction>>()
        for (activity in activities) {
            for (slug in ActivityHelpers.getActivityTokenSlugs(activity)) {
                bySlug.getOrPut(slug) { mutableListOf() }.add(activity)
            }
        }
        return bySlug
    }

    private fun pendingCexSwapIds(accountId: String): List<String> =
        ActivityHelpers.pendingCexSwapHashes(pendingCexSwapActivities(accountId))

    private fun pendingCexSwapActivities(accountId: String): List<MApiTransaction> {
        val byId = accountStates[accountId]?.cachedTransactions ?: return emptyList()
        return byId.values.filter { it is MApiTransaction.Swap && it.cex != null && it.isPending() }
    }
}
