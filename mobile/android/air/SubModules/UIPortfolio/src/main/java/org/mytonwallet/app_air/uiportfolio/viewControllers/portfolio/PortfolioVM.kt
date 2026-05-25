package org.mytonwallet.app_air.uiportfolio.viewControllers.portfolio

import androidx.core.graphics.toColorInt
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import org.mytonwallet.app_air.uiportfolio.viewControllers.portfolio.models.PortfolioBreakdownSlice
import org.mytonwallet.app_air.uiportfolio.viewControllers.portfolio.models.PortfolioChartKind
import org.mytonwallet.app_air.uiportfolio.viewControllers.portfolio.models.PortfolioHistoryRequest
import org.mytonwallet.app_air.uiportfolio.viewControllers.portfolio.models.PortfolioOverview
import org.mytonwallet.app_air.uiportfolio.viewControllers.portfolio.models.PortfolioUiState
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.async
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.supervisorScope
import kotlinx.coroutines.withContext
import org.mytonwallet.app_air.uicomponents.widgets.chart.extended.ChartData
import org.mytonwallet.app_air.uicomponents.widgets.chart.extended.ChartModel
import org.mytonwallet.app_air.uicomponents.widgets.chart.extended.SignedBarChartData
import org.mytonwallet.app_air.uicomponents.widgets.chart.extended.StackLinearChartData
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.models.MBaseCurrency
import org.mytonwallet.app_air.walletbasecontext.utils.MHistoryTimePeriod
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.api.fetchPortfolioNetWorthHistory
import org.mytonwallet.app_air.walletcore.api.fetchPortfolioPnlCumulativeHistory
import org.mytonwallet.app_air.walletcore.api.fetchPortfolioPnlHistory
import org.mytonwallet.app_air.walletcore.models.MAccount
import org.mytonwallet.app_air.walletcore.models.MToken
import org.mytonwallet.app_air.walletcore.models.blockchain.MBlockchain
import org.mytonwallet.app_air.walletcore.moshi.ApiHistoryList
import org.mytonwallet.app_air.walletcore.moshi.ApiPortfolioHistoryDataset
import org.mytonwallet.app_air.walletcore.moshi.ApiPortfolioHistoryResponse
import org.mytonwallet.app_air.walletcore.moshi.normalizedForPortfolioDisplay
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import org.mytonwallet.app_air.walletcore.stores.TokenStore
import kotlin.math.abs
import kotlin.math.pow
import kotlin.math.roundToLong

class PortfolioVM : ViewModel(), WalletCore.EventObserver {
    private val _stateFlow = MutableStateFlow<PortfolioUiState>(PortfolioUiState.Idle)
    val stateFlow: StateFlow<PortfolioUiState> = _stateFlow.asStateFlow()

    private var loadJob: Job? = null
    private val retryJobs = mutableMapOf<PortfolioChartKind, Job>()
    private var netWorthRetryJob: Job? = null
    private var historyRefreshJob: Job? = null
    private var historyRefreshAttempts = 0

    private val cachedResponses = mutableMapOf<PortfolioHistoryRequest, PortfolioChartResults>()

    var selectedPeriod: MHistoryTimePeriod = readPersistedPeriod()
        private set

    init {
        WalletCore.registerObserver(this)
        load()
    }

    fun selectPeriod(period: MHistoryTimePeriod) {
        if (selectedPeriod == period) return
        selectedPeriod = period
        persistPeriod(period)
        reload(
            account = AccountStore.activeAccount,
            baseCurrency = WalletCore.baseCurrency,
            resetHistoryRefreshAttempts = true,
            showLoadingState = true,
            loadingAnimated = true,
        )
    }

    private fun readPersistedPeriod(): MHistoryTimePeriod {
        val accountId = AccountStore.activeAccount?.accountId ?: return DEFAULT_PORTFOLIO_PERIOD
        val stored =
            WGlobalStorage.currentPortfolioPeriod(accountId) ?: return DEFAULT_PORTFOLIO_PERIOD
        return MHistoryTimePeriod.entries.find { it.value == stored } ?: DEFAULT_PORTFOLIO_PERIOD
    }

    private fun persistPeriod(period: MHistoryTimePeriod) {
        val accountId = AccountStore.activeAccount?.accountId ?: return
        WGlobalStorage.setCurrentPortfolioPeriod(accountId, period.value)
    }

    fun load(
        account: MAccount? = AccountStore.activeAccount,
        baseCurrency: MBaseCurrency = WalletCore.baseCurrency,
    ) {
        reload(
            account = account,
            baseCurrency = baseCurrency,
            resetHistoryRefreshAttempts = true,
            showLoadingState = true,
        )
    }

    private fun refreshPreservingContent(
        account: MAccount? = AccountStore.activeAccount,
        baseCurrency: MBaseCurrency = WalletCore.baseCurrency,
    ) {
        reload(
            account = account,
            baseCurrency = baseCurrency,
            resetHistoryRefreshAttempts = true,
            showLoadingState = false,
        )
    }

    private fun reload(
        account: MAccount?,
        baseCurrency: MBaseCurrency,
        resetHistoryRefreshAttempts: Boolean,
        showLoadingState: Boolean,
        loadingAnimated: Boolean = false,
    ) {
        val request = buildRequest(account, baseCurrency)
        if (request == null) {
            loadJob?.cancel()
            historyRefreshJob?.cancel()
            historyRefreshAttempts = 0
            _stateFlow.value = PortfolioUiState.Idle
            return
        }

        load(
            request = request,
            resetHistoryRefreshAttempts = resetHistoryRefreshAttempts,
            showLoadingState = showLoadingState,
            loadingAnimated = loadingAnimated,
        )
    }

    private fun load(
        request: PortfolioHistoryRequest,
        resetHistoryRefreshAttempts: Boolean,
        showLoadingState: Boolean,
        loadingAnimated: Boolean = false,
    ) {
        loadJob?.cancel()
        historyRefreshJob?.cancel()
        cancelRetryJobs()
        if (resetHistoryRefreshAttempts) {
            historyRefreshAttempts = 0
        }

        val cacheHit = showLoadingState && cachedResponses[request]?.isComplete == true
        loadJob = viewModelScope.launch {
            if (showLoadingState && !cacheHit) {
                _stateFlow.value = PortfolioUiState.Loading(request, animated = loadingAnimated)
            }
            try {
                val results = fetchChartData(request, useCache = showLoadingState)
                _stateFlow.value = deriveLoaded(request, results, silent = !showLoadingState)
                results.netWorth?.let { scheduleHistoryRefreshIfNeeded(request, it) }
                scheduleNetWorthAutoRetry(request, failed = results.netWorthFailed)
            } catch (e: CancellationException) {
                throw e
            } catch (_: Throwable) {
                if (showLoadingState || _stateFlow.value !is PortfolioUiState.Loaded) {
                    _stateFlow.value = deriveLoaded(
                        request,
                        PortfolioChartResults.allFailed(),
                        silent = !showLoadingState,
                    )
                }
                scheduleNetWorthAutoRetry(request, failed = true)
            }
        }
    }

    // Net worth is mandatory (the value/distribution/overview/breakdown all derive from it), so a
    // failure has no Try Again button — the whole screen stays in loading (PnL charts included) and
    // we silently re-fetch every 5s. Each sweep retries every still-failed chart, so the PnL charts
    // recover together with net worth. The loop is cancelled by any (re)load (period/account/
    // currency change) or when the view controller is destroyed.
    private fun scheduleNetWorthAutoRetry(request: PortfolioHistoryRequest, failed: Boolean) {
        if (!failed) {
            netWorthRetryJob?.cancel()
            netWorthRetryJob = null
            return
        }
        if (netWorthRetryJob?.isActive == true) return
        netWorthRetryJob = viewModelScope.launch {
            while (true) {
                delay(NET_WORTH_AUTO_RETRY_DELAY_MS)
                val before = cachedResponses[request] ?: PortfolioChartResults.allFailed()
                val swept = supervisorScope {
                    val nw = async {
                        if (before.netWorthFailed) runCatchingFetch {
                            fetchSingle(
                                request,
                                PortfolioChartKind.NET_WORTH
                            )
                        } else before.netWorth
                    }
                    val pc = async {
                        if (before.pnlCumulativeFailed) runCatchingFetch {
                            fetchSingle(
                                request,
                                PortfolioChartKind.TOTAL_PNL
                            )
                        } else before.pnlCumulative
                    }
                    val pd = async {
                        if (before.pnlDailyFailed) runCatchingFetch {
                            fetchSingle(
                                request,
                                PortfolioChartKind.DAILY_PNL
                            )
                        } else before.pnlDaily
                    }
                    val nwR = nw.await()
                    val pcR = pc.await()
                    val pdR = pd.await()
                    PortfolioChartResults(
                        netWorth = nwR,
                        pnlCumulative = pcR,
                        pnlDaily = pdR,
                        netWorthFailed = nwR == null,
                        pnlCumulativeFailed = pcR == null,
                        pnlDailyFailed = pdR == null,
                    )
                }
                cachedResponses[request] = swept
                // Keep sweeping until net worth recovers; once it does, stop and show the result
                // (any PnL still failed then falls back to its own Try Again button).
                if (!swept.netWorthFailed) {
                    netWorthRetryJob = null
                    _stateFlow.value = deriveLoaded(request, swept, silent = true)
                    break
                }
            }
        }
    }

    fun retry(kind: PortfolioChartKind) {
        val request = buildRequest(AccountStore.activeAccount, WalletCore.baseCurrency) ?: return
        // Per-chart jobs so retrying two charts concurrently doesn't cancel each other; only a
        // repeat tap on the same chart supersedes its own in-flight retry.
        retryJobs[kind]?.cancel()
        retryJobs[kind] = viewModelScope.launch {
            val refreshed = try {
                fetchSingle(request, kind)
            } catch (e: CancellationException) {
                throw e
            } catch (_: Throwable) {
                null
            }
            // Re-read the cache AFTER the fetch and merge only this chart's field, so a sibling
            // retry that finished meanwhile is preserved (no lost update). Both the cache write
            // and the emit below run without suspending, on the single Main dispatcher.
            val cached = cachedResponses[request] ?: PortfolioChartResults.allFailed()
            val merged = when (kind) {
                PortfolioChartKind.NET_WORTH ->
                    cached.copy(netWorth = refreshed, netWorthFailed = refreshed == null)

                PortfolioChartKind.TOTAL_PNL ->
                    cached.copy(pnlCumulative = refreshed, pnlCumulativeFailed = refreshed == null)

                PortfolioChartKind.DAILY_PNL ->
                    cached.copy(pnlDaily = refreshed, pnlDailyFailed = refreshed == null)
            }
            cachedResponses[request] = merged
            retryJobs.remove(kind)
            _stateFlow.value = deriveLoaded(request, merged, silent = true)
        }
    }

    private suspend fun deriveLoaded(
        request: PortfolioHistoryRequest,
        results: PortfolioChartResults,
        silent: Boolean,
    ): PortfolioUiState.Loaded = withContext(Dispatchers.Default) {
        val normalized = results.netWorth?.normalizedForPortfolioDisplay()
        val summaries = normalized?.activeDatasetSummaries() ?: emptyList()
        PortfolioUiState.Loaded(
            request = request,
            chartData = normalized?.toStackChartData(request.baseCurrency),
            totalPnlChartData = results.pnlCumulative.toSignedLineChartData(request.baseCurrency),
            dailyPnlChartData = results.pnlDaily.toSignedBarChartData(request.baseCurrency),
            overview = normalized?.toOverview(),
            assetBreakdown = summaries.toAssetBreakdown(),
            chainBreakdown = summaries.toChainBreakdown(),
            netWorthFailed = results.netWorthFailed,
            totalPnlFailed = results.pnlCumulativeFailed,
            dailyPnlFailed = results.pnlDailyFailed,
            silent = silent,
        )
    }

    override fun onWalletEvent(walletEvent: WalletEvent) {
        when (walletEvent) {
            is WalletEvent.AccountChanged,
            is WalletEvent.AccountChangedInApp -> {
                cachedResponses.clear()
                selectedPeriod = readPersistedPeriod()
                load()
            }

            WalletEvent.BaseCurrencyChanged -> {
                cachedResponses.clear()
                load()
            }

            is WalletEvent.BalanceChanged -> {
                cachedResponses.clear()
                refreshPreservingContent()
            }

            is WalletEvent.ByChainUpdated -> {
                if (walletEvent.accountId == AccountStore.activeAccount?.accountId) {
                    cachedResponses.clear()
                    refreshPreservingContent()
                }
            }

            else -> {}
        }
    }

    fun onDestroy() {
        loadJob?.cancel()
        historyRefreshJob?.cancel()
        cancelRetryJobs()
        WalletCore.unregisterObserver(this)
    }

    // A full (re)load supersedes any in-flight per-chart retries; without this an orphaned
    // retry could write stale data back into the cache/state after the load — including a
    // previous account's data, since account/currency changes clear the cache then reload.
    private fun cancelRetryJobs() {
        retryJobs.values.forEach { it.cancel() }
        retryJobs.clear()
        netWorthRetryJob?.cancel()
        netWorthRetryJob = null
    }

    private fun buildRequest(
        account: MAccount?,
        baseCurrency: MBaseCurrency,
    ): PortfolioHistoryRequest? {
        if (account == null || !account.isMainnet) {
            return null
        }

        val wallets = account.byChain
            .mapNotNull { (chain, wallet) ->
                wallet.address.takeIf { it.isNotEmpty() }?.let { "$chain:$it" }
            }.takeIf { it.isNotEmpty() } ?: return null

        return PortfolioHistoryRequest(
            wallets = wallets,
            baseCurrency = baseCurrency,
            period = selectedPeriod,
        )
    }

    // Each chart fetches independently: a failure (e.g. 503) on one marks only that chart
    // failed (shown as an inline error + Try Again), leaving the others intact.
    private suspend fun fetchChartData(
        request: PortfolioHistoryRequest,
        useCache: Boolean,
    ): PortfolioChartResults {
        if (useCache) {
            cachedResponses[request]?.takeIf { it.isComplete }?.let { return it }
        }
        val results = supervisorScope {
            val netWorth =
                async { runCatchingFetch { fetchSingle(request, PortfolioChartKind.NET_WORTH) } }
            val pnlCumulative =
                async { runCatchingFetch { fetchSingle(request, PortfolioChartKind.TOTAL_PNL) } }
            val pnlDaily =
                async { runCatchingFetch { fetchSingle(request, PortfolioChartKind.DAILY_PNL) } }
            val nw = netWorth.await()
            val pc = pnlCumulative.await()
            val pd = pnlDaily.await()
            PortfolioChartResults(
                netWorth = nw,
                pnlCumulative = pc,
                pnlDaily = pd,
                netWorthFailed = nw == null,
                pnlCumulativeFailed = pc == null,
                pnlDailyFailed = pd == null,
            )
        }
        cachedResponses[request] = results
        return results
    }

    private suspend fun fetchSingle(
        request: PortfolioHistoryRequest,
        kind: PortfolioChartKind,
    ): ApiPortfolioHistoryResponse = when (kind) {
        PortfolioChartKind.NET_WORTH -> WalletCore.fetchPortfolioNetWorthHistory(
            request.wallets, request.baseCurrency, request.period,
        )

        PortfolioChartKind.TOTAL_PNL -> WalletCore.fetchPortfolioPnlCumulativeHistory(
            request.wallets, request.baseCurrency, request.period,
        )

        PortfolioChartKind.DAILY_PNL -> WalletCore.fetchPortfolioPnlHistory(
            request.wallets, request.baseCurrency, request.period,
        )
    }

    private suspend fun runCatchingFetch(
        block: suspend () -> ApiPortfolioHistoryResponse,
    ): ApiPortfolioHistoryResponse? {
        return try {
            block()
        } catch (e: CancellationException) {
            throw e
        } catch (_: Throwable) {
            null
        }
    }

    private fun ApiPortfolioHistoryResponse.toStackChartData(
        baseCurrency: MBaseCurrency,
    ): StackLinearChartData? {
        datasets?.let { return datasetsToStackChartData(it, baseCurrency) }
        points?.let { return historyPointsToStackChartData(it, baseCurrency) }
        return null
    }

    private fun ApiPortfolioHistoryResponse.toOverview(): PortfolioOverview? {
        val datasetTotals = datasets?.let { datasetsTotalsByTimestamp(it) }
        val pointsList = points
        val totals: List<Pair<Long, Double>> = when {
            !datasetTotals.isNullOrEmpty() -> datasetTotals
            !pointsList.isNullOrEmpty() -> pointsList.toHistoryPoints()
                .sortedBy { it.timestamp }
                .map { it.timestamp to it.value }

            else -> return null
        }
        if (totals.isEmpty()) return null

        val first = totals.first()
        val last = totals.last()
        val baseline = totals.firstOrNull { it.second > 0.0 } ?: first
        val netAbs = last.second - first.second
        val netPct = if (baseline.second > 0.0) {
            (last.second - baseline.second) / baseline.second
        } else null

        return PortfolioOverview(
            totalValue = last.second,
            netChangeAbs = netAbs,
            netChangePct = netPct,
            startTimestampMs = first.first.toChartTimestampMs(),
            endTimestampMs = last.first.toChartTimestampMs(),
        )
    }

    private fun ApiPortfolioHistoryResponse.activeDatasetSummaries(): List<PortfolioDatasetSummary> {
        val datasets = datasets ?: return emptyList()
        return datasets.map { it.toSummary() }
            .filter { it.impact > 0.0 || it.hasPositiveValues }
            .sortedWith(
                compareByDescending<PortfolioDatasetSummary> { it.impact }
                    .thenByDescending { it.latestValue }
            )
    }

    private fun List<PortfolioDatasetSummary>.toAssetBreakdown(): List<PortfolioBreakdownSlice> {
        val total = sumOf { it.latestValue.coerceAtLeast(0.0) }
        if (total <= 0.0) return emptyList()
        val tokens = TokenStore.tokens
        val slices = mapIndexed { index, summary ->
            val tokenColor = summary.tokenColor(tokens)
            PortfolioBreakdownSlice(
                id = summary.dataset.contractAddress.takeIf { it.isNotBlank() }
                    ?: "asset_${summary.dataset.assetId}_$index",
                label = summary.dataset.symbol,
                color = (summary.dataset.color ?: tokenColor)?.toChartColor(index)
                    ?: fallbackChartColors[index % fallbackChartColors.size],
                ratio = summary.latestValue.coerceAtLeast(0.0) / total,
            )
        }
        return collapseToMax(slices)
    }

    private fun PortfolioDatasetSummary.tokenColor(tokens: Map<String, MToken>): String? {
        val contract = dataset.contractAddress.takeIf { it.isNotBlank() }
        if (contract != null) {
            tokens.values.firstOrNull { it.tokenAddress == contract }?.color?.let { return it }
        }
        val symbol = dataset.symbol.takeIf { it.isNotBlank() } ?: return null
        return tokens.values.firstOrNull { it.symbol.equals(symbol, ignoreCase = true) }?.color
    }

    private fun List<PortfolioDatasetSummary>.toChainBreakdown(): List<PortfolioBreakdownSlice> {
        if (isEmpty()) return emptyList()
        val tokens = TokenStore.tokens
        val totals = LinkedHashMap<String, Double>()
        for (summary in this) {
            val chainKey = summary.resolveChain(tokens) ?: UNKNOWN_CHAIN
            totals[chainKey] = (totals[chainKey] ?: 0.0) + summary.latestValue
        }
        val total = totals.values.sum()
        if (total <= 0.0) return emptyList()
        val slices = totals.entries
            .sortedByDescending { it.value }
            .mapIndexed { index, (chainKey, value) ->
                PortfolioBreakdownSlice(
                    id = "chain_$chainKey",
                    label = chainDisplayName(chainKey),
                    color = chainColor(chainKey, index),
                    ratio = value / total,
                )
            }
        return collapseToMax(slices)
    }

    private fun chainColor(chainKey: String, index: Int): Int {
        val nativeSlug = MBlockchain.valueOfOrNull(chainKey)?.nativeSlug
        val nativeColor = nativeSlug?.let { TokenStore.getToken(it)?.color }
        return nativeColor?.toChartColor(index)
            ?: fallbackChartColors[index % fallbackChartColors.size]
    }

    private fun collapseToMax(slices: List<PortfolioBreakdownSlice>): List<PortfolioBreakdownSlice> {
        if (slices.size <= BREAKDOWN_MAX_SLICES) return slices
        val kept = slices.take(BREAKDOWN_MAX_SLICES - 1)
        val rest = slices.drop(BREAKDOWN_MAX_SLICES - 1)
        val othersRatio = rest.sumOf { it.ratio }
        return kept + PortfolioBreakdownSlice(
            id = "_others",
            label = LocaleController.getString("Other"),
            color = OTHERS_COLOR,
            ratio = othersRatio,
        )
    }

    private fun PortfolioDatasetSummary.resolveChain(tokens: Map<String, MToken>): String? {
        val contract = dataset.contractAddress.takeIf { it.isNotBlank() }
        if (contract != null) {
            tokens.values.firstOrNull { it.tokenAddress == contract }
                ?.chain?.takeIf { it.isNotBlank() }
                ?.let { return it }
        }
        val symbol = dataset.symbol.takeIf { it.isNotBlank() } ?: return null
        return tokens.values.firstOrNull { it.symbol.equals(symbol, ignoreCase = true) }
            ?.chain?.takeIf { it.isNotBlank() }
    }

    private fun chainDisplayName(chainKey: String): String {
        if (chainKey == UNKNOWN_CHAIN) return LocaleController.getString("Other")
        return MBlockchain.valueOfOrNull(chainKey)?.displayName
            ?: chainKey.replaceFirstChar { it.uppercase() }
    }

    private data class PortfolioChartResults(
        val netWorth: ApiPortfolioHistoryResponse?,
        val pnlCumulative: ApiPortfolioHistoryResponse?,
        val pnlDaily: ApiPortfolioHistoryResponse?,
        val netWorthFailed: Boolean,
        val pnlCumulativeFailed: Boolean,
        val pnlDailyFailed: Boolean,
    ) {
        val isComplete: Boolean
            get() = !netWorthFailed && !pnlCumulativeFailed && !pnlDailyFailed

        companion object {
            fun allFailed() = PortfolioChartResults(
                netWorth = null,
                pnlCumulative = null,
                pnlDaily = null,
                netWorthFailed = true,
                pnlCumulativeFailed = true,
                pnlDailyFailed = true,
            )
        }
    }

    private fun datasetsTotalsByTimestamp(
        datasets: List<ApiPortfolioHistoryDataset>,
    ): List<Pair<Long, Double>> {
        val byTs = sortedMapOf<Long, Double>()
        for (dataset in datasets) {
            for (point in dataset.points) {
                if (point.size < 2) continue
                val timestamp = point[0] ?: continue
                val value = point[1] ?: continue
                val ts = timestamp.toLong()
                byTs[ts] = (byTs[ts] ?: 0.0) + value
            }
        }
        return byTs.map { it.key to it.value }
    }

    private fun historyPointsToStackChartData(
        points: ApiHistoryList,
        baseCurrency: MBaseCurrency,
    ): StackLinearChartData? {
        val sortedPoints = points.toHistoryPoints().sortedBy { it.timestamp }
        if (sortedPoints.isEmpty()) {
            return null
        }

        return buildStackLinearChartData(
            timestamps = sortedPoints.map { it.timestamp.toChartTimestampMs() },
            series = listOf(
                ChartSeriesInput(
                    id = "portfolio_total",
                    name = LocaleController.getString("Portfolio"),
                    color = fallbackChartColors[0],
                    values = sortedPoints.map { it.value.toChartValue(baseCurrency.decimalsCount) },
                )
            )
        )
    }

    private fun datasetsToStackChartData(
        datasets: List<ApiPortfolioHistoryDataset>,
        baseCurrency: MBaseCurrency,
    ): StackLinearChartData? {
        val activeDatasets = datasets.map { it.toSummary() }
            .filter { it.impact > 0.0 || it.hasPositiveValues }
            .sortedWith(
                compareByDescending<PortfolioDatasetSummary> { it.impact }
                    .thenByDescending { it.latestValue }
            )

        val timestamps = activeDatasets.flatMap { dataset -> dataset.points.map { it.timestamp } }
            .distinct()
            .sorted()
        if (timestamps.isEmpty()) {
            return null
        }

        return buildStackLinearChartData(
            timestamps = timestamps.map { it.toChartTimestampMs() },
            series = activeDatasets.mapIndexed { index, dataset ->
                val valuesByTimestamp = dataset.points.associate { it.timestamp to it.value }
                ChartSeriesInput(
                    id = dataset.dataset.contractAddress.takeIf { it.isNotBlank() }
                        ?: "asset_${dataset.dataset.assetId}_$index",
                    name = dataset.dataset.symbol,
                    color = dataset.dataset.color?.toChartColor(index)
                        ?: fallbackChartColors[index % fallbackChartColors.size],
                    values = timestamps.map {
                        (valuesByTimestamp[it] ?: 0.0).toChartValue(baseCurrency.decimalsCount)
                    },
                )
            }
        )
    }

    private fun ApiHistoryList.toHistoryPoints(): List<PortfolioHistoryPoint> {
        return buildList {
            for (point in this@toHistoryPoints) {
                if (point.size < 2) {
                    continue
                }
                val timestamp = point[0] ?: continue
                val value = point[1] ?: continue
                add(PortfolioHistoryPoint(timestamp = timestamp.toLong(), value = value))
            }
        }
    }

    private fun ApiPortfolioHistoryDataset.toSummary(): PortfolioDatasetSummary {
        val historyPoints = points.toHistoryPoints()
        return PortfolioDatasetSummary(
            dataset = this,
            points = historyPoints,
            latestValue = historyPoints.lastOrNull { it.value > 0.0 }?.value ?: 0.0,
            impact = impact ?: 0.0,
            hasPositiveValues = historyPoints.any { it.value > 0.0 },
        )
    }

    private fun scheduleHistoryRefreshIfNeeded(
        request: PortfolioHistoryRequest,
        response: ApiPortfolioHistoryResponse,
    ) {
        historyRefreshJob?.cancel()

        if (response.historyScanCursor == null || historyRefreshAttempts >= MAX_HISTORY_REFRESH_ATTEMPTS) {
            return
        }

        historyRefreshAttempts += 1
        historyRefreshJob = viewModelScope.launch {
            delay(HISTORY_REFRESH_DELAY_MS)
            historyRefreshJob = null
            load(
                request = request,
                resetHistoryRefreshAttempts = false,
                showLoadingState = false,
            )
        }
    }

    private fun buildStackLinearChartData(
        timestamps: List<Long>,
        series: List<ChartSeriesInput>,
    ): StackLinearChartData? {
        if (timestamps.isEmpty() || series.isEmpty()) {
            return null
        }
        return try {
            StackLinearChartData(buildChartModel(timestamps, series), false)
        } catch (_: Exception) {
            null
        }
    }

    private fun buildChartModel(
        timestamps: List<Long>,
        series: List<ChartSeriesInput>,
    ): ChartModel {
        return ChartModel(
            x = timestamps.toLongArray(),
            lines = series.map { item ->
                ChartModel.Line(
                    id = item.id,
                    name = item.name,
                    y = item.values.toLongArray(),
                    color = item.color,
                )
            }
        )
    }

    private fun Double.toChartValue(decimals: Int): Long {
        if (!isFinite()) return 0L
        val normalizedValue = coerceAtLeast(0.0)
        val scale = 10.0.pow(decimals.toDouble())
        val scaledValue = normalizedValue * scale
        return when {
            !scaledValue.isFinite() -> Long.MAX_VALUE
            scaledValue <= 0.0 -> 0L
            scaledValue >= Long.MAX_VALUE.toDouble() -> Long.MAX_VALUE
            else -> scaledValue.roundToLong()
        }
    }

    private fun Double.toSignedChartValue(decimals: Int): Long {
        if (!isFinite()) return 0L
        val scale = 10.0.pow(decimals.toDouble())
        val scaledValue = this * scale
        return when {
            !scaledValue.isFinite() -> if (scaledValue < 0) Long.MIN_VALUE else Long.MAX_VALUE
            scaledValue >= Long.MAX_VALUE.toDouble() -> Long.MAX_VALUE
            scaledValue <= Long.MIN_VALUE.toDouble() -> Long.MIN_VALUE
            else -> scaledValue.roundToLong()
        }
    }

    private fun buildSignedSeries(
        response: ApiPortfolioHistoryResponse,
        baseCurrency: MBaseCurrency,
    ): Pair<List<Long>, List<ChartSeriesInput>>? {
        val datasets = response.datasets ?: return null
        val summaries = datasets.map { it.toSummary() }
            .filter { it.points.isNotEmpty() }
            .sortedWith(
                compareByDescending<PortfolioDatasetSummary> { abs(it.impact) }
                    .thenByDescending { abs(it.latestValue) }
            )
        if (summaries.isEmpty()) return null

        val timestamps = summaries.flatMap { dataset -> dataset.points.map { it.timestamp } }
            .distinct()
            .sorted()
        if (timestamps.isEmpty()) return null

        val rollup = summaries.size > MAX_PNL_SERIES
        val selectedCount = if (rollup) MAX_PNL_SERIES - 1 else summaries.size
        val selected = summaries.take(selectedCount)
        val remaining = summaries.drop(selectedCount)

        val series = selected.mapIndexed { index, dataset ->
            val valuesByTimestamp = dataset.points.associate { it.timestamp to it.value }
            ChartSeriesInput(
                id = dataset.dataset.contractAddress.takeIf { it.isNotBlank() }
                    ?: "asset_${dataset.dataset.assetId}_$index",
                name = dataset.dataset.symbol.takeIf { it.isNotBlank() }
                    ?: dataset.dataset.contractAddress.takeIf { it.isNotBlank() }
                    ?: LocaleController.getString("Asset"),
                color = dataset.dataset.color?.toChartColor(index)
                    ?: fallbackChartColors[index % fallbackChartColors.size],
                values = timestamps.map {
                    (valuesByTimestamp[it] ?: 0.0).toSignedChartValue(baseCurrency.decimalsCount)
                },
            )
        }.toMutableList()

        if (rollup && remaining.isNotEmpty()) {
            val remainingMaps =
                remaining.map { it.points.associate { p -> p.timestamp to p.value } }
            val otherValues = timestamps.map { ts ->
                remainingMaps.sumOf { it[ts] ?: 0.0 }.toSignedChartValue(baseCurrency.decimalsCount)
            }
            if (otherValues.any { it != 0L }) {
                series.add(
                    ChartSeriesInput(
                        id = "_other_pnl",
                        name = LocaleController.getString("Other"),
                        color = fallbackChartColors[series.size % fallbackChartColors.size],
                        values = otherValues,
                    )
                )
            }
        }

        if (series.isEmpty()) return null
        return timestamps.map { it.toChartTimestampMs() } to series
    }

    private fun ApiPortfolioHistoryResponse?.toSignedLineChartData(
        baseCurrency: MBaseCurrency,
    ): ChartData? {
        if (this == null) return null
        val (timestamps, series) = buildSignedSeries(this, baseCurrency) ?: return null
        return try {
            ChartData(buildChartModel(timestamps, series))
        } catch (_: Exception) {
            null
        }
    }

    private fun ApiPortfolioHistoryResponse?.toSignedBarChartData(
        baseCurrency: MBaseCurrency,
    ): SignedBarChartData? {
        if (this == null) return null
        val (timestamps, series) = buildSignedSeries(this, baseCurrency) ?: return null
        return try {
            SignedBarChartData(buildChartModel(timestamps, series))
        } catch (_: Exception) {
            null
        }
    }

    private fun Long.toChartTimestampMs(): Long {
        return if (this < UNIX_TIMESTAMP_MS_THRESHOLD) this * 1000 else this
    }

    private fun String.toChartColor(index: Int): Int {
        return try {
            val trimmed = trim()
            val normalizedColor = if (trimmed.startsWith("#")) trimmed else "#$trimmed"
            normalizedColor.toColorInt()
        } catch (_: IllegalArgumentException) {
            fallbackChartColors[index % fallbackChartColors.size]
        }
    }

    private data class PortfolioHistoryPoint(
        val timestamp: Long,
        val value: Double,
    )

    private data class PortfolioDatasetSummary(
        val dataset: ApiPortfolioHistoryDataset,
        val points: List<PortfolioHistoryPoint>,
        val latestValue: Double,
        val impact: Double,
        val hasPositiveValues: Boolean,
    )

    private data class ChartSeriesInput(
        val id: String,
        val name: String,
        val color: Int,
        val values: List<Long>,
    )

    companion object {
        private const val UNIX_TIMESTAMP_MS_THRESHOLD = 10_000_000_000L
        private const val MAX_HISTORY_REFRESH_ATTEMPTS = 6
        private const val HISTORY_REFRESH_DELAY_MS = 8_000L
        private const val NET_WORTH_AUTO_RETRY_DELAY_MS = 5_000L
        private const val UNKNOWN_CHAIN = "_unknown"
        private const val BREAKDOWN_MAX_SLICES = 4
        private const val MAX_PNL_SERIES = 8
        private val OTHERS_COLOR = 0xFF8E8E93.toInt()
        private val DEFAULT_PORTFOLIO_PERIOD = MHistoryTimePeriod.THREE_MONTHS

        private val fallbackChartColors = intArrayOf(
            0xFF3497ED.toInt(),
            0xFF2373DB.toInt(),
            0xFF9ED448.toInt(),
            0xFF5FB641.toInt(),
            0xFFF5BD25.toInt(),
            0xFFF79E39.toInt(),
            0xFFE65850.toInt(),
            0xFF5D5CDC.toInt(),
        )
    }
}
