package org.mytonwallet.app_air.uiportfolio

import androidx.core.graphics.toColorInt
import androidx.core.net.toUri
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import org.mytonwallet.app_air.uicomponents.widgets.chart.extended.ChartModel
import org.mytonwallet.app_air.uicomponents.widgets.chart.extended.StackLinearChartData
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.models.MBaseCurrency
import org.mytonwallet.app_air.walletbasecontext.utils.optDoubleOrNull
import org.mytonwallet.app_air.walletbasecontext.utils.optIntOrNull
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.models.MAccount
import org.mytonwallet.app_air.walletcore.network.NetworkClient
import org.mytonwallet.app_air.walletcore.network.NetworkRequest
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import kotlin.math.pow
import kotlin.math.roundToLong

class PortfolioViewModel : ViewModel(), WalletCore.EventObserver {
    private val _stateFlow = MutableStateFlow<PortfolioUiState>(PortfolioUiState.Idle)
    val stateFlow: StateFlow<PortfolioUiState> = _stateFlow.asStateFlow()

    private var loadJob: Job? = null

    init {
        WalletCore.registerObserver(this)
        load()
    }

    fun load(
        account: MAccount? = AccountStore.activeAccount,
        baseCurrency: MBaseCurrency = WalletCore.baseCurrency,
    ) {
        val request = buildRequest(account, baseCurrency)
        if (request == null) {
            _stateFlow.value = PortfolioUiState.Error
            return
        }

        load(request)
    }

    fun load(request: PortfolioHistoryRequest) {
        loadJob?.cancel()
        loadJob = viewModelScope.launch {
            _stateFlow.value = PortfolioUiState.Loading(request)
            try {
                val rawData = fetchChartData(request)
                if (rawData == null) {
                    _stateFlow.value = PortfolioUiState.Error
                    return@launch
                }
                val chartData = withContext(Dispatchers.Default) {
                    rawData.toStackChartData(request.baseCurrency)
                }
                _stateFlow.value = PortfolioUiState.Loaded(request, chartData)
            } catch (e: CancellationException) {
                throw e
            } catch (_: Exception) {
                _stateFlow.value = PortfolioUiState.Error
            }
        }
    }

    override fun onWalletEvent(walletEvent: WalletEvent) {
        when (walletEvent) {
            is WalletEvent.AccountChanged,
            is WalletEvent.AccountChangedInApp,
            WalletEvent.BaseCurrencyChanged -> load()

            else -> {}
        }
    }

    fun onDestroy() {
        WalletCore.unregisterObserver(this)
    }

    private fun buildRequest(
        account: MAccount?,
        baseCurrency: MBaseCurrency,
    ): PortfolioHistoryRequest? {
        val addresses = account?.byChain
            ?.mapNotNull { (chain, wallet) ->
                wallet.address.takeIf { it.isNotEmpty() }?.let { "$chain:$it" }
            }
            ?.joinToString(",")
            ?.takeIf { it.isNotEmpty() }
            ?: return null

        val to = Date()
        val from = Date(to.time - HISTORY_DAYS * DAY_MS)

        return PortfolioHistoryRequest(
            addresses = addresses,
            baseCurrency = baseCurrency,
            fromIso = isoFormatter.format(from),
            toIso = isoFormatter.format(to),
        )
    }

    private suspend fun fetchChartData(request: PortfolioHistoryRequest): PortfolioChartData? {
        val url = "$PORTFOLIO_API_URL/net-worth-history".toUri()
            .buildUpon()
            .appendQueryParameter("wallets", request.addresses)
            .appendQueryParameter("from", request.fromIso)
            .appendQueryParameter("to", request.toIso)
            .appendQueryParameter("density", request.density)
            .appendQueryParameter("base", request.baseCurrency.currencyCode.lowercase())
            .build()
            .toString()

        val json = fetchJson(url) ?: return null
        return parseChartData(json)
    }

    private suspend fun fetchJson(url: String): JSONObject? {
        val response = NetworkClient.request(
            NetworkRequest(
                url = url,
                connectTimeoutMs = CONNECT_TIMEOUT_MS,
                readTimeoutMs = READ_TIMEOUT_MS,
                writeTimeoutMs = READ_TIMEOUT_MS,
                callTimeoutMs = CONNECT_TIMEOUT_MS + READ_TIMEOUT_MS,
                retryCount = RETRY_COUNT,
                retryDelayMs = RETRY_DELAY_MS,
            )
        )

        if (!response.isSuccessful) return null

        return JSONObject(response.body)
    }

    private fun parseChartData(json: JSONObject): PortfolioChartData? {
        val datasets = json.optJSONArray("datasets")
        if (datasets != null) {
            return PortfolioChartData.ByAsset(
                datasets = parseDatasets(datasets),
            )
        }

        val points = json.optJSONArray("points") ?: return null

        return PortfolioChartData.Aggregated(
            points = parsePoints(points),
        )
    }

    private fun parseDatasets(json: JSONArray): List<PortfolioDataset> {
        return buildList {
            for (i in 0 until json.length()) {
                val item = json.optJSONObject(i) ?: continue
                val symbol = item.optString("symbol").takeIf { it.isNotEmpty() } ?: continue
                val points = item.optJSONArray("points") ?: continue

                add(
                    PortfolioDataset(
                        assetId = item.optIntOrNull("assetId"),
                        symbol = symbol,
                        contractAddress = item.optString("contractAddress")
                            .takeIf { it.isNotEmpty() },
                        color = item.optString("color").takeIf { it.isNotEmpty() },
                        points = parsePoints(points),
                        impact = item.optDoubleOrNull("impact"),
                    )
                )
            }
        }
    }

    private fun parsePoints(json: JSONArray): List<PortfolioHistoryPoint> {
        return buildList {
            for (i in 0 until json.length()) {
                val point = json.optJSONArray(i) ?: continue
                if (point.length() < 2) continue

                add(
                    PortfolioHistoryPoint(
                        timestamp = point.getLong(0),
                        value = point.getDouble(1),
                    )
                )
            }
        }
    }

    private fun PortfolioChartData.toStackChartData(baseCurrency: MBaseCurrency): StackLinearChartData? {
        return when (this) {
            is PortfolioChartData.Aggregated -> historyPointsToStackChartData(points, baseCurrency)
            is PortfolioChartData.ByAsset -> datasetsToStackChartData(datasets, baseCurrency)
        }
    }

    private fun historyPointsToStackChartData(
        points: List<PortfolioHistoryPoint>,
        baseCurrency: MBaseCurrency,
    ): StackLinearChartData? {
        val sortedPoints = points.sortedBy { it.timestamp }
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
        datasets: List<PortfolioDataset>,
        baseCurrency: MBaseCurrency,
    ): StackLinearChartData? {
        val activeDatasets = datasets.map(::PortfolioDatasetSummary)
            .filter { it.impact > 0.0 || it.hasPositiveValues }
            .sortedWith(
                compareByDescending<PortfolioDatasetSummary> { it.impact }
                    .thenByDescending { it.latestValue }
            )
            .map { it.dataset }

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
                    id = dataset.assetId?.let { "asset_$it" }
                        ?: dataset.contractAddress
                        ?: "asset_${dataset.symbol}_$index",
                    name = dataset.symbol,
                    color = dataset.color?.toChartColor(index)
                        ?: fallbackChartColors[index % fallbackChartColors.size],
                    values = timestamps.map {
                        (valuesByTimestamp[it] ?: 0.0).toChartValue(baseCurrency.decimalsCount)
                    },
                )
            }
        )
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

    private data class PortfolioDatasetSummary(
        val dataset: PortfolioDataset,
        val latestValue: Double = dataset.points.lastOrNull { it.value > 0.0 }?.value ?: 0.0,
        val impact: Double = dataset.impact ?: 0.0,
        val hasPositiveValues: Boolean = dataset.points.any { it.value > 0.0 },
    )

    private data class ChartSeriesInput(
        val id: String,
        val name: String,
        val color: Int,
        val values: List<Long>,
    )

    companion object {
        private val isoFormatter: SimpleDateFormat by lazy {
            SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US).apply {
                timeZone = TimeZone.getTimeZone("UTC")
            }
        }

        private const val PORTFOLIO_API_URL = "https://api-portfolio.mytonwallet.io/api"
        private const val HISTORY_DAYS = 365L
        private const val DAY_MS = 86_400_000L
        private const val CONNECT_TIMEOUT_MS = 15_000
        private const val READ_TIMEOUT_MS = 30_000
        private const val RETRY_COUNT = 100
        private const val RETRY_DELAY_MS = 500L
        private const val UNIX_TIMESTAMP_MS_THRESHOLD = 10_000_000_000L

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
