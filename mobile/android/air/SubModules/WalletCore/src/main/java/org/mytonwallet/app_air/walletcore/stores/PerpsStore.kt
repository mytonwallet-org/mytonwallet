package org.mytonwallet.app_air.walletcore.stores

import com.squareup.moshi.JsonAdapter
import com.squareup.moshi.Types
import java.util.WeakHashMap
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.delay
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.launch
import org.mytonwallet.app_air.walletbasecontext.utils.MHistoryTimePeriod
import org.mytonwallet.app_air.walletcontext.cacheStorage.WCacheStorage
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcore.JSWebViewBridge
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.models.MAccount
import org.mytonwallet.app_air.walletcore.models.blockchain.MBlockchain
import org.mytonwallet.app_air.walletcore.moshi.MApiPerpsCatalogue
import org.mytonwallet.app_air.walletcore.moshi.MApiPerpsFill
import org.mytonwallet.app_air.walletcore.moshi.MApiPerpsListedAsset
import org.mytonwallet.app_air.walletcore.moshi.MApiPerpsMarketSection
import org.mytonwallet.app_air.walletcore.moshi.MApiPerpsOnboarding
import org.mytonwallet.app_air.walletcore.moshi.MApiPerpsOperation
import org.mytonwallet.app_air.walletcore.moshi.MApiPerpsSnapshot
import org.mytonwallet.app_air.walletcore.moshi.PERPS_OPERATION_COMPLETED
import org.mytonwallet.app_air.walletcore.moshi.PERPS_OPERATION_PARTIAL
import org.mytonwallet.app_air.walletcore.moshi.PERPS_OPERATION_RUNNING
import org.mytonwallet.app_air.walletcore.moshi.PERPS_QUOTE_CLOSE
import org.mytonwallet.app_air.walletcore.moshi.PERPS_QUOTE_REDUCE
import org.mytonwallet.app_air.walletcore.moshi.PERPS_QUOTE_WITHDRAW
import org.mytonwallet.app_air.walletcore.moshi.api.ApiMethod

/**
 * Perps markets and the active account's positions, fills and reviewed orders, shown from the cache
 * while they refresh. Loads when an account becomes active or the bridge connects, and again when
 * perps screens appear.
 */
object PerpsStore : IStore, WalletCore.EventObserver {
    private var isAssetsCacheRead = false
    private val snapshotsByAccountId = mutableMapOf<String, MApiPerpsSnapshot>()
    private val fillsByAccountId = mutableMapOf<String, List<MApiPerpsFill>>()
    private val operationsByAccountId = mutableMapOf<String, List<MApiPerpsOperation>>()
    private val reconciledAccountIds = mutableSetOf<String>()
    private val reconcilingOperationIds = mutableSetOf<String>()
    private val executingOperationIds = mutableSetOf<String>()

    // saveOperation drops settled orders
    private val settledOperations = mutableMapOf<String, MApiPerpsOperation>()
    private val dismissedOperationIds = mutableSetOf<String>()

    private var _assetsByCoin: Map<String, MApiPerpsListedAsset> = emptyMap()
    private var _assetsById: Map<String, MApiPerpsListedAsset> = emptyMap()

    val assetsByCoin: Map<String, MApiPerpsListedAsset>
        get() {
            readAssetsCacheIfNeeded()
            return _assetsByCoin
        }

    val assetsById: Map<String, MApiPerpsListedAsset>
        get() {
            readAssetsCacheIfNeeded()
            return _assetsById
        }

    /** Backend Futures groups; `null` when the backend predates them. */
    val marketSections: List<MApiPerpsMarketSection>?
        get() {
            readAssetsCacheIfNeeded()
            return _marketSections
        }
    private var _marketSections: List<MApiPerpsMarketSection>? = null

    /** `null` when the backend predates it. */
    val onboarding: MApiPerpsOnboarding?
        get() {
            readAssetsCacheIfNeeded()
            return _onboarding
        }
    private var _onboarding: MApiPerpsOnboarding? = null

    private val hasActivityHistoryByAccountId = mutableMapOf<String, Boolean>()

    // Completed trades the activity may not list yet
    private val tradedAccountIds = mutableSetOf<String>()

    private var snapshotRequest: ApiMethod.Perps.GetSnapshot? = null
    private var snapshotRequestAccountId: String? = null
    private var isSnapshotReloadQueued = false
    private var marketRequest: ApiMethod.Perps.GetMarketSnapshot? = null
    private val snapshotErrorsByAccountId = mutableMapOf<String, String>()
    private var fillsRequest: ApiMethod.Perps.GetActivityHistory? = null
    private val failedFillsAccountIds = mutableSetOf<String>()
    private var fillsRequestAccountId: String? = null
    private var isFillsReloadQueued = false
    private val fillsCursorsByAccountId = mutableMapOf<String, String>()
    private val pagedFillsAccountIds = mutableSetOf<String>()
    private val moreFillsRequests = mutableMapOf<String, ApiMethod.Perps.GetActivityHistory>()

    private val executionScope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private val cacheScope =
        CoroutineScope(SupervisorJob() + Dispatchers.IO.limitedParallelism(1))
    private var catalogueWriteJob: Job? = null

    /** Language and fetch time of the persisted catalogue. */
    private var savedCatalogueVersion: Pair<String, Long>? = null

    private val catalogueAdapter: JsonAdapter<MApiPerpsCatalogue> by lazy {
        WalletCore.moshi.adapter(MApiPerpsCatalogue::class.java)
    }
    private val snapshotAdapter: JsonAdapter<MApiPerpsSnapshot> by lazy {
        WalletCore.moshi.adapter(MApiPerpsSnapshot::class.java)
    }
    private val fillsAdapter: JsonAdapter<List<MApiPerpsFill>> by lazy {
        WalletCore.moshi.adapter(
            Types.newParameterizedType(List::class.java, MApiPerpsFill::class.java)
        )
    }
    private val operationsAdapter: JsonAdapter<List<MApiPerpsOperation>> by lazy {
        WalletCore.moshi.adapter(
            Types.newParameterizedType(List::class.java, MApiPerpsOperation::class.java)
        )
    }

    /** A bridge rebuild drops observers, and a new window sends no foreground event. */
    fun onBridgeReady() {
        WalletCore.unregisterObserver(this)
        WalletCore.registerObserver(this)
        isAppActive = true
    }

    /** Hyperliquid account address of a mainnet account; perps share the Arbitrum EVM key. */
    fun perpsAddress(account: MAccount?): String? =
        account?.takeIf { it.isMainnet }?.addressByChain?.get(MBlockchain.arbitrum.name)

    fun canTrade(account: MAccount?): Boolean =
        account?.accountType == MAccount.AccountType.MNEMONIC &&
            perpsAddress(account) != null &&
            snapshotFor(account.accountId)?.tradingAvailability?.isAvailable != false

    /** Positions and totals of the account; its catalogue lives in [assetsById]. */
    fun snapshotFor(accountId: String?): MApiPerpsSnapshot? {
        accountId ?: return null
        snapshotsByAccountId[accountId]?.let { return it }
        return readCache(WCacheStorage.getPerpsPositions(accountId), snapshotAdapter) {
            WCacheStorage.setPerpsPositions(accountId, null)
        }?.also { snapshotsByAccountId[accountId] = it }
    }

    /** Older than a minute, as on iOS. */
    fun isSnapshotStale(accountId: String?): Boolean {
        val snapshot = snapshotFor(accountId) ?: return false
        return snapshot.unavailableDexs.isNotEmpty() ||
            System.currentTimeMillis() - snapshot.timestamp >= SNAPSHOT_MAX_AGE_MS
    }

    /** A balance withdrawal is not a trade. */
    fun isNewToFutures(accountId: String?): Boolean {
        accountId ?: return false
        val snapshot = snapshotFor(accountId) ?: return false
        return snapshot.unavailableDexs.isEmpty() &&
            snapshot.openPositions.isEmpty() &&
            hasActivityHistoryByAccountId[accountId] == false &&
            accountId !in tradedAccountIds &&
            pendingOperation(accountId) == null &&
            operationsFor(accountId).none {
                it.kind != PERPS_QUOTE_WITHDRAW &&
                    (it.state == PERPS_OPERATION_COMPLETED || it.state == PERPS_OPERATION_PARTIAL)
            }
    }

    fun isLoadingFills(accountId: String?): Boolean {
        accountId ?: return false
        if (fillsFor(accountId) != null || accountId in failedFillsAccountIds) return false
        return perpsAddress(AccountStore.accountById(accountId)) != null
    }

    /** Positions of the account are not known yet, and its last request has not failed. */
    fun isLoadingPositions(accountId: String?): Boolean {
        accountId ?: return false
        if (snapshotFor(accountId) != null || accountId in snapshotErrorsByAccountId) return false
        return perpsAddress(AccountStore.accountById(accountId)) != null
    }

    /** A localization key. */
    fun snapshotError(accountId: String?): String? = snapshotErrorsByAccountId[accountId]

    /** Newest first. */
    fun fillsFor(accountId: String?): List<MApiPerpsFill>? {
        accountId ?: return null
        fillsByAccountId[accountId]?.let { return it }
        return readCache(WCacheStorage.getPerpsActivities(accountId), fillsAdapter) {
            WCacheStorage.setPerpsActivities(accountId, null)
        }?.also { fillsByAccountId[accountId] = it }
    }

    fun operation(accountId: String, id: String): MApiPerpsOperation? =
        operationsFor(accountId).firstOrNull { it.id == id }

    /**
     * The newest operation that blocks this order. A filled close or reduce awaiting its
     * withdrawal does not block closing or reducing another asset.
     */
    fun pendingOperation(
        accountId: String?,
        assetId: String? = null,
        kind: String? = null
    ): MApiPerpsOperation? = operationsFor(accountId ?: return null)
        .filter { operation ->
            operation.blocksTrading && !(
                operation.state == PERPS_OPERATION_PARTIAL &&
                    operation.orderStatus == "filled" &&
                    operation.orderId != null &&
                    (operation.kind == PERPS_QUOTE_CLOSE || operation.kind == PERPS_QUOTE_REDUCE) &&
                    assetId != null &&
                    operation.assetId != assetId &&
                    (kind == PERPS_QUOTE_CLOSE || kind == PERPS_QUOTE_REDUCE)
                )
        }
        .maxByOrNull { it.createdAt }

    /** The operation to surface on the home screen; hiding it never unblocks trading. */
    fun visibleOperationStatus(accountId: String?): MApiPerpsOperation? =
        operationsFor(accountId ?: return null)
            .filter {
                (it.blocksTrading || it.isUnseenPartialFill) && it.id !in dismissedOperationIds
            }
            .maxByOrNull { it.createdAt }

    /** Deletes a seen partial fill; hides others until relaunch. */
    fun dismissOperationStatus(id: String) {
        operationsByAccountId.entries
            .firstOrNull { (_, operations) ->
                operations.any { it.id == id && it.isUnseenPartialFill }
            }
            ?.let { (accountId, operations) ->
                setOperations(accountId, operations.filter { it.id != id })
            }
        if (dismissedOperationIds.add(id)) WalletCore.notifyEvent(WalletEvent.PerpsUpdated)
    }

    /** Runs the order outside its screen, so closing it doesn't stop it settling. */
    fun execute(
        initial: MApiPerpsOperation,
        submit: suspend () -> MApiPerpsOperation,
        resolveFailure: (current: MApiPerpsOperation, error: Throwable) -> MApiPerpsOperation
    ): Deferred<MApiPerpsOperation> {
        // Not reconciled while running here
        executingOperationIds.add(initial.id)
        saveOperation(initial)
        return executionScope.async {
            val result = try {
                submit().also { check(it.isSameOperation(initial)) }
            } catch (e: Throwable) {
                // The bridge reports an operation that carries an `error` as a failed call
                ((e as? JSWebViewBridge.ApiError)?.parsedResult as? MApiPerpsOperation)
                    ?.takeIf { it.isSameOperation(initial) }
                    ?: (
                        settledOperations[initial.id]
                            ?: operation(initial.accountId, initial.id)
                            ?: initial
                        ).let { current ->
                        if (current.state ==
                            PERPS_OPERATION_RUNNING
                        ) {
                            resolveFailure(current, e)
                        } else {
                            current
                        }
                    }
            }
            executingOperationIds.remove(initial.id)
            settledOperations.remove(initial.id)
            saveOperation(result)
            loadSnapshot(force = true)
            loadFills(force = true)
            result
        }
    }

    private fun MApiPerpsOperation.isSameOperation(other: MApiPerpsOperation) =
        id == other.id && accountId == other.accountId && assetId == other.assetId &&
            kind == other.kind

    /** Saves the operation for recovery after a restart; settled ones are forgotten once seen. */
    fun saveOperation(operation: MApiPerpsOperation) {
        val accountId = operation.accountId
        if (WGlobalStorage.getAccount(accountId) == null) return
        if (operation.kind != PERPS_QUOTE_WITHDRAW &&
            operation.state == PERPS_OPERATION_COMPLETED
        ) {
            tradedAccountIds += accountId
        }
        val current = operationsFor(accountId)
        val reviewedQuote = operation.reviewedQuote
            ?: current.firstOrNull { it.id == operation.id }?.reviewedQuote
        val operations = current.filter { it.id != operation.id } +
            listOfNotNull(
                operation.copy(reviewedQuote = reviewedQuote)
                    .takeIf { it.isUnresolved || it.isUnseenPartialFill }
            )
        setOperations(accountId, operations)
        WalletCore.notifyEvent(WalletEvent.PerpsUpdated)
    }

    fun receiveOperationUpdate(operation: MApiPerpsOperation) {
        if (operation.id !in executingOperationIds) return
        val previous = operation(operation.accountId, operation.id) ?: return
        if (previous.assetId != operation.assetId ||
            previous.kind != operation.kind ||
            previous.state != PERPS_OPERATION_RUNNING
        ) {
            return
        }
        if (operation.state != PERPS_OPERATION_RUNNING) settledOperations[operation.id] = operation
        saveOperation(operation)
    }

    /** Reconciles the active account's operations again, for a screen showing their status. */
    fun refreshOperations() {
        AccountStore.activeAccountId?.let(reconciledAccountIds::remove)
        refresh()
    }

    /** Refreshes everything the perps screens show for the active account. */
    fun refresh() {
        loadSnapshot()
        loadFills()
        reconcileOperationsOnce()
    }

    override fun onWalletEvent(walletEvent: WalletEvent) {
        when (walletEvent) {
            is WalletEvent.AccountChanged -> {
                // Reloads from the skeleton, not the last failure
                walletEvent.accountId?.let {
                    snapshotErrorsByAccountId.remove(it)
                    failedFillsAccountIds.remove(it)
                }
                refresh()
            }

            is WalletEvent.AccountRemoved -> forgetAccount(walletEvent.accountId)

            WalletEvent.NetworkConnected -> refresh()

            WalletEvent.AppForeground -> isAppActive = true

            WalletEvent.AppBackground -> isAppActive = false

            else -> {}
        }
    }

    private var isAppActive = true

    // Weak, so a destroyed screen stops counting
    private val watchers = WeakHashMap<Any, Long>()
    private var watchJob: Job? = null
    private var watchIntervalMs: Long? = null

    /** Polls at the shortest interval any owner asks for, as on iOS. */
    fun watch(owner: Any, intervalMs: Long = POLL_INTERVAL_MS) {
        watchers[owner] = intervalMs
        updateWatchLoop()
    }

    fun unwatch(owner: Any) {
        if (watchers.remove(owner) != null) updateWatchLoop()
    }

    private fun updateWatchLoop() {
        val intervalMs = watchers.values.minOrNull()
        if (intervalMs == watchIntervalMs) return
        watchIntervalMs = intervalMs
        watchJob?.cancel()
        watchJob = intervalMs?.let {
            executionScope.launch {
                while (true) {
                    delay(it)
                    if (watchers.isEmpty()) break
                    poll()
                }
                watchIntervalMs = null
                watchJob = null
            }
        }
    }

    /** A shown screen's periodic refresh of positions, activity and orders; skipped in the background. */
    private fun poll() {
        if (!isAppActive) return
        loadSnapshot()
        loadFills()
        AccountStore.activeAccountId?.let(::reconcileOperations)
    }

    /**
     * Chart prices of an asset in the base currency, as tokens load theirs: a fresh cached copy
     * first, then the network. Kept with token histories, so a base currency change clears them.
     */
    fun loadPriceHistory(
        assetId: String,
        period: MHistoryTimePeriod,
        callback: (data: Array<Array<Double>>?, fromCache: Boolean) -> Unit
    ) {
        val cacheKey = PRICE_HISTORY_PREFIX + assetId
        WGlobalStorage.getPriceHistory(cacheKey, period.value)
            ?.takeIf { isPriceHistoryFresh(it, period) }
            ?.let { callback(it, true) }
        val baseCurrency = WalletCore.baseCurrency
        WalletCore.call(ApiMethod.Perps.GetCandles(assetId, period.value)) { res, _ ->
            if (WalletCore.baseCurrency != baseCurrency) return@call
            if (res == null) {
                callback(null, false)
                return@call
            }
            // Candles are in USD
            val rate = TokenStore.baseCurrencyRate ?: 1.0
            val data = res.mapNotNull { point ->
                val time = point.getOrNull(0) ?: return@mapNotNull null
                val price = point.getOrNull(1) ?: return@mapNotNull null
                arrayOf(time, price * rate)
            }.toTypedArray()
            WGlobalStorage.setPriceHistory(cacheKey, period.value, data)
            callback(data, false)
        }
    }

    /** The same ages as token histories; candle timestamps are in seconds. */
    private fun isPriceHistoryFresh(
        data: Array<Array<Double>>,
        period: MHistoryTimePeriod
    ): Boolean {
        val lastTimestamp = data.lastOrNull()?.firstOrNull() ?: return true
        val maxAgeHours = when (period) {
            MHistoryTimePeriod.DAY -> 3
            MHistoryTimePeriod.WEEK -> 24
            MHistoryTimePeriod.MONTH -> 4 * 24
            MHistoryTimePeriod.THREE_MONTHS -> 12 * 24
            MHistoryTimePeriod.YEAR, MHistoryTimePeriod.ALL -> 45 * 24
        }
        return System.currentTimeMillis() / 1000 - lastTimestamp <= maxAgeHours * 3600
    }

    /** Reuses a request in flight for the account; [force] reads again after it. */
    fun loadSnapshot(force: Boolean = false) {
        val account = AccountStore.activeAccount
        if (!WalletCore.isBridgeReady) {
            snapshotRequest = null
            return
        }
        if (account == null || perpsAddress(account) == null) {
            snapshotRequest = null
            loadMarket()
            return
        }
        val accountId = account.accountId
        if (snapshotRequest != null && snapshotRequestAccountId == accountId) {
            if (force) isSnapshotReloadQueued = true
            return
        }
        val langCode = WGlobalStorage.getLangCode()
        val request = ApiMethod.Perps.GetSnapshot(accountId, langCode)
        snapshotRequest = request
        snapshotRequestAccountId = accountId
        isSnapshotReloadQueued = false
        WalletCore.call(request) { res, _ ->
            if (snapshotRequest !== request) return@call
            snapshotRequest = null
            if (res == null) {
                snapshotErrorsByAccountId[accountId] = SNAPSHOT_UNAVAILABLE_ERROR
            } else {
                applyCatalogue(
                    langCode,
                    MApiPerpsCatalogue(res.assets, res.marketSections, res.onboarding),
                    res.assetsFetchedAt
                )
                if (WGlobalStorage.getAccount(accountId) != null) applySnapshot(accountId, res)
            }
            WalletCore.notifyEvent(WalletEvent.PerpsUpdated)
            if (isSnapshotReloadQueued) loadSnapshot()
        }
    }

    // An incomplete read replaces only an absent portfolio, as its totals would understate it
    private fun applySnapshot(accountId: String, res: MApiPerpsSnapshot) {
        val isComplete = res.unavailableDexs.isEmpty()
        if (isComplete || snapshotFor(accountId) == null) {
            val snapshot = res.copy(assets = emptyList(), marketSections = null, onboarding = null)
            snapshotsByAccountId[accountId] = snapshot
            WCacheStorage.setPerpsPositions(accountId, snapshotAdapter.toJson(snapshot))
        }
        if (isComplete) {
            snapshotErrorsByAccountId.remove(accountId)
        } else {
            snapshotErrorsByAccountId[accountId] = SNAPSHOT_INCOMPLETE_ERROR
        }
    }

    /** The catalogue alone, for an account without perps. */
    private fun loadMarket() {
        if (marketRequest != null) return
        val langCode = WGlobalStorage.getLangCode()
        val request = ApiMethod.Perps.GetMarketSnapshot(langCode)
        marketRequest = request
        WalletCore.call(request) { res, _ ->
            if (marketRequest !== request) return@call
            marketRequest = null
            res ?: return@call
            applyCatalogue(
                langCode,
                MApiPerpsCatalogue(res.assets, res.marketSections, res.onboarding),
                res.assetsFetchedAt
            )
            WalletCore.notifyEvent(WalletEvent.PerpsUpdated)
        }
    }

    private fun applyCatalogue(langCode: String, catalogue: MApiPerpsCatalogue, fetchedAt: Long) {
        isAssetsCacheRead = true
        val version = langCode to fetchedAt
        if (fetchedAt == 0L || version != savedCatalogueVersion) {
            savedCatalogueVersion = version
            saveCatalogue(catalogue)
        } else {
            setCatalogue(catalogue)
        }
    }

    /** Older activity is available beyond what [fillsFor] returns. */
    fun hasMoreFills(accountId: String?): Boolean = accountId in fillsCursorsByAccountId

    /** Appends the next page of the account's activity; a failure retries on the next call. */
    fun loadMoreFills(accountId: String) {
        val cursor = fillsCursorsByAccountId[accountId] ?: return
        if (!WalletCore.isBridgeReady || accountId in moreFillsRequests) return
        val request = ApiMethod.Perps.GetActivityHistory(accountId, cursor)
        moreFillsRequests[accountId] = request
        WalletCore.call(request) { res, _ ->
            if (moreFillsRequests[accountId] !== request) return@call
            moreFillsRequests.remove(accountId)
            val history = res ?: return@call
            if (WGlobalStorage.getAccount(accountId) == null) return@call
            mergeFills(accountId, history.fills)
            if (history.hasActivity) hasActivityHistoryByAccountId[accountId] = true
            pagedFillsAccountIds += accountId
            if (history.nextCursor == null || history.nextCursor == cursor) {
                fillsCursorsByAccountId.remove(accountId)
            } else {
                fillsCursorsByAccountId[accountId] = history.nextCursor
            }
            WalletCore.notifyEvent(WalletEvent.PerpsUpdated)
        }
    }

    private fun mergeFills(accountId: String, fills: List<MApiPerpsFill>) {
        val merged = (fills + fillsFor(accountId).orEmpty())
            .distinctBy { it.identity }
            .sortedByDescending { it.time }
        fillsByAccountId[accountId] = merged
        WCacheStorage.setPerpsActivities(
            accountId,
            fillsAdapter.toJson(merged.take(CACHED_FILLS_COUNT))
        )
    }

    /** Reuses a request in flight like [loadSnapshot]. */
    fun loadFills(force: Boolean = false) {
        val account = AccountStore.activeAccount
        if (!WalletCore.isBridgeReady || account == null || perpsAddress(account) == null) {
            fillsRequest = null
            return
        }
        val accountId = account.accountId
        if (fillsRequest != null && fillsRequestAccountId == accountId) {
            if (force) isFillsReloadQueued = true
            return
        }
        val request = ApiMethod.Perps.GetActivityHistory(accountId)
        fillsRequest = request
        fillsRequestAccountId = accountId
        isFillsReloadQueued = false
        WalletCore.call(request) { res, _ ->
            if (fillsRequest !== request) return@call
            fillsRequest = null
            if (isFillsReloadQueued) loadFills()
            if (res == null) {
                failedFillsAccountIds.add(accountId)
                WalletCore.notifyEvent(WalletEvent.PerpsUpdated)
                return@call
            }
            if (WGlobalStorage.getAccount(accountId) == null) return@call
            failedFillsAccountIds.remove(accountId)
            // A page that doesn't reach the stored activity replaces it, so no gap stays unloadable
            if (res.nextCursor != null && !isContiguousWithStoredFills(accountId, res.fills)) {
                fillsByAccountId[accountId] = emptyList()
                pagedFillsAccountIds.remove(accountId)
                moreFillsRequests.remove(accountId)
            }
            mergeFills(accountId, res.fills)
            hasActivityHistoryByAccountId[accountId] =
                hasActivityHistoryByAccountId[accountId] == true || res.hasActivity
            // Older pages already loaded keep their own continuation
            if (accountId !in pagedFillsAccountIds) {
                res.nextCursor?.let { fillsCursorsByAccountId[accountId] = it }
                    ?: fillsCursorsByAccountId.remove(accountId)
            }
            WalletCore.notifyEvent(WalletEvent.PerpsUpdated)
        }
    }

    private fun isContiguousWithStoredFills(
        accountId: String,
        fills: List<MApiPerpsFill>
    ): Boolean {
        val stored = fillsFor(accountId).orEmpty()
        if (stored.isEmpty() || fills.isEmpty()) return true
        val storedIdentities = stored.mapTo(HashSet()) { it.identity }
        return fills.any { it.identity in storedIdentities }
    }

    /** Restores saved operations of the active account once per launch, before it can order again. */
    private fun reconcileOperationsOnce() {
        val accountId = AccountStore.activeAccountId ?: return
        if (!WalletCore.isBridgeReady || !reconciledAccountIds.add(accountId)) return
        reconcileOperations(accountId)
    }

    /** Copies the SDK's records, which can change without an execution reporting it. */
    private fun reconcileOperations(accountId: String) {
        if (!WalletCore.isBridgeReady) return
        for (operation in operationsFor(accountId)) {
            if (!operation.isUnresolved ||
                operation.id in executingOperationIds ||
                !reconcilingOperationIds.add(operation.id)
            ) {
                continue
            }
            WalletCore.call(ApiMethod.Perps.ReconcileOperation(accountId, operation)) { res, err ->
                reconcilingOperationIds.remove(operation.id)
                // The bridge reports an operation that carries an `error` as a failed call
                val reconciled = (res ?: err?.parsedResult as? MApiPerpsOperation)
                    ?.copy(reviewedQuote = operation.reviewedQuote)
                if (reconciled == null) {
                    reconciledAccountIds.remove(accountId)
                    return@call
                }
                if (reconciled.id != operation.id ||
                    reconciled.accountId != accountId ||
                    reconciled.assetId != operation.assetId ||
                    reconciled.kind != operation.kind
                ) {
                    return@call
                }
                if (reconciled != operation &&
                    operation.id !in executingOperationIds &&
                    operation(accountId, operation.id) == operation
                ) {
                    saveOperation(reconciled)
                }
            }
        }
    }

    private fun operationsFor(accountId: String): List<MApiPerpsOperation> {
        operationsByAccountId[accountId]?.let { return it }
        return (
            readCache(WCacheStorage.getPerpsOperations(accountId), operationsAdapter) {
                WCacheStorage.setPerpsOperations(accountId, null)
            } ?: emptyList()
            ).also { operationsByAccountId[accountId] = it }
    }

    private fun setOperations(accountId: String, operations: List<MApiPerpsOperation>) {
        operationsByAccountId[accountId] = operations
        WCacheStorage.setPerpsOperations(
            accountId,
            operations.takeIf { it.isNotEmpty() }?.let(operationsAdapter::toJson)
        )
    }

    // A new account can reuse the ID
    private fun forgetAccount(accountId: String) {
        snapshotsByAccountId.remove(accountId)
        fillsByAccountId.remove(accountId)
        operationsByAccountId.remove(accountId)
        reconciledAccountIds.remove(accountId)
        snapshotErrorsByAccountId.remove(accountId)
        failedFillsAccountIds.remove(accountId)
        fillsCursorsByAccountId.remove(accountId)
        pagedFillsAccountIds.remove(accountId)
        moreFillsRequests.remove(accountId)
        hasActivityHistoryByAccountId.remove(accountId)
        tradedAccountIds.remove(accountId)
        if (snapshotRequestAccountId == accountId) snapshotRequest = null
        if (fillsRequestAccountId == accountId) fillsRequest = null
    }

    override fun wipeData() {
        clearCache()
    }

    override fun clearCache() {
        catalogueWriteJob?.cancel()
        catalogueWriteJob = null
        savedCatalogueVersion = null
        isAssetsCacheRead = false
        setCatalogue(MApiPerpsCatalogue())
        snapshotsByAccountId.clear()
        fillsByAccountId.clear()
        operationsByAccountId.clear()
        reconciledAccountIds.clear()
        dismissedOperationIds.clear()
        snapshotRequest = null
        snapshotRequestAccountId = null
        isSnapshotReloadQueued = false
        marketRequest = null
        snapshotErrorsByAccountId.clear()
        fillsRequest = null
        fillsRequestAccountId = null
        isFillsReloadQueued = false
        fillsCursorsByAccountId.clear()
        pagedFillsAccountIds.clear()
        failedFillsAccountIds.clear()
        moreFillsRequests.clear()
        hasActivityHistoryByAccountId.clear()
        tradedAccountIds.clear()
    }

    private fun readAssetsCacheIfNeeded() {
        if (isAssetsCacheRead) return
        isAssetsCacheRead = true
        readCache(WCacheStorage.getPerpsAssets(), catalogueAdapter) {
            WCacheStorage.setPerpsAssets(null)
        }?.let(::setCatalogue)
    }

    private fun saveCatalogue(catalogue: MApiPerpsCatalogue) {
        setCatalogue(catalogue)
        catalogueWriteJob?.cancel()
        catalogueWriteJob = cacheScope.launch {
            val json = catalogueAdapter.toJson(catalogue)
            ensureActive()
            WCacheStorage.setPerpsAssets(json)
        }
    }

    private fun setCatalogue(catalogue: MApiPerpsCatalogue) {
        _assetsByCoin = catalogue.assets.associateBy { it.name }
        _assetsById = catalogue.assets.associateBy { it.id }
        _marketSections = catalogue.marketSections
        _onboarding = catalogue.onboarding
    }

    private fun <T> readCache(json: String?, adapter: JsonAdapter<T>, onInvalid: () -> Unit): T? {
        json ?: return null
        return try {
            adapter.fromJson(json)
        } catch (_: Exception) {
            onInvalid()
            null
        }
    }

    private const val POLL_INTERVAL_MS = 20_000L
    private const val CACHED_FILLS_COUNT = 50
    private const val SNAPSHOT_MAX_AGE_MS = 60_000L
    private const val SNAPSHOT_UNAVAILABLE_ERROR = "PerpsUnavailable"
    private const val SNAPSHOT_INCOMPLETE_ERROR = "PerpsIncompleteData"
    private const val PRICE_HISTORY_PREFIX = "perps:"
}
