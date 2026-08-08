package org.mytonwallet.app_air.uiassets.viewControllers.token

import android.content.Context
import android.os.Handler
import android.os.Looper
import java.lang.ref.WeakReference
import kotlin.time.Duration.Companion.milliseconds
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.mytonwallet.app_air.walletbasecontext.utils.MHistoryTimePeriod
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.debug.TokenInfoDebugConfig
import org.mytonwallet.app_air.walletcore.debug.TokenInfoDebugSource
import org.mytonwallet.app_air.walletcore.helpers.ActivityLoader
import org.mytonwallet.app_air.walletcore.helpers.IActivityLoader
import org.mytonwallet.app_air.walletcore.models.MToken
import org.mytonwallet.app_air.walletcore.moshi.MApiTokenDetails
import org.mytonwallet.app_air.walletcore.moshi.api.ApiMethod
import org.mytonwallet.app_air.walletcore.stores.TokenStore

class TokenVM(
    val context: Context,
    private val accountId: String,
    val token: MToken,
    val delegate: WeakReference<Delegate>
) : WalletCore.EventObserver,
    IActivityLoader.Delegate {

    sealed interface TokenInfoState {
        data object Loading : TokenInfoState
        data class Details(val info: MApiTokenDetails.TokenInfo) : TokenInfoState
        data object Fallback : TokenInfoState

        companion object {
            fun resolved(info: MApiTokenDetails.TokenInfo?): TokenInfoState =
                if (info?.hasPublicInformation == true) Details(info) else Fallback
        }
    }

    companion object {
        const val CHART_UPDATE_INTERVAL = 5 * 60 * 1000L
        const val TOKEN_INFO_RETRY_INTERVAL = 5_000L
    }

    interface Delegate {
        fun dataUpdated(isUpdateEvent: Boolean)
        fun loadedAll()
        fun priceDataUpdated()
        fun tokenInfoUpdated()
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
    var tokenInfoState: TokenInfoState = TokenInfoState.Loading
        private set

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var tokenInfoJob: Job? = null

    init {
        WalletCore.registerObserver(this)
    }

    fun onDestroy() {
        scope.cancel()
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
        loadTokenInfo()
    }

    private fun loadTokenInfo() {
        tokenInfoJob?.cancel()
        setTokenInfoState(TokenInfoState.Loading)
        when (val debugSource = TokenInfoDebugConfig.source) {
            TokenInfoDebugSource.COMPLETE_DATA,
            TokenInfoDebugSource.LOCALIZED_DESCRIPTION,
            TokenInfoDebugSource.LONG_DESCRIPTION_PARTIAL_DATA,
            TokenInfoDebugSource.MISSING_DESCRIPTION -> {
                val info = debugSource.mockTokenInfo
                val state = TokenInfoState.resolved(info)
                tokenInfoJob = scope.launch {
                    delay(2_000L.milliseconds)
                    withContext(Dispatchers.Main) {
                        setTokenInfoState(state)
                    }
                }
                return
            }

            TokenInfoDebugSource.REAL_API -> Unit
        }
        tokenInfoJob = scope.launch {
            while (isActive) {
                val state = try {
                    val details = WalletCore.call(
                        ApiMethod.Tokens.FetchTokenDetails(
                            listOf(token.tokenAddress ?: token.slug)
                        )
                    ).firstOrNull { it.slug == token.slug }
                    val info = details?.tokenInfo
                    TokenInfoState.resolved(info)
                } catch (e: CancellationException) {
                    throw e
                } catch (_: Throwable) {
                    null
                }
                if (state != null) {
                    withContext(Dispatchers.Main) {
                        setTokenInfoState(state)
                    }
                    break
                }
                delay(TOKEN_INFO_RETRY_INTERVAL)
            }
        }
    }

    private fun setTokenInfoState(state: TokenInfoState) {
        if (tokenInfoState == state) return
        tokenInfoState = state
        delegate.get()?.tokenInfoUpdated()
    }

    private var lastChartUpdate: Long = 0
    private fun loadPriceHistoryChart(period: MHistoryTimePeriod, useCache: Boolean = true) {
        // LP tokens have no chart
        if (token.isLpToken) return
        TokenStore.loadPriceHistory(
            token.slug,
            period
        ) { res, isFromCache, err ->
            if (period != selectedPeriod) return@loadPriceHistory
            if (!useCache && isFromCache) return@loadPriceHistory
            if (res == null || err != null) {
                if (!isFromCache) {
                    // An error occurred, retry after few seconds
                    Handler(Looper.getMainLooper()).postDelayed({
                        if (period != selectedPeriod) return@postDelayed
                        loadPriceHistoryChart(period)
                    }, 5000)
                }
                return@loadPriceHistory
            }
            if (!isFromCache) {
                // Schedule reloading the chart after some time
                lastChartUpdate = System.currentTimeMillis()
                Handler(Looper.getMainLooper()).postDelayed({
                    if (selectedPeriod != period ||
                        lastChartUpdate > System.currentTimeMillis() - CHART_UPDATE_INTERVAL
                    ) {
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
                if (walletEvent.accountId == accountId) delegate.get()?.accountRemoved()
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
