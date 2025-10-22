package org.mytonwallet.app_air.walletcore.stores

import android.content.Context
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
import org.mytonwallet.app_air.walletcore.api.fetchAllActivitySlice
import org.mytonwallet.app_air.walletcore.api.fetchTokenActivitySlice
import org.mytonwallet.app_air.walletcore.helpers.ActivityHelpers
import org.mytonwallet.app_air.walletcore.helpers.ActivityHelpers.Companion.isSuitableToGetTimestamp
import org.mytonwallet.app_air.walletcore.helpers.PoisoningCacheHelper
import org.mytonwallet.app_air.walletcore.moshi.ApiTransactionStatus
import org.mytonwallet.app_air.walletcore.moshi.MApiTransaction
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors

object ActivityStore : IStore {
    // queue the tasks
    private val backgroundQueue = Executors.newSingleThreadExecutor()

    private var _cachedTransactions = ConcurrentHashMap<String, HashMap<String, MApiTransaction>>()

    private var _localTransactions = ConcurrentHashMap<String, List<MApiTransaction>>()
    private var _pendingTransactions = ConcurrentHashMap<String, List<MApiTransaction>>()
    fun getLocalTransactions(): Map<String, List<MApiTransaction>> {
        return _localTransactions.toMap()
    }

    private const val DEFAULT_LIMIT = 60
    private const val MAX_ITEMS_TO_CACHE_IN_LIST = 200

    data class FetchResult(
        val transactions: List<MApiTransaction>,
        val isFromCache: Boolean,
        val loadedAll: Boolean,
    )

    // Reload all the cache data from the global storage
    fun loadFromCache() {
        backgroundQueue.execute {
            for (accountId in WGlobalStorage.accountIds()) {
                val existingDict =
                    WGlobalStorage.getActivitiesDict(accountId)
                        ?: JSONObject()
                val transactions = ArrayList<MApiTransaction>()
                val keys = existingDict.keys().asSequence().toList()
                for (key in keys) {
                    transactions.add(MApiTransaction.fromJson(existingDict.getJSONObject(key))!!)
                }
                addCachedTransactions(accountId, transactions.toTypedArray())
                updatePendingTransactions(accountId, emptyList())
            }
        }
    }

    override fun wipeData() {
        clearCache()
    }

    override fun clearCache() {
        _localTransactions = ConcurrentHashMap()
        _cachedTransactions = ConcurrentHashMap()
        _pendingTransactions = ConcurrentHashMap()
    }

    // Called to fetch data for a list
    fun fetchTransactions(
        context: Context,
        accountId: String,
        tokenSlug: String?,
        before: MApiTransaction?,
        callback: (FetchResult) -> Unit,
    ) {
        backgroundQueue.execute {
            // Fetch from offline storage
            val stopLazyLoad = fetchTransactionsFromCache(
                accountId = accountId,
                tokenSlug = tokenSlug,
                beforeId = before?.id,
                callback = callback
            )
            if (stopLazyLoad)
                return@execute
            if (tokenSlug == null && !AccountStore.isAccountInitialized && before == null)
                return@execute // Wait for the initialization, it will contain the 1st page data, no need to call APIs now.

            // Call the API and update cache
            fetchTransactionsOnline(
                context = context,
                accountId = accountId,
                tokenSlug = tokenSlug,
                before = before,
                callback = callback,
            )
        }
    }

    // Store a list into global storage, called after SDK events or after list updates from ActivityLoader
    fun setListTransactions(
        accountId: String,
        slug: String?,
        activitiesToSave: List<MApiTransaction>,
        insertBeforeExistingItems: Boolean,
        overrideLoadedAll: Boolean? = null
    ) {
        backgroundQueue.execute {
            val activitiesToSave = ActivityHelpers.filter(
                activitiesToSave.filter { !it.isLocal() && (it as? MApiTransaction.Transaction)?.isPending() != true },
                false,
                slug
            )!!

            var ids = activitiesToSave.map { it.id }
            var loadedAll = overrideLoadedAll
            val existingIds =
                WGlobalStorage.getActivityIds(accountId, slug) ?: emptyArray()
            if (insertBeforeExistingItems) {
                ids = ids + existingIds.filter { !ids.contains(it) }
            } else {
                if (existingIds.isNotEmpty()) {
                    val firstIndex = ids.indexOf(existingIds.first())
                    val lastIndex = ids.indexOf(existingIds.last())

                    ids = when {
                        firstIndex < 0 -> ids
                        else -> {
                            val prefix = if (firstIndex > 0) ids.take(firstIndex) else emptyList()
                            val suffix =
                                if (lastIndex >= 0) ids.drop(lastIndex + 1) else emptyList()
                            prefix + existingIds + suffix
                        }
                    }
                    // Check if existingIds already contains all the transactions
                    if (loadedAll != true && firstIndex > -1) {
                        loadedAll = WGlobalStorage.isHistoryEndReached(accountId, slug)
                    }
                } else if (loadedAll == null) {
                    // New items array doesn't contain the first item from the previous list, so should reset loadedAll flag to false
                    loadedAll = false
                }
            }

            val limitedIds = ids.take(MAX_ITEMS_TO_CACHE_IN_LIST).toTypedArray()
            val limitedTransactionsToSave = activitiesToSave.take(MAX_ITEMS_TO_CACHE_IN_LIST)
            val dict = JSONObject()
            for (it in limitedTransactionsToSave) {
                dict.put(it.id, it.toDictionary())
            }

            // Update activities cache
            val existingDict =
                WGlobalStorage.getActivitiesDict(accountId)
                    ?: JSONObject()
            existingDict.add(dict)
            WGlobalStorage.setActivitiesDict(accountId, existingDict)

            WGlobalStorage.setActivityIds(accountId, slug, limitedIds)

            loadedAll?.let {
                Logger.d(
                    Logger.LogTag.ACTIVITY_STORE,
                    "Storing transactions for $accountId - slug: $slug - set loadedAll: ${loadedAll == true && limitedIds.size == ids.size}"
                )
                WGlobalStorage.setIsHistoryEndReached(
                    accountId,
                    slug,
                    value = loadedAll && limitedIds.size == ids.size,
                )
            }
        }
    }

    // Process newly received activities from the SDK
    fun initialActivities(
        context: Context,
        accountId: String,
        mainActivities: List<MApiTransaction>,
        bySlug: Map<String, List<MApiTransaction>>
    ) {
        AccountStore.isAccountInitialized = true
        val newActs = mainActivities + bySlug.values.flatten()
        received(
            context = context,
            accountId = accountId,
            newActivities = newActs,
            pendingActivities = null,
            isUpdateEvent = true,
            loadedAll = newActs.isEmpty()
        )
        beginTransaction()
        val newestActivitiesBySlug = mutableMapOf<String, JSONObject?>()
        backgroundQueue.execute {
            for ((slug, activities) in bySlug) {
                setListTransactions(
                    accountId = accountId,
                    slug = slug,
                    activitiesToSave = activities,
                    insertBeforeExistingItems = activities.size < 10,
                    overrideLoadedAll = activities.isEmpty()
                )
                newestActivitiesBySlug[slug] =
                    activities.firstOrNull(::isSuitableToGetTimestamp)?.toDictionary()
            }
            setListTransactions(
                accountId = accountId,
                slug = null,
                activitiesToSave = mainActivities,
                insertBeforeExistingItems = mainActivities.size < 10,
                overrideLoadedAll = mainActivities.isEmpty()
            )
            WGlobalStorage.setNewestActivitiesBySlug(
                accountId,
                newestActivitiesBySlug,
                IGlobalStorageProvider.PERSIST_NO
            )
        }
        endTransaction()
    }

    fun newActivities(
        context: Context,
        accountId: String,
        newActivities: List<MApiTransaction>,
        pendingActivities: List<MApiTransaction>
    ) {
        AccountStore.isAccountInitialized = true
        received(
            context = context,
            accountId = accountId,
            newActivities = newActivities,
            pendingActivities = pendingActivities,
            isUpdateEvent = true,
            loadedAll = null
        )
        storeActivities(accountId, newActivities)
    }

    fun receivedLocalTransaction(
        accountId: String,
        newLocalTransaction: MApiTransaction
    ) {
        addAccountLocalTransactions(accountId, newLocalTransaction)
        // Store swap transfers
        if (!newLocalTransaction.isLocal() && !newLocalTransaction.isPending()) {
            storeActivities(accountId, listOf(newLocalTransaction))
        }
        backgroundQueue.execute {
            val walletEvent = WalletEvent.ReceivedNewActivities(
                accountId = accountId,
                newActivities = listOf(newLocalTransaction),
                isUpdateEvent = true,
                loadedAll = null
            )
            WalletCore.notifyEvent(walletEvent)
        }
    }

    private fun storeActivities(accountId: String, newActivities: List<MApiTransaction>) {
        beginTransaction()
        backgroundQueue.execute {
            val newestActivitiesBySlug = mutableMapOf<String, JSONObject?>()
            for ((slug, slugActivities) in newActivities.groupBy { it.getTxSlug() }) {
                setListTransactions(
                    accountId = accountId,
                    slug = slug,
                    activitiesToSave = slugActivities,
                    insertBeforeExistingItems = slugActivities.size < 10
                )
                newestActivitiesBySlug[slug] = slugActivities.firstOrNull()?.toDictionary()
            }
            WGlobalStorage.setNewestActivitiesBySlug(
                accountId,
                newestActivitiesBySlug,
                IGlobalStorageProvider.PERSIST_NO
            )
            setListTransactions(
                accountId = accountId,
                slug = null,
                activitiesToSave = newActivities,
                insertBeforeExistingItems = newActivities.size < 10
            )
        }
        endTransaction()
    }

    // Read a list from cache
    private fun fetchTransactionsFromCache(
        accountId: String,
        tokenSlug: String?,
        beforeId: String?,
        callback: (FetchResult) -> Unit,
    ): Boolean {
        val transactions = getTransactionList(accountId, tokenSlug, beforeId, DEFAULT_LIMIT)
        if (transactions.isNotEmpty()) {
            // Found cached transactions, pass them.
            callback(
                FetchResult(
                    transactions,
                    isFromCache = true,
                    loadedAll = false
                )
            )
            return true
        }

        val isHistoryEndReached = WGlobalStorage.isHistoryEndReached(accountId, tokenSlug)
        val isLoadingMore = beforeId != null
        if (isHistoryEndReached && isLoadingMore) {
            // No more cached transactions found, and the history end is already reached, stop the lazy load.
            callback(
                FetchResult(
                    emptyList(),
                    isFromCache = true,
                    loadedAll = true
                )
            )
            return true
        }

        if (beforeId == null) {
            // No cached transactions found, so we will be waiting for network requests, just poke the callback to let it know and handle UI correctly.
            callback(
                FetchResult(
                    emptyList(),
                    isFromCache = true,
                    loadedAll = isHistoryEndReached
                )
            )
        }
        return false
    }

    // Receive a list from API
    private fun fetchTransactionsOnline(
        context: Context,
        accountId: String,
        tokenSlug: String?,
        before: MApiTransaction?,
        callback: (FetchResult) -> Unit,
    ) {
        // Retry logic
        fun retry() {
            Handler(Looper.getMainLooper()).postDelayed({
                fetchTransactionsOnline(
                    context,
                    accountId,
                    tokenSlug,
                    before,
                    callback,
                )
            }, 3000)
        }

        Handler(Looper.getMainLooper()).post {
            if (tokenSlug == null) {
                WalletCore.fetchAllActivitySlice(
                    accountId = accountId,
                    limit = DEFAULT_LIMIT,
                    toTimestamp = before?.timestamp,
                ) { fetchedTransactions, err ->
                    if (fetchedTransactions == null || err != null) {
                        retry()
                        return@fetchAllActivitySlice
                    }

                    val cachedTransactions = getCachedTransactions()[accountId]
                    if (before == null && fetchedTransactions.isNotEmpty()) {
                        val lastTxId = fetchedTransactions.last().id
                        if (cachedTransactions?.get(lastTxId) == null) {
                            setListTransactions(
                                accountId,
                                tokenSlug,
                                emptyList(),
                                false
                            )
                            val walletEvent =
                                WalletEvent.InvalidateCache(accountId, tokenSlug)
                            WalletCore.notifyEvent(walletEvent)
                            WGlobalStorage.setIsHistoryEndReached(
                                accountId,
                                null,
                                value = false,
                            )
                        }
                    }

                    received(
                        context = context,
                        accountId = accountId,
                        newActivities = fetchedTransactions,
                        pendingActivities = null,
                        isUpdateEvent = false,
                        loadedAll = null
                    )
                    backgroundQueue.execute {
                        callback(
                            FetchResult(
                                fetchedTransactions,
                                isFromCache = false,
                                loadedAll = fetchedTransactions.isEmpty()
                            )
                        )
                    }
                }
            } else {
                WalletCore.fetchTokenActivitySlice(
                    accountId = accountId,
                    slug = tokenSlug,
                    fromTimestamp = before?.timestamp,
                    limit = DEFAULT_LIMIT
                ) { fetchedTransactions, err, _ ->
                    if (fetchedTransactions == null || err != null) {
                        retry()
                        return@fetchTokenActivitySlice
                    }

                    val cachedTransactions = getCachedTransactions()[accountId]
                    if (before == null && fetchedTransactions.isNotEmpty()) {
                        val lastTxId = fetchedTransactions.last().id
                        if (cachedTransactions?.get(lastTxId) == null) {
                            setListTransactions(
                                accountId,
                                tokenSlug,
                                emptyList(),
                                false
                            )
                            val walletEvent =
                                WalletEvent.InvalidateCache(accountId, tokenSlug)
                            WalletCore.notifyEvent(walletEvent)
                            WGlobalStorage.setIsHistoryEndReached(
                                accountId,
                                null,
                                value = false,
                            )
                        }
                    }

                    received(
                        context = context,
                        accountId = accountId,
                        newActivities = fetchedTransactions,
                        pendingActivities = null,
                        isUpdateEvent = false,
                        loadedAll = null
                    )
                    backgroundQueue.execute {
                        callback(
                            FetchResult(
                                fetchedTransactions,
                                isFromCache = false,
                                loadedAll = fetchedTransactions.isEmpty()
                            )
                        )
                    }
                }
            }
        }
    }

    private fun getCachedTransactions(): HashMap<String, HashMap<String, MApiTransaction>> {
        synchronized(this) {
            return HashMap(_cachedTransactions)
        }
    }

    fun updateCachedTransaction(accountId: String, transaction: MApiTransaction) {
        synchronized(this) {
            if (_cachedTransactions[accountId] == null)
                _cachedTransactions[accountId] = HashMap()
            _cachedTransactions[accountId]?.set(transaction.id, transaction)
            PoisoningCacheHelper.updatePoisoningCache(transaction)
        }
    }

    private fun addCachedTransactions(accountId: String, transactions: Array<MApiTransaction>) {
        synchronized(this) {
            if (_cachedTransactions[accountId] == null)
                _cachedTransactions[accountId] = HashMap()
            for (transaction in transactions) {
                _cachedTransactions[accountId]?.set(transaction.id, transaction)
                PoisoningCacheHelper.updatePoisoningCache(transaction)
            }
        }
    }

    private fun setCachedTransactions(
        accountId: String,
        transactions: HashMap<String, MApiTransaction>
    ) {
        synchronized(this) {
            _cachedTransactions[accountId] = transactions
            transactions.values.forEach {
                PoisoningCacheHelper.updatePoisoningCache(it)
            }
        }
    }

    private fun updateLocalTransactions(accountId: String, transactions: List<MApiTransaction>?) {
        synchronized(this) {
            transactions?.let {
                _localTransactions[accountId] = transactions
            } ?: run {
                _localTransactions.remove(accountId)
            }
        }
    }

    fun getPendingTransactions(accountId: String): List<MApiTransaction> {
        return _pendingTransactions[accountId] ?: emptyList()
    }

    private fun updatePendingTransactions(accountId: String, transactions: List<MApiTransaction>?) {
        synchronized(this) {
            transactions?.let {
                _pendingTransactions[accountId] = transactions
            } ?: run {
                _pendingTransactions.remove(accountId)
            }
        }
    }

    private fun getTransactionList(
        accountId: String,
        slug: String?,
        beforeId: String?,
        limit: Int?
    ): List<MApiTransaction> {
        val transactionIds: List<String> = (WGlobalStorage.getActivityIds(
            accountId, slug
        ) ?: emptyArray()).toList()

        val filteredTransactionIds: List<String> = if (beforeId != null) {
            val index = transactionIds.lastIndexOf(beforeId)
            if (index != -1) {
                transactionIds.drop(index + 1)
            } else {
                return emptyList()
            }
        } else {
            transactionIds
        }

        val limitedTransactionIds: List<String> = if (limit != null) {
            filteredTransactionIds.take(limit)
        } else {
            filteredTransactionIds
        }

        val cachedTransactions = getCachedTransactions()[accountId]
        return limitedTransactionIds.mapNotNull { id ->
            cachedTransactions?.get(id)
        }
    }

    private fun lastTxIds(accountId: String, after: Long): Map<String, String> {
        val all = getTransactionList(accountId, slug = null, beforeId = null, limit = null)
            .filter { it.timestamp >= after }

        val idsBySlug = mutableMapOf<String, String>()
        for (transaction in all) {
            if (transaction.id.contains("|") || transaction.id.contains("swap")) {
                continue
            }
            idsBySlug[transaction.getTxSlug()] = transaction.id
        }

        return idsBySlug
    }

    private fun localActivityMatches(
        it: MApiTransaction,
        newActivity: MApiTransaction
    ): Boolean {
        if (it.extra?.withW5Gasless == true) {
            when (it) {
                is MApiTransaction.Swap -> {
                    if (newActivity is MApiTransaction.Swap) {
                        return it.from == newActivity.from &&
                            it.to == newActivity.to &&
                            it.fromAmount == newActivity.fromAmount
                    }
                }

                is MApiTransaction.Transaction -> {
                    if (newActivity is MApiTransaction.Transaction) {
                        return !newActivity.isIncoming &&
                            it.normalizedAddress == newActivity.normalizedAddress &&
                            it.amount == newActivity.amount &&
                            it.slug == newActivity.slug
                    }
                }
            }
        }

        it.externalMsgHashNorm?.let { localHash ->
            return localHash == newActivity.externalMsgHashNorm && newActivity.shouldHide != true
        }

        return it.parsedTxId.hash == newActivity.parsedTxId.hash
    }

    // Process newly received list from service or bridge event
    private fun received(
        context: Context,
        accountId: String,
        newActivities: List<MApiTransaction>,
        pendingActivities: List<MApiTransaction>?,
        isUpdateEvent: Boolean,
        loadedAll: Boolean?
    ) {
        pendingActivities?.let {
            updatePendingTransactions(accountId, pendingActivities)
        }

        val newActivities = ActivityHelpers.filter(
            newActivities,
            false,
            null
        )!!

        val accountCachedTransactionsDict = getCachedTransactions()[accountId]

        beginTransaction()
        val localTransactions = getLocalTransactions()[accountId] ?: emptyList()

        if ((accountCachedTransactionsDict?.keys?.size ?: 0) > 0) {
            val addedActivities = mutableMapOf<String, MApiTransaction>()
            for (newActivity in newActivities) {
                localTransactions.firstOrNull {
                    localActivityMatches(it, newActivity)
                }?.let { localTransaction ->
                    removeAccountLocalTransaction(accountId, localTransaction.id)
                }

                accountCachedTransactionsDict?.get(newActivity.id)?.let { prevTransaction ->
                    if (newActivity.isChanged(prevTransaction)) {
                        updateCachedTransaction(accountId, newActivity)
                    }/* else if (newActivity.nft != null && newActivity.nft != prevTransaction.nft) {
                        updateCachedTransaction(accountId, newActivity)
                    }*/
                } ?: run {
                    addedActivities[newActivity.id] = newActivity
                }
            }
            addCachedTransactions(accountId, addedActivities.values.toTypedArray())
        } else {
            val newCachedTransactions = HashMap(newActivities.associateBy { it.id })
            setCachedTransactions(accountId, newCachedTransactions)
        }

        if (accountId == AccountStore.activeAccountId) {
            // Play sound for new incoming transactions within this batch
            if (isUpdateEvent &&
                WGlobalStorage.getAreSoundsActive() &&
                WalletContextManager.delegate?.isAppUnlocked() == true &&
                newActivities.any { act ->
                    val isNew = System.currentTimeMillis() / 1000 - act.timestamp / 1000 < 60
                    act is MApiTransaction.Transaction &&
                        act.isIncoming &&
                        act.status == ApiTransactionStatus.COMPLETED &&
                        isNew &&
                        (!WGlobalStorage.getAreTinyTransfersHidden() || !act.isTinyOrScam())
                }
            ) {
                AudioHelpers.play(
                    context,
                    AudioHelpers.Sound.IncomingTransaction
                )
            }
        }

        if (isUpdateEvent) {
            // Make sure all inner processes are already done
            backgroundQueue.execute {
                val walletEvent = WalletEvent.ReceivedNewActivities(
                    accountId,
                    newActivities,
                    isUpdateEvent,
                    loadedAll
                )
                WalletCore.notifyEvent(walletEvent)
            }
        }

        endTransaction()
    }

    private fun addAccountLocalTransactions(accountId: String, localTransaction: MApiTransaction) {
        updateLocalTransactions(
            accountId,
            (getLocalTransactions()[accountId] ?: emptyList()).plus(localTransaction)
        )
    }

    private fun removeAccountLocalTransaction(accountId: String, id: String) {
        updateLocalTransactions(
            accountId = accountId,
            getLocalTransactions()[accountId]?.filter { it.id != id } ?: emptyList()
        )
    }

    private fun beginTransaction() {
        WGlobalStorage.incDoNotSynchronize()
    }

    private fun endTransaction() {
        backgroundQueue.execute {
            WGlobalStorage.decDoNotSynchronize()
        }
    }

    fun removeAccount(removingAccountId: String) {
        backgroundQueue.execute {
            synchronized(this) {
                _cachedTransactions.remove(removingAccountId)
                _localTransactions.remove(removingAccountId)
                _pendingTransactions.remove(removingAccountId)
            }
        }
    }

}
