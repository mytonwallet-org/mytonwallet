package org.mytonwallet.app_air.walletcore.stores

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import org.json.JSONArray
import org.json.JSONObject
import org.mytonwallet.app_air.walletcontext.cacheStorage.WCacheStorage
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.api.fetchPriceHistory
import org.mytonwallet.app_air.walletcore.models.MBaseCurrency
import org.mytonwallet.app_air.walletcore.models.MBridgeError
import org.mytonwallet.app_air.walletcore.models.MHistoryTimePeriod
import org.mytonwallet.app_air.walletcore.models.MToken
import org.mytonwallet.app_air.walletcore.moshi.ApiTokenWithPrice
import org.mytonwallet.app_air.walletcore.moshi.MApiSwapAsset

object TokenStore {

    // Observable Flow
    data class Tokens(
        val tokens: Map<String, ApiTokenWithPrice>,
        val baseCurrency: MBaseCurrency,
    )

    private val _tokensFlow = MutableStateFlow<Tokens?>(null)
    fun setFlowValue(tokens: Tokens) {
        _tokensFlow.value = tokens
    }

    val tokensFlow = _tokensFlow.asStateFlow()
    /////

    fun loadFromCache() {
        WCacheStorage.getTokens()?.let { tokensString ->
            val tokensJsonArray = JSONArray(tokensString)
            for (item in 0..<tokensJsonArray.length()) {
                val token = MToken(tokensJsonArray.get(item) as JSONObject)
                setToken(token.slug, token)
            }
            swapAssets2 = tokens.values.map { MApiSwapAsset.from(it) }
        }
        WCacheStorage.getSwapAssets()?.let { swapAssetsString ->
            val swapAssetsArray = JSONArray(swapAssetsString)
            val assetsArray = ArrayList<MToken>()
            for (item in 0..<swapAssetsArray.length()) {
                assetsArray.add(MToken(swapAssetsArray.get(item) as JSONObject))
            }
            if (assetsArray.size > 0) {
                swapAssets = assetsArray
                _swapAssetsFlow.value = assetsArray.map { MApiSwapAsset.from(it) }
            }
        }
    }

    @Volatile
    var tokens = HashMap<String, MToken>()
        private set

    @Volatile
    var swapAssets: ArrayList<MToken>? = null

    internal val _swapAssetsFlow = MutableStateFlow<List<MApiSwapAsset>?>(null)
    val swapAssetsFlow = _swapAssetsFlow.asStateFlow()

    var swapAssets2: List<MApiSwapAsset>? = null
    var swapAssetsMap: Map<String, MApiSwapAsset>? = null
    var isLoadingSwapAssets = false

    val loadedAllTokens: Boolean
        get() {
            return tokens.size > 6
        }

    fun getToken(slug: String?, searchMinterAddress: Boolean = false): MToken? {
        slug?.let {
            return@getToken tokens[slug] ?: swapAssets?.find {
                it.slug == slug || (searchMinterAddress && it.tokenAddress == slug)
            }
        }
        return null
    }

    fun setToken(slug: String, token: MToken) {
        tokens[slug] = token
    }

    fun clearQuotes() {
        for (token in tokens.values) {
            setToken(token.slug, token.apply { price = null })
        }
    }

    fun updateSwapCache() {
        val arr = JSONArray()
        for (it in swapAssets ?: emptyList()) {
            arr.put(it.toDictionary())
        }
        WCacheStorage.setSwapAssets(arr.toString())
    }

    fun updateTokensCache() {
        val arr = JSONArray()
        for (it in tokens.keys) {
            arr.put(tokens[it]?.toDictionary())
        }
        WCacheStorage.setTokens(arr.toString())
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
            WalletCore.baseCurrency?.currencyCode ?: ""
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
}
