package org.mytonwallet.app_air.walletcore.stores

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import org.json.JSONArray
import org.json.JSONObject
import org.mytonwallet.app_air.walletbasecontext.logger.Logger
import org.mytonwallet.app_air.walletbasecontext.utils.MHistoryTimePeriod
import org.mytonwallet.app_air.walletcontext.cacheStorage.WCacheStorage
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcore.TESTNET_SLUGS
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.api.fetchPriceHistory
import org.mytonwallet.app_air.walletcore.models.MBridgeError
import org.mytonwallet.app_air.walletcore.models.MToken
import org.mytonwallet.app_air.walletcore.moshi.ApiTokenWithPrice
import org.mytonwallet.app_air.walletcore.moshi.MApiSwapAsset
import org.mytonwallet.app_air.walletcore.moshi.api.ApiUpdate
import java.util.concurrent.ConcurrentHashMap

object TokenStore : IStore {

    // Observable Flow
    data class Tokens(
        val tokens: Map<String, ApiTokenWithPrice>,
    )

    private val _tokensFlow = MutableStateFlow<Tokens?>(null)
    fun setFlowValue(tokens: Tokens) {
        _tokensFlow.value = tokens
    }

    val tokensFlow = _tokensFlow.asStateFlow()
    /////

    fun loadFromCache() {
        try {
            currencyRates = WGlobalStorage.getCurrencyRates()?.let { jsonObject ->
                jsonObject.keys().asSequence().associateWith { key -> jsonObject.getDouble(key) }
            }
        } catch (t: Throwable) {
            Logger.e(Logger.LogTag.AIR_APPLICATION, "TokenStore: bad currencyRates: ${t.message}")
            currencyRates = null
            WGlobalStorage.setCurrencyRates(null)
        }

        WCacheStorage.getTokens()?.let { tokensString ->
            try {
                val tokensJsonArray = JSONArray(tokensString)
                for (item in 0..<tokensJsonArray.length()) {
                    val token = MToken(tokensJsonArray.get(item) as JSONObject)
                    setToken(token.slug, token)
                }
                setSwapAssets(tokens.values.toList())
            } catch (t: Throwable) {
                Logger.e(
                    Logger.LogTag.AIR_APPLICATION,
                    "TokenStore: bad tokens cache: ${t.message}"
                )
                tokens.clear()
                setSwapAssets(null)
                WCacheStorage.setTokens(null)
            }
        }
        WCacheStorage.getSwapAssets()?.let { swapAssetsString ->
            try {
                val swapAssetsArray = JSONArray(swapAssetsString)
                val assetsArray = ArrayList<MToken>()
                for (item in 0..<swapAssetsArray.length()) {
                    assetsArray.add(MToken(swapAssetsArray.get(item) as JSONObject))
                }
                if (assetsArray.isNotEmpty()) {
                    setSwapAssets(assetsArray)
                }
            } catch (t: Throwable) {
                Logger.e(
                    Logger.LogTag.AIR_APPLICATION,
                    "TokenStore: bad swapAssets cache: ${t.message}"
                )
                WCacheStorage.setSwapAssets(null)
            }
        }
        seedDefaultTokensIfRequired()
        BalanceStore.resetBalanceInBaseCurrency()
    }

    @Volatile
    var tokens = ConcurrentHashMap<String, MToken>()
        private set

    @Volatile
    var currencyRates: Map<String, Double>? = null
    val baseCurrencyRate: Double?
        get() {
            return currencyRates?.get(WalletCore.baseCurrency.currencyCode)
        }

    internal val _swapAssetsFlow = MutableStateFlow<List<MApiSwapAsset>?>(null)
    val swapAssetsFlow = _swapAssetsFlow.asStateFlow()

    // List of swap assets, as MToken to query
    @Volatile
    private var swapAssetTokens: List<MToken>? = null

    @Volatile
    var swapAssets: List<MApiSwapAsset>? = null
        private set

    @Volatile
    var swapAssetsMap: Map<String, MApiSwapAsset>? = null
        private set

    @Volatile
    var isLoadingSwapAssets = false

    @Volatile
    var swapAssetsLoaded = false
        private set

    fun setSwapAssets(tokens: List<MToken>?, isDefault: Boolean = false) {
        swapAssetTokens = tokens
        swapAssets = tokens?.map { MApiSwapAsset.from(it) }
        swapAssetsMap = swapAssets?.associateBy { it.slug }
        _swapAssetsFlow.value = swapAssets
        if (!isDefault) {
            swapAssetsLoaded = !tokens.isNullOrEmpty()
        }
    }

    val loadedAllTokens: Boolean
        get() {
            return tokens.size > 6
        }

    fun getToken(slug: String?, searchMinterAddress: Boolean = false): MToken? {
        val key = slug ?: return null

        return tokens[key]
            ?: swapAssetTokens?.find { it.slug == key || (searchMinterAddress && it.tokenAddress == key) }
    }

    fun setToken(slug: String, token: MToken) {
        tokens[slug] = token
    }

    private fun seedDefaultTokensIfRequired() {
        if (tokens.isEmpty()) {
            for ((slug, token) in DefaultTokens.tokens) {
                tokens.putIfAbsent(slug, token)
            }
        }
        if (_tokensFlow.value == null && tokens.isNotEmpty()) {
            setFlowValue(Tokens(tokens.mapValues { it.value.toApiTokenWithPrice() }))
        }
        if (swapAssets.isNullOrEmpty() && DefaultTokens.tokens.isNotEmpty()) {
            setSwapAssets(
                DefaultTokens.tokens.values
                    .filter { it.slug !in TESTNET_SLUGS },
                isDefault = true
            )
        }
    }

    private fun MToken.toApiTokenWithPrice() = ApiTokenWithPrice(
        name = name,
        symbol = symbol,
        slug = slug,
        decimals = decimals,
        chain = chain,
        tokenAddress = tokenAddress,
        image = image,
        isPopular = isPopular,
        keywords = keywords,
        cmcSlug = cmcSlug,
        color = color,
        codeHash = codeHash,
        label = label,
        priceUsd = priceUsd,
        percentChange24h = percentChange24h,
    )

    private val cacheScope =
        CoroutineScope(SupervisorJob() + Dispatchers.IO.limitedParallelism(1))

    @Volatile
    private var tokensCacheJob: Job? = null

    @Volatile
    private var swapCacheJob: Job? = null

    fun updateSwapCache() {
        val snapshot = ArrayList(swapAssetTokens ?: emptyList())
        swapCacheJob?.cancel()
        swapCacheJob = cacheScope.launch {
            try {
                val json = tokensToJsonString(snapshot)
                ensureActive()
                WCacheStorage.setSwapAssets(json)
            } catch (t: OutOfMemoryError) {
                Logger.e(
                    Logger.LogTag.MEMORY,
                    "TokenStore: OOM serializing swap cache: ${t.message}"
                )
                WCacheStorage.setSwapAssets(null)
            }
        }
    }

    fun updateTokensCache() {
        val snapshot = ArrayList(tokens.values)
        tokensCacheJob?.cancel()
        tokensCacheJob = cacheScope.launch {
            try {
                val json = tokensToJsonString(snapshot)
                ensureActive()
                WCacheStorage.setTokens(json)
            } catch (t: OutOfMemoryError) {
                Logger.e(
                    Logger.LogTag.MEMORY,
                    "TokenStore: OOM serializing tokens cache: ${t.message}"
                )
                WCacheStorage.setTokens(null)
            }
        }
    }

    private fun tokensToJsonString(items: Iterable<MToken>): String {
        val sb = StringBuilder("[")
        var first = true
        for (token in items) {
            if (!first) sb.append(',')
            sb.append(token.toDictionary().toString())
            first = false
        }
        sb.append(']')
        return sb.toString()
    }

    fun updateCurrencyRates(update: ApiUpdate.ApiUpdateCurrencyRates) {
        val prevCurrencyRate = baseCurrencyRate
        currencyRates = update.rates
        WGlobalStorage.setCurrencyRates(update.rates)
        if (baseCurrencyRate != prevCurrencyRate) {
            WalletCore.notifyEvent(WalletEvent.TokensChanged)
        }
    }

    // Load price history from cache and update the price history instantly
    fun loadPriceHistory(
        slug: String,
        period: MHistoryTimePeriod,
        callback: (data: Array<Array<Double>>?, fromCache: Boolean, MBridgeError?) -> Unit,
    ) {
        val cachedData = WGlobalStorage.getPriceHistory(slug, period.value)
        if (cachedData != null)
            callback(cachedData, true, null)
        updatePriceHistory(slug, period, callback)
    }

    // Update price history data for a specific token and time period
    private fun updatePriceHistory(
        slug: String,
        period: MHistoryTimePeriod,
        callback: (data: Array<Array<Double>>?, fromCache: Boolean, MBridgeError?) -> Unit,
        retriesLeft: Int = 3
    ) {
        WalletCore.fetchPriceHistory(
            slug,
            period,
            WalletCore.baseCurrency.currencyCode
        ) { res, err ->
            if (res == null || err != null) {
                if (retriesLeft > 0) {
                    updatePriceHistory(slug, period, callback, retriesLeft - 1)
                } else {
                    callback(null, false, err)
                }
                return@fetchPriceHistory
            }
            WGlobalStorage.setPriceHistory(slug, period.value, res)
            callback(res, false, null)
        }
    }

    fun getTokenInfo(): JSONObject {
        val tokenInfo = JSONObject()
        for (token in tokens) {
            tokenInfo.put(token.key, token.value.toDictionary())
        }
        return tokenInfo
    }

    override fun wipeData() {
    }

    override fun clearCache() {
    }
}
