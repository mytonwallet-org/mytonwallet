package org.mytonwallet.app_air.uiassets.viewControllers.token

import android.content.Context
import android.os.Handler
import android.os.Looper
import org.mytonwallet.app_air.walletbasecontext.utils.MHistoryTimePeriod
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.helpers.ActivityLoader
import org.mytonwallet.app_air.walletcore.helpers.IActivityLoader
import org.mytonwallet.app_air.walletcore.models.MToken
import org.mytonwallet.app_air.walletcore.stores.TokenStore
import java.lang.ref.WeakReference

class TokenVM(
    val context: Context,
    private val accountId: String,
    val token: MToken,
    val delegate: WeakReference<Delegate>
) : WalletCore.EventObserver,
    IActivityLoader.Delegate {

    companion object {
        const val CHART_UPDATE_INTERVAL = 5 * 60 * 1000L
    }

    interface Delegate {
        fun dataUpdated(isUpdateEvent: Boolean)
        fun loadedAll()
        fun priceDataUpdated()
        fun stateChanged()
        fun accountChanged()
        fun accountRemoved()
        fun cacheNotFound()
    }

    var selectedPeriod: MHistoryTimePeriod =
        MHistoryTimePeriod.entries
            .find { it.value == WGlobalStorage.currentTokenPeriod(accountId) }
            ?: MHistoryTimePeriod.DAY
        set(value) {
            field = value
            WGlobalStorage.setCurrentTokenPeriod(accountId, value.value)
            historyData = null
            delegate.get()?.priceDataUpdated()
            loadPriceHistoryChart(value)
        }

    var historyData: Array<Array<Double>>? = null
    var activityLoader: IActivityLoader? = null

    init {
        WalletCore.registerObserver(this)
    }

    fun onDestroy() {
        WalletCore.unregisterObserver(this)
    }

    fun refreshTransactions() {
        activityLoader?.clean()
        activityLoader = ActivityLoader(
            context,
            accountId,
            token.slug,
            WeakReference(this)
        )
        activityLoader?.askForActivities()
        loadPriceHistoryChart(selectedPeriod)
    }

    private var lastChartUpdate: Long = 0
    private fun loadPriceHistoryChart(period: MHistoryTimePeriod, useCache: Boolean = true) {
        TokenStore.loadPriceHistory(
            token.slug,
            period,
        ) { res, isFromCache, err ->
            if (period != selectedPeriod)
                return@loadPriceHistory
            if (!useCache && isFromCache)
                return@loadPriceHistory
            if (res == null || err != null) {
                if (!isFromCache) {
                    // An error occurred, retry after few seconds
                    Handler(Looper.getMainLooper()).postDelayed({
                        if (period != selectedPeriod)
                            return@postDelayed
                        loadPriceHistoryChart(period)
                    }, 5000)
                }
                return@loadPriceHistory
            }
            if (!isFromCache) {
                // Schedule reloading the chart after some time
                lastChartUpdate = System.currentTimeMillis()
                Handler(Looper.getMainLooper()).postDelayed({
                    if (selectedPeriod != period || lastChartUpdate > System.currentTimeMillis() - CHART_UPDATE_INTERVAL) {
                        return@postDelayed
                    }
                    loadPriceHistoryChart(period, useCache = false)
                }, CHART_UPDATE_INTERVAL)
            }
            historyData = res
            delegate.get()?.priceDataUpdated()
        }
    }

    override fun activityLoaderDataLoaded(isUpdateEvent: Boolean) {
        delegate.get()?.dataUpdated(isUpdateEvent)
    }

    override fun activityLoaderCacheNotFound() {
        delegate.get()?.cacheNotFound()
    }

    override fun activityLoaderLoadedAll() {
        delegate.get()?.loadedAll()
    }

    override fun onWalletEvent(walletEvent: WalletEvent) {
        when (walletEvent) {
            WalletEvent.HideTinyTransfersChanged -> {
                delegate.get()?.dataUpdated(false)
            }

            WalletEvent.BalanceChanged,
            WalletEvent.TokensChanged -> {
                delegate.get()?.priceDataUpdated()
                delegate.get()?.dataUpdated(false)
            }

            WalletEvent.BaseCurrencyChanged -> {
                historyData = null
                delegate.get()?.priceDataUpdated()
                loadPriceHistoryChart(selectedPeriod)
                delegate.get()?.dataUpdated(false)
            }

            is WalletEvent.AccountChanged -> {
                delegate.get()?.accountChanged()
            }

            is WalletEvent.AccountRemoved -> {
                if (walletEvent.accountId == accountId)
                    delegate.get()?.accountRemoved()
            }

            is WalletEvent.AccountSavedAddressesChanged -> {
                delegate.get()?.dataUpdated(false)
            }

            WalletEvent.NetworkDisconnected -> {
                delegate.get()?.stateChanged()
            }

            else -> {}
        }
    }
}
