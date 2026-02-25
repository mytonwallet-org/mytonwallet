package org.mytonwallet.app_air.walletcore.stores

import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import org.json.JSONObject
import org.mytonwallet.app_air.walletbasecontext.logger.Logger
import org.mytonwallet.app_air.walletbasecontext.utils.add
import org.mytonwallet.app_air.walletcontext.WalletContextManager
import org.mytonwallet.app_air.walletcontext.globalStorage.IGlobalStorageProvider
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.helpers.AudioHelpers
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.helpers.ActivityHelpers
import org.mytonwallet.app_air.walletcore.moshi.api.ApiMethod
import org.mytonwallet.app_air.walletcore.helpers.ActivityHelpers.Companion.isSuitableToGetTimestamp
import org.mytonwallet.app_air.walletcore.helpers.PoisoningCacheHelper
import org.mytonwallet.app_air.walletcore.models.blockchain.MBlockchain
import org.mytonwallet.app_air.walletcore.moshi.MApiTransaction
import java.util.Collections
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors

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
 * - pendingTransactions: Transactions in pending state (sent but not yet confirmed)
 * - newestActivitiesBySlug: Most recent activity for each token (for timestamp tracking)
 * - idsMain: Ordered activity IDs for main list (in-memory cache, persisted to WGlobalStorage)
 * - idsBySlug: Ordered activity IDs per token slug (in-memory cache, persisted to WGlobalStorage)
 *
 * ## Thread Safety:
 * - Write operations are queued via backgroundQueue (single-thread executor)
 * - ConcurrentHashMap enables safe cross-thread reads
 * - beginTransaction/endTransaction manage WGlobalStorage sync boundaries
 *
 * ## Event Flow:
 * SDK Events → processReceivedActivities() → cache update → WalletCore.notifyEvent() → ActivityLoader
 */
object ActivityStore : IStore {

    // Constants ///////////////////////////////////////////////////////////////////////////////////
    private const val DEFAULT_LIMIT = 60
    private const val MAX_ITEMS_TO_CACHE_IN_LIST = 200
    private const val NEW_TRANSACTION_THRESHOLD_SECONDS = 60

    // Thread management ///////////////////////////////////////////////////////////////////////////
    private val backgroundQueue = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    // In-memory caches ////////////////////////////////////////////////////////////////////////////
    // All activity state indexed by accountId
    private var _accountStates = ConcurrentHashMap<String, AccountActivityState>()

    private fun getOrCreateAccountState(accountId: String): AccountActivityState {
        return _accountStates.getOrPut(accountId) { AccountActivityState() }
    }

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
     * @property pendingTransactions Transactions in pending state (sent but not confirmed)
     * @property newestActivitiesBySlug Most recent activity for each token (for timestamp tracking)
     * @property idsMain Ordered list of activity IDs for the main (all activities) list
     * @property idsBySlug Ordered list of activity IDs per token slug
     */
    data class AccountActivityState(
        var cachedTransactions: MutableMap<String, MApiTransaction> = HashMap(),
        @Volatile
        var localTransactions: List<MApiTransaction> = emptyList(),
        @Volatile
        var pendingTransactions: List<MApiTransaction> = emptyList(),
        var newestActivitiesBySlug: MutableMap<String, JSONObject> = mutableMapOf(),
        var idsMain: List<String> = emptyList(),
        var idsBySlug: MutableMap<String, List<String>> = HashMap(),
    )

    // Result of a fetch operation, indicating source and completion status
    data class FetchResult(
        val transactions: List<MApiTransaction>,
        val isFromCache: Boolean,
        val loadedAll: Boolean,
    )

    // Lifecycle / Initialization //////////////////////////////////////////////////////////////////


    /**
     * Reload all cached data from global storage.
     * Called during app startup to restore persisted activities.
     */
    fun loadFromCache() {
        backgroundQueue.execute {
            for (accountId in WGlobalStorage.accountIds()) {
                loadAccountFromCache(accountId)
            }
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
        updatePendingTransactions(accountId, emptyList())

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
        _accountStates = ConcurrentHashMap()
    }

    fun removeAccount(removingAccountId: String) {
        backgroundQueue.execute {
            _accountStates.remove(removingAccountId)
        }
    }

    // Public Data Access //////////////////////////////////////////////////////////////////////////
    fun getLocalTransactions(): Map<String, List<MApiTransaction>> {
        return _accountStates.mapValues { it.value.localTransactions }
    }

    fun getNewestActivityTimestamps(accountId: String): JSONObject? {
        // Check if cache is valid. It may be cleared in CapacitorGlobalStorageProvider.
        if (!WGlobalStorage.hasCachedActivities(accountId, null)) {
            _accountStates[accountId]?.newestActivitiesBySlug?.clear()
            return null
        }
        return _accountStates[accountId]?.newestActivitiesBySlug
            ?.mapValues { (_, value) -> value.optLong("timestamp") }
            ?.let { JSONObject(it) }
    }

    fun getAllTransactions(accountId: String, slug: String?): List<String>? {
        val accountState = _accountStates[accountId] ?: return null
        val ids = getActivityIds(accountId, slug)
        if (ids.isEmpty() && accountState.cachedTransactions.isEmpty()) return null

        return ids
    }

    fun getLocalAndPendingActivities(accountId: String, slug: String?): List<MApiTransaction>? {
        val accountState = _accountStates[accountId] ?: return null
        return (accountState.pendingTransactions + accountState.localTransactions)
            .filter { ActivityHelpers.activityBelongsToSlug(it, slug) }.distinctBy { it.id }
    }

    /**
     * Get a cached transaction by ID.
     */
    fun getTransaction(accountId: String, transactionId: String): MApiTransaction? {
        return _accountStates[accountId]?.cachedTransactions?.get(transactionId)
    }

    /**
     * Get the count of cached activity IDs for an account/slug.
     */
    fun getActivityCount(accountId: String, slug: String?): Int {
        return getActivityIds(accountId, slug).size
    }

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
        callback: (FetchResult) -> Unit,
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

                null if _accountStates[accountId]?.cachedTransactions.isNullOrEmpty() &&
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
                        callback = callback,
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
        callback: (FetchResult) -> Unit,
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
        callback: (FetchResult) -> Unit,
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
            processReceivedActivities(
                context = context,
                accountId = accountId,
                newActivities = fetchedTransactions,
                pendingActivities = null,
                eventType = WalletEvent.ReceivedNewActivities.EventType.PAGINATE,
            )

            backgroundQueue.execute {
                callback(
                    FetchResult(
                        transactions = fetchedTransactions,
                        isFromCache = false,
                        loadedAll = !result.hasMore
                    )
                )
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
            Logger.i(
                Logger.LogTag.ACTIVITY_STORE,
                "setListTransactions accountId=$accountId slug=$slug activities=${activitiesToSave.size}"
            )

            // Filter out local and pending transactions (they're handled separately)
            val filteredActivities = ActivityHelpers.filter(
                accountId,
                activitiesToSave.filter { !it.isLocal() && (it as? MApiTransaction.Transaction)?.isPending() != true },
                false,
                slug
            )!!

            // Get existing IDs from in-memory cache
            val existingIds = getActivityIds(accountId, slug)
            val listIsAlreadySaved = existingIds.size >= MAX_ITEMS_TO_CACHE_IN_LIST && afterPaginate
            if (listIsAlreadySaved) {
                endTransaction()
                return@execute
            }

            // Merge IDs with existing list
            val mergedIds = ActivityHelpers.mergeSortedActivityIds(
                filteredActivities.map { it.id },
                existingIds,
                _accountStates[accountId]?.cachedTransactions ?: emptyMap()
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
            endTransaction()
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
                "InitialActivities accountId=${accountId} chain=${chain.name} mainActivities=${mainActivities.size} bySlug=${bySlug.keys.size}"
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
                eventType = WalletEvent.ReceivedNewActivities.EventType.ACCOUNT_INITIALIZE,
            )
            WalletCore.notifyEvent(walletEvent)

            endTransaction()
        }
    }

    private fun persistIdsToStorage(accountId: String) {
        val accountState = _accountStates[accountId] ?: return

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
        pendingActivities: List<MApiTransaction>
    ) {
        Logger.i(
            Logger.LogTag.ACTIVITY_STORE,
            "newActivities accountId=$accountId newActivities=${newActivities.size} pendingActivities=${pendingActivities.size}"
        )

        processReceivedActivities(
            context = context,
            accountId = accountId,
            newActivities = newActivities,
            pendingActivities = pendingActivities,
            eventType = WalletEvent.ReceivedNewActivities.EventType.UPDATE,
        )
        storeActivitiesBySlug(accountId, newActivities)
    }

    // Process locally-created transactions (e.g., from send flow before confirmation)
    fun receivedLocalTransactions(
        accountId: String,
        newLocalTransactions: Array<MApiTransaction>
    ) {
        backgroundQueue.execute {
            Logger.i(
                Logger.LogTag.ACTIVITY_STORE,
                "receivedLocalTransactions accountId=$accountId localActivities=${newLocalTransactions.size}"
            )

            addAccountLocalTransactions(accountId, newLocalTransactions)

            for (transaction in newLocalTransactions) {
                if (!transaction.isLocal() && !transaction.isPending()) {
                    storeActivitiesBySlug(accountId, listOf(transaction))
                }
            }

            // Notify observers
            val walletEvent = WalletEvent.ReceivedNewActivities(
                accountId = accountId,
                newActivities = newLocalTransactions.toList(),
                eventType = WalletEvent.ReceivedNewActivities.EventType.UPDATE,
            )
            WalletCore.notifyEvent(walletEvent)
        }
    }

    /**
     * Persist activities organized by token slug.
     *
     * Groups activities by slug and stores each group separately.
     * Also updates the main (all activities) list.
     * Called after newActivities and receivedLocalTransactions events.
     */
    private fun storeActivitiesBySlug(accountId: String, newActivities: List<MApiTransaction>) {
        beginTransaction()
        backgroundQueue.execute {
            val newestActivitiesBySlug = mutableMapOf<String, JSONObject>()
            for ((slug, slugActivities) in newActivities.groupBy { it.getTxSlug() }) {
                setListTransactions(
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
                newestActivitiesBySlug,
            )
            setListTransactions(
                accountId = accountId,
                slug = null,
                activitiesToSave = newActivities,
                afterPaginate = false,
            )
            endTransaction()
        }
    }

    // Core Activity Processing ////////////////////////////////////////////////////////////////////
    /**
     * Core method that processes all received activities.
     *
     * Responsibilities:
     * - Match new activities with existing local/pending (for smooth UI transitions)
     * - Update in-memory cache
     * - Play notification sounds for incoming transactions
     * - Broadcast events to observers (ActivityLoader)
     *
     * Called by: fetchFromNetwork, newActivities
     */
    private fun processReceivedActivities(
        context: Context,
        accountId: String,
        newActivities: List<MApiTransaction>,
        pendingActivities: List<MApiTransaction>?,
        eventType: WalletEvent.ReceivedNewActivities.EventType,
    ) {
        beginTransaction()

        backgroundQueue.execute {
            val pendingAndNewActivities = pendingActivities.orEmpty() + newActivities

            // Match new activities with existing local/pending transactions
            processReplacedStableIds(accountId, pendingAndNewActivities)

            // Update pending transactions cache
            pendingActivities?.let {
                updatePendingTransactions(accountId, it)
            }

            // Apply filters
            val filteredActivities = ActivityHelpers.filter(
                accountId,
                newActivities,
                false,
                null
            )!!

            // Update in-memory cache
            updateInMemoryCache(accountId, filteredActivities, pendingAndNewActivities)

            // Play notification sound for incoming transactions
            if (eventType != WalletEvent.ReceivedNewActivities.EventType.PAGINATE) {
                playIncomingTransactionSound(context, accountId, pendingAndNewActivities)
            }
            notifiedIds.addAll(pendingAndNewActivities.map { it.id })

            // Broadcast event to observers (not for pagination - handled by ActivityLoader)
            if (eventType != WalletEvent.ReceivedNewActivities.EventType.PAGINATE) {
                notifyActivityEvent(accountId, newActivities, eventType)
            }

            endTransaction()
        }
    }

    /**
     * Match new activities with existing local/pending transactions.
     *
     * Sets replacedStableId on matching activities to enable smooth UI animations
     * when a local/pending transaction is confirmed and replaced by a real one.
     */
    private fun processReplacedStableIds(
        accountId: String,
        pendingAndNewActivities: List<MApiTransaction>
    ) {
        val accountState = _accountStates[accountId]
        val existingTemporaryActivities =
            (accountState?.pendingTransactions ?: emptyList()) + (accountState?.localTransactions
                ?: emptyList())

        for (tempActivity in existingTemporaryActivities) {
            pendingAndNewActivities
                .firstOrNull { newActivity -> tempActivity.isSame(newActivity) }
                ?.let { newActivity ->
                    newActivity.replacedStableId = tempActivity.getStableId()
                }
        }
    }

    private fun updateInMemoryCache(
        accountId: String,
        filteredActivities: List<MApiTransaction>,
        pendingAndNewActivities: List<MApiTransaction>
    ) {
        val accountState = _accountStates[accountId]
        val accountCache = accountState?.cachedTransactions
        val localTransactions = accountState?.localTransactions ?: emptyList()

        // Remove matched local transactions
        if (localTransactions.isNotEmpty()) {
            for (pendingActivity in pendingAndNewActivities) {
                localTransactions.firstOrNull {
                    ActivityHelpers.localActivityMatches(it, pendingActivity)
                }?.let { localTransaction ->
                    removeAccountLocalTransaction(accountId, localTransaction.id)
                }
            }
        }

        // Update or add to cache
        if ((accountCache?.keys?.size ?: 0) > 0) {
            val newActivities = mutableMapOf<String, MApiTransaction>()
            for (activity in filteredActivities) {
                val existing = accountCache?.get(activity.id)
                if (existing != null) {
                    if (activity.isChanged(existing)) {
                        updateCachedTransaction(accountId, activity)
                    }
                } else {
                    newActivities[activity.id] = activity
                }
            }
            addCachedTransactions(accountId, newActivities.values.toTypedArray())
        } else {
            // First time - create new cache
            val newCache = HashMap(filteredActivities.associateBy { it.id })
            setCachedTransactions(accountId, newCache)
        }
    }

    private fun playIncomingTransactionSound(
        context: Context,
        accountId: String,
        activities: List<MApiTransaction>
    ) {
        if (accountId != AccountStore.activeAccountId) return
        if (!WGlobalStorage.getAreSoundsActive()) return
        if (WalletContextManager.delegate?.isAppUnlocked() != true) return

        val hasNewIncoming = activities.any { activity ->
            val isRecent =
                System.currentTimeMillis() / 1000 - activity.timestamp / 1000 < NEW_TRANSACTION_THRESHOLD_SECONDS
            activity is MApiTransaction.Transaction &&
                activity.isIncoming &&
                !activity.isPending() &&
                !notifiedIds.contains(activity.id) &&
                isRecent &&
                !activity.isPoisoning(accountId) &&
                (!WGlobalStorage.getAreTinyTransfersHidden() || !activity.isTinyOrScam)
        }

        if (hasNewIncoming) {
            AudioHelpers.play(context, AudioHelpers.Sound.IncomingTransaction)
        }
    }

    private fun notifyActivityEvent(
        accountId: String,
        activities: List<MApiTransaction>,
        eventType: WalletEvent.ReceivedNewActivities.EventType,
    ) {
        backgroundQueue.execute {
            val walletEvent = WalletEvent.ReceivedNewActivities(
                accountId = accountId,
                newActivities = activities,
                eventType = eventType,
            )
            WalletCore.notifyEvent(walletEvent)
        }
    }

    // Cache Management ////////////////////////////////////////////////////////////////////////////
    private fun getCachedTransactions(): Map<String, Map<String, MApiTransaction>> {
        return _accountStates.mapValues { it.value.cachedTransactions }
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
        transactions: HashMap<String, MApiTransaction>
    ) {
        getOrCreateAccountState(accountId).cachedTransactions = transactions
        transactions.values.forEach {
            PoisoningCacheHelper.updatePoisoningCache(accountId, it)
        }
    }

    // Local/Pending Transaction Management ////////////////////////////////////////////////////////
    private fun updateLocalTransactions(accountId: String, transactions: List<MApiTransaction>?) {
        if (transactions != null) {
            getOrCreateAccountState(accountId).localTransactions = transactions
        } else {
            _accountStates[accountId]?.localTransactions = emptyList()
        }
    }

    private fun updatePendingTransactions(accountId: String, transactions: List<MApiTransaction>?) {
        if (transactions != null) {
            getOrCreateAccountState(accountId).pendingTransactions = transactions
        } else {
            _accountStates[accountId]?.pendingTransactions = emptyList()
        }
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
            _accountStates[accountId]?.newestActivitiesBySlug,
            IGlobalStorageProvider.PERSIST_NORMAL
        )
    }

    // Transaction List Retrieval //////////////////////////////////////////////////////////////////
    private fun getTransactionList(
        accountId: String,
        slug: String?,
        beforeId: String?,
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
        val accountState = _accountStates[accountId] ?: return emptyList()

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
     * Re-enables WGlobalStorage disk sync.
     * Executed on background queue to ensure all writes complete first.
     */
    private fun endTransaction() {
        backgroundQueue.execute {
            WGlobalStorage.decDoNotSynchronize()
        }
    }
}
