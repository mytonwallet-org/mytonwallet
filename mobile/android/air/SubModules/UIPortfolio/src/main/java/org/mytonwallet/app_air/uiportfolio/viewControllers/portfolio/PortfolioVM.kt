package org.mytonwallet.app_air.uiportfolio.viewControllers.portfolio

import androidx.core.graphics.toColorInt
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import org.mytonwallet.app_air.uiportfolio.viewControllers.portfolio.models.PortfolioBreakdownSlice
import org.mytonwallet.app_air.uiportfolio.viewControllers.portfolio.models.PortfolioHistoryRequest
import org.mytonwallet.app_air.uiportfolio.viewControllers.portfolio.models.PortfolioOverview
import org.mytonwallet.app_air.uiportfolio.viewControllers.portfolio.models.PortfolioUiState
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.mytonwallet.app_air.uicomponents.widgets.chart.extended.ChartModel
import org.mytonwallet.app_air.uicomponents.widgets.chart.extended.StackLinearChartData
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.models.MBaseCurrency
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.api.fetchPortfolioNetWorthHistory
import org.mytonwallet.app_air.walletcore.models.MAccount
import org.mytonwallet.app_air.walletcore.models.MToken
import org.mytonwallet.app_air.walletcore.models.blockchain.MBlockchain
import org.mytonwallet.app_air.walletcore.moshi.ApiHistoryList
import org.mytonwallet.app_air.walletcore.moshi.ApiPortfolioHistoryDataset
import org.mytonwallet.app_air.walletcore.moshi.ApiPortfolioHistoryResponse
import org.mytonwallet.app_air.walletcore.moshi.normalizedForPortfolioDisplay
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import org.mytonwallet.app_air.walletcore.stores.TokenStore
import kotlin.math.pow
import kotlin.math.roundToLong

class PortfolioVM : ViewModel(), WalletCore.EventObserver {
    private val _stateFlow = MutableStateFlow<PortfolioUiState>(PortfolioUiState.Idle)
    val stateFlow: StateFlow<PortfolioUiState> = _stateFlow.asStateFlow()

    private var loadJob: Job? = null
    private var historyRefreshJob: Job? = null
    private var historyRefreshAttempts = 0

    init {
        WalletCore.registerObserver(this)
        load()
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
    ) {
        val request = buildRequest(account, baseCurrency)
        if (request == null) {
            loadJob?.cancel()
            historyRefreshJob?.cancel()
            historyRefreshAttempts = 0
            _stateFlow.value = PortfolioUiState.Error
            return
        }

        load(
            request = request,
            resetHistoryRefreshAttempts = resetHistoryRefreshAttempts,
            showLoadingState = showLoadingState || _stateFlow.value !is PortfolioUiState.Loaded,
        )
    }

    fun load(request: PortfolioHistoryRequest) {
        load(
            request = request,
            resetHistoryRefreshAttempts = true,
            showLoadingState = true,
        )
    }

    private fun load(
        request: PortfolioHistoryRequest,
        resetHistoryRefreshAttempts: Boolean,
        showLoadingState: Boolean,
    ) {
        loadJob?.cancel()
        historyRefreshJob?.cancel()
        if (resetHistoryRefreshAttempts) {
            historyRefreshAttempts = 0
        }

        loadJob = viewModelScope.launch {
            if (showLoadingState) {
                _stateFlow.value = PortfolioUiState.Loading(request)
            }
            try {
                val rawData = fetchChartData(request)
                val derived = withContext(Dispatchers.Default) {
                    val normalized = rawData.normalizedForPortfolioDisplay()
                    val summaries = normalized.activeDatasetSummaries()
                    DerivedPortfolio(
                        chartData = normalized.toStackChartData(request.baseCurrency),
                        overview = normalized.toOverview(),
                        assetBreakdown = summaries.toAssetBreakdown(),
                        chainBreakdown = summaries.toChainBreakdown(),
                    )
                }
                _stateFlow.value = PortfolioUiState.Loaded(
                    request = request,
                    chartData = derived.chartData,
                    overview = derived.overview,
                    assetBreakdown = derived.assetBreakdown,
                    chainBreakdown = derived.chainBreakdown,
                )
                scheduleHistoryRefreshIfNeeded(request, rawData)
            } catch (e: CancellationException) {
                throw e
            } catch (_: Throwable) {
                if (showLoadingState || _stateFlow.value !is PortfolioUiState.Loaded) {
                    _stateFlow.value = PortfolioUiState.Error
                }
            }
        }
    }

    override fun onWalletEvent(walletEvent: WalletEvent) {
        when (walletEvent) {
            is WalletEvent.AccountChanged,
            is WalletEvent.AccountChangedInApp,
            WalletEvent.BaseCurrencyChanged -> load()

            is WalletEvent.BalanceChanged -> refreshPreservingContent()

            is WalletEvent.ByChainUpdated -> {
                if (walletEvent.accountId == AccountStore.activeAccount?.accountId) {
                    refreshPreservingContent()
                }
            }

            else -> {}
        }
    }

    fun onDestroy() {
        loadJob?.cancel()
        historyRefreshJob?.cancel()
        WalletCore.unregisterObserver(this)
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
                val blockchain = MBlockchain.valueOfOrNull(chain) ?: return@mapNotNull null
                if (!blockchain.isNetWorthSupported) {
                    return@mapNotNull null
                }

                wallet.address.takeIf { it.isNotEmpty() }?.let { "$chain:$it" }
            }.takeIf { it.isNotEmpty() } ?: return null

        return PortfolioHistoryRequest(
            wallets = wallets,
            baseCurrency = baseCurrency,
        )
    }

    private suspend fun fetchChartData(request: PortfolioHistoryRequest): ApiPortfolioHistoryResponse {
        return WalletCore.fetchPortfolioNetWorthHistory(
            wallets = request.wallets,
            baseCurrency = request.baseCurrency,
        )
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
            .filter { it.latestValue > 0.0 }
            .sortedWith(
                compareByDescending<PortfolioDatasetSummary> { it.impact }
                    .thenByDescending { it.latestValue }
            )
    }

    private fun List<PortfolioDatasetSummary>.toAssetBreakdown(): List<PortfolioBreakdownSlice> {
        val total = sumOf { it.latestValue }
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
                ratio = summary.latestValue / total,
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
        if (chainKey == UNKNOWN_CHAIN) return LocaleController.getString("Others")
        return MBlockchain.valueOfOrNull(chainKey)?.displayName
            ?: chainKey.replaceFirstChar { it.uppercase() }
    }

    private data class DerivedPortfolio(
        val chartData: StackLinearChartData?,
        val overview: PortfolioOverview?,
        val assetBreakdown: List<PortfolioBreakdownSlice>,
        val chainBreakdown: List<PortfolioBreakdownSlice>,
    )

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
        private const val UNKNOWN_CHAIN = "_unknown"
        private const val BREAKDOWN_MAX_SLICES = 4
        private val OTHERS_COLOR = 0xFF8E8E93.toInt()

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
