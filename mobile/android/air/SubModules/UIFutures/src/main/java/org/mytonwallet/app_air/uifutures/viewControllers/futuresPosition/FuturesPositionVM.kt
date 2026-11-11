package org.mytonwallet.app_air.uifutures.viewControllers.futuresPosition

import java.lang.ref.WeakReference
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import org.json.JSONObject
import org.mytonwallet.app_air.uifutures.viewControllers.futures.cells.forActivityCard
import org.mytonwallet.app_air.uifutures.viewControllers.futuresEdit.FuturesQuoteResult
import org.mytonwallet.app_air.uifutures.viewControllers.futuresEdit.PERPS_QUOTE_FAILED
import org.mytonwallet.app_air.uifutures.viewControllers.futuresEdit.prepareFuturesQuote
import org.mytonwallet.app_air.walletbasecontext.utils.MHistoryTimePeriod
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.models.MToken
import org.mytonwallet.app_air.walletcore.moshi.MApiPerpsDraftRequest
import org.mytonwallet.app_air.walletcore.moshi.MApiPerpsFill
import org.mytonwallet.app_air.walletcore.moshi.MApiPerpsListedAsset
import org.mytonwallet.app_air.walletcore.moshi.MApiPerpsNativePosition
import org.mytonwallet.app_air.walletcore.moshi.PERPS_UNIT_CURRENCY
import org.mytonwallet.app_air.walletcore.stores.PerpsStore

class FuturesPositionVM(
    private val coin: String,
    private var accountId: String?,
    delegate: Delegate
) : WalletCore.EventObserver {
    interface Delegate {
        fun positionUpdated()
        fun priceDataUpdated()
    }

    private val delegate = WeakReference(delegate)
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    /** The period whose chart was last requested; `null` until the asset is known. */
    private var historyPeriod: MHistoryTimePeriod? = null
    private var isDestroyed = false
    private var chartRefreshJob: Job? = null
    private var closeEstimateJob: Job? = null

    var asset: MApiPerpsListedAsset? = null
        private set

    /** The open position in this market, or `null` once the account's positions show there is none. */
    var position: MApiPerpsNativePosition? = null
        private set
    var activities: List<MApiPerpsFill> = emptyList()
        private set

    /** More activities of this market than the card shows; it ends with Show All. */
    var hasMoreActivities = false
        private set
    var historyData: Array<Array<Double>>? = null
        private set

    /** Remembered per account, as the token screen remembers its period. */
    var selectedPeriod: MHistoryTimePeriod = accountId
        ?.let(WGlobalStorage::currentFuturesPeriod)
        ?.let { value -> MHistoryTimePeriod.entries.find { it.value == value } }
        ?: MHistoryTimePeriod.DAY
        set(value) {
            if (field == value) return
            field = value
            accountId?.let {
                WGlobalStorage.setCurrentFuturesPeriod(it, value.value)
            }
            historyData = null
            delegate.get()?.priceDataUpdated()
            loadPriceHistory()
        }

    val displayName: String
        get() = asset?.displayName ?: asset?.symbol ?: coin

    val description: String?
        get() = asset?.description

    /** Stand-in token for the price chart, priced like wallet tokens in the base currency. */
    val chartToken: MToken?
        get() {
            val asset = asset ?: return null
            val context = asset.context
            val markPrice = context?.markPx?.toDoubleOrNull() ?: return null
            val percentChange24h = context.percentChange24h ?: context.prevDayPx
                ?.toDoubleOrNull()
                ?.takeIf { it > 0 }
                ?.let { (markPrice / it - 1) * 100 }
            return MToken(
                JSONObject().apply {
                    put("slug", "$CHART_SLUG_PREFIX$coin")
                    put("symbol", asset.symbol)
                    put("name", displayName)
                    put("decimals", CHART_DECIMALS)
                    put("priceUsd", markPrice)
                    asset.image?.let { put("image", it) }
                    percentChange24h?.let { put("percentChange24h", it) }
                }
            )
        }

    fun start() {
        WalletCore.registerObserver(this)
        rebuild()
        refresh()
    }

    fun switchAccount(accountId: String) {
        if (this.accountId == accountId) return
        this.accountId = accountId
        position = null
        activities = emptyList()
        hasMoreActivities = false
        rebuild()
    }

    fun onDestroy() {
        isDestroyed = true
        scope.cancel()
        WalletCore.unregisterObserver(this)
    }

    /** Quotes closing the whole position, for review. */
    fun prepareClose(onResult: (FuturesQuoteResult) -> Unit) {
        val position = position
        val asset = position?.asset?.id
        val accountId = accountId
        if (position == null || asset == null || accountId == null) {
            return onResult(FuturesQuoteResult(null, PERPS_QUOTE_FAILED))
        }
        closeEstimateJob?.cancel()
        closeEstimateJob = scope.launch {
            onResult(
                prepareFuturesQuote(accountId, closeDraft(position, asset), loadsFunding = false)
            )
        }
    }

    fun closeDraft(position: MApiPerpsNativePosition, assetId: String) = MApiPerpsDraftRequest(
        assetId = assetId,
        side = position.side,
        amount = "0",
        unit = PERPS_UNIT_CURRENCY,
        leverage = position.leverage,
        editing = true,
        close = true
    )

    fun refresh() {
        PerpsStore.refresh()
    }

    /** Keeps the mark price, P&L and liquidation live while the screen is shown. */
    fun startPolling() {
        PerpsStore.watch(this)
    }

    fun stopPolling() {
        PerpsStore.unwatch(this)
    }

    override fun onWalletEvent(walletEvent: WalletEvent) {
        when (walletEvent) {
            WalletEvent.PerpsUpdated -> rebuild()

            WalletEvent.SideGuttersChanged -> delegate.get()?.positionUpdated()

            WalletEvent.BaseCurrencyChanged -> {
                historyData = null
                delegate.get()?.priceDataUpdated()
                loadPriceHistory()
            }

            else -> {}
        }
    }

    private fun rebuild() {
        val asset = PerpsStore.assetsByCoin[coin]
        this.asset = asset
        PerpsStore.snapshotFor(accountId)?.let { snapshot ->
            position = snapshot.openPositions.firstOrNull { it.coin == coin }
        }
        val (fills, hasMoreFills) = PerpsStore.fillsFor(accountId).orEmpty()
            .filter { it.coin == coin }
            .forActivityCard(VISIBLE_ACTIVITIES)
        // Older account pages can hold more of this market's trades
        hasMoreActivities = hasMoreFills || PerpsStore.hasMoreFills(accountId)
        activities = fills
        delegate.get()?.positionUpdated()
        if (historyPeriod == null) loadPriceHistory()
    }

    /** As TokenVM does: a network result schedules the next refresh, which skips the cache. */
    private fun loadPriceHistory(useCache: Boolean = true) {
        val asset = asset?.id ?: return
        val period = selectedPeriod
        historyPeriod = period
        PerpsStore.loadPriceHistory(asset, period) { data, isFromCache ->
            if (isDestroyed || period != selectedPeriod || asset != this.asset?.id) {
                return@loadPriceHistory
            }
            if (!useCache && isFromCache) return@loadPriceHistory
            if (!isFromCache) scheduleChartRefresh(period)
            data ?: return@loadPriceHistory
            historyData = data
            delegate.get()?.priceDataUpdated()
        }
    }

    private fun scheduleChartRefresh(period: MHistoryTimePeriod) {
        chartRefreshJob?.cancel()
        chartRefreshJob = scope.launch {
            delay(CHART_UPDATE_INTERVAL_MS)
            if (period == selectedPeriod) loadPriceHistory(useCache = false)
        }
    }

    private companion object {
        const val CHART_UPDATE_INTERVAL_MS = 15_000L
        const val CHART_SLUG_PREFIX = "perps:"
        const val CHART_DECIMALS = 9
        const val VISIBLE_ACTIVITIES = 5
    }
}
