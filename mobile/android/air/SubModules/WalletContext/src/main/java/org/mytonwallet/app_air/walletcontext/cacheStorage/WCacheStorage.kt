package org.mytonwallet.app_air.walletcontext.cacheStorage

import android.content.Context
import android.content.SharedPreferences
import androidx.core.content.edit

object WCacheStorage {
    private lateinit var sharedPreferences: SharedPreferences

    private const val CACHE_PREF_NAME = "airCache"
    private const val CACHE_PREF_TOKENS = "tokens"
    private const val CACHE_PREF_SWAP_ASSETS = "swapAssets"
    private const val CACHE_PREF_TOKEN_DETAILS = "tokenDetails"
    private const val CACHE_PREF_MARKET_ASSETS = "marketAssets"

    private const val CACHE_PREF_STAKING_DATA = "stakingData."
    private const val CACHE_PREF_NFTS = "nfts."
    private const val CACHE_PREF_NFT_COLLECTIONS = "nftCollections."
    private const val CACHE_PREF_HAS_HIDDEN_NFT = "hasHiddenNFT."
    private const val CACHE_PREF_EXPLORE = "exploreHistory."
    private const val CACHE_PREF_PORTFOLIO = "portfolio."
    private const val CACHE_INITIAL_SCREEN = "initialScreen"
    private const val CACHE_AGENT_CLIENT_ID = "agentClientId"

    fun init(context: Context) {
        sharedPreferences = context.getSharedPreferences(CACHE_PREF_NAME, Context.MODE_PRIVATE)
    }

    fun getTokens(): String? = sharedPreferences.getString(CACHE_PREF_TOKENS, null)

    fun setTokens(value: String?) {
        if (value == null) {
            sharedPreferences.edit { remove(CACHE_PREF_TOKENS) }
            return
        }
        sharedPreferences.edit { putString(CACHE_PREF_TOKENS, value) }
    }

    fun getSwapAssets(): String? = sharedPreferences.getString(CACHE_PREF_SWAP_ASSETS, null)

    fun setSwapAssets(value: String?) {
        if (value == null) {
            sharedPreferences.edit { remove(CACHE_PREF_SWAP_ASSETS) }
            return
        }
        sharedPreferences.edit { putString(CACHE_PREF_SWAP_ASSETS, value) }
    }

    fun getTokenDetails(): String? = sharedPreferences.getString(CACHE_PREF_TOKEN_DETAILS, null)

    fun setTokenDetails(value: String?) {
        sharedPreferences.edit {
            value?.let {
                putString(CACHE_PREF_TOKEN_DETAILS, it)
            } ?: remove(CACHE_PREF_TOKEN_DETAILS)
        }
    }

    fun getMarketAssets(): String? = sharedPreferences.getString(CACHE_PREF_MARKET_ASSETS, null)

    fun setMarketAssets(value: String?) {
        sharedPreferences.edit {
            value?.let {
                putString(CACHE_PREF_MARKET_ASSETS, it)
            } ?: remove(CACHE_PREF_MARKET_ASSETS)
        }
    }

    fun getStakingData(accountId: String): String? =
        sharedPreferences.getString(CACHE_PREF_STAKING_DATA + accountId, null)

    fun setStakingData(accountId: String, value: String?) {
        if (value == null) {
            sharedPreferences.edit { remove(CACHE_PREF_STAKING_DATA + accountId) }
            return
        }
        sharedPreferences.edit { putString(CACHE_PREF_STAKING_DATA + accountId, value) }
    }

    fun getNfts(accountId: String): String? =
        sharedPreferences.getString(CACHE_PREF_NFTS + accountId, null)

    fun setNfts(accountId: String, value: String?) {
        sharedPreferences.edit {
            value?.let {
                putString(CACHE_PREF_NFTS + accountId, value)
            } ?: run {
                remove(CACHE_PREF_NFTS + accountId)
            }
        }
    }

    fun getHasHiddenNft(accountId: String): Boolean? {
        val key = CACHE_PREF_HAS_HIDDEN_NFT + accountId
        return if (sharedPreferences.contains(key)) {
            sharedPreferences.getBoolean(key, false)
        } else {
            null
        }
    }

    fun setHasHiddenNft(accountId: String, value: Boolean?) {
        sharedPreferences.edit {
            value?.let {
                putBoolean(CACHE_PREF_HAS_HIDDEN_NFT + accountId, value)
            } ?: run {
                remove(CACHE_PREF_HAS_HIDDEN_NFT + accountId)
            }
        }
    }

    fun getNftCollections(accountId: String): String? =
        sharedPreferences.getString(CACHE_PREF_NFT_COLLECTIONS + accountId, null)

    fun setNftCollections(accountId: String, value: String?) {
        sharedPreferences.edit {
            value?.let {
                putString(CACHE_PREF_NFT_COLLECTIONS + accountId, value)
            } ?: run {
                remove(CACHE_PREF_NFT_COLLECTIONS + accountId)
            }
        }
    }

    fun getExploreHistory(accountId: String): String? =
        sharedPreferences.getString(CACHE_PREF_EXPLORE + accountId, null)

    fun setExploreHistory(accountId: String, value: String?) {
        sharedPreferences.edit {
            value?.let {
                putString(CACHE_PREF_EXPLORE + accountId, value)
            } ?: run {
                remove(CACHE_PREF_EXPLORE + accountId)
            }
        }
    }

    fun getPortfolio(key: String): String? =
        sharedPreferences.getString(CACHE_PREF_PORTFOLIO + key, null)

    fun setPortfolio(key: String, value: String?) {
        sharedPreferences.edit {
            value?.let {
                putString(CACHE_PREF_PORTFOLIO + key, value)
            } ?: run {
                remove(CACHE_PREF_PORTFOLIO + key)
            }
        }
    }

    private fun removePortfolioByKeyPrefix(keyPrefix: String) {
        val fullPrefix = CACHE_PREF_PORTFOLIO + keyPrefix
        val toRemove = sharedPreferences.all.keys.filter { it.startsWith(fullPrefix) }
        if (toRemove.isEmpty()) return
        sharedPreferences.edit {
            toRemove.forEach { remove(it) }
        }
    }

    fun cleanPortfolio(accountId: String) {
        removePortfolioByKeyPrefix(PortfolioCacheKey.accountPrefix(accountId))
    }

    // Drops the prior cached entries for one chart of an account+period (all currencies/buckets);
    // called right before persisting a fresh response so each chart keeps a single entry.
    fun cleanPortfolioChart(accountId: String, methodName: String, periodValue: String) {
        removePortfolioByKeyPrefix(
            PortfolioCacheKey.chartPrefix(accountId, methodName, periodValue)
        )
    }

    enum class InitialScreen(val value: Int) {
        INTRO(0),
        HOME(1),
        LOCK(2)
    }

    private var cachedInitialScreen: InitialScreen? = null

    fun getInitialScreen(): InitialScreen? = cachedInitialScreen ?: run {
        val value = sharedPreferences.getInt(CACHE_INITIAL_SCREEN, InitialScreen.INTRO.value)
        InitialScreen.entries.firstOrNull { it.value == value }
            ?.also { cachedInitialScreen = it }
    }

    fun setInitialScreen(initialScreen: InitialScreen) {
        if (cachedInitialScreen == initialScreen) return

        cachedInitialScreen = initialScreen
        sharedPreferences.edit {
            putInt(CACHE_INITIAL_SCREEN, initialScreen.value)
        }
    }

    fun getAgentClientId(): String? = sharedPreferences.getString(CACHE_AGENT_CLIENT_ID, null)

    fun setAgentClientId(value: String?) {
        sharedPreferences.edit {
            value?.let {
                putString(CACHE_AGENT_CLIENT_ID, value)
            } ?: run {
                remove(CACHE_AGENT_CLIENT_ID)
            }
        }
    }

    fun clearDownloadedData(): Boolean {
        val keys = setOf(
            CACHE_PREF_TOKENS,
            CACHE_PREF_SWAP_ASSETS,
            CACHE_PREF_TOKEN_DETAILS,
            CACHE_PREF_MARKET_ASSETS
        )
        val prefixes = listOf(
            CACHE_PREF_STAKING_DATA,
            CACHE_PREF_NFTS,
            CACHE_PREF_NFT_COLLECTIONS,
            CACHE_PREF_HAS_HIDDEN_NFT,
            CACHE_PREF_PORTFOLIO
        )
        return sharedPreferences.edit().apply {
            sharedPreferences.all.keys.forEach { key ->
                if (key in keys || prefixes.any { key.startsWith(it) }) remove(key)
            }
        }.commit()
    }

    fun clean(accountIds: Array<String>) {
        for (accountId in accountIds) {
            clean(accountId)
        }
    }

    fun clean(accountId: String) {
        setNfts(accountId, null)
        setNftCollections(accountId, null)
        setHasHiddenNft(accountId, null)
        setStakingData(accountId, null)
        setExploreHistory(accountId, null)
        cleanPortfolio(accountId)
    }
}
