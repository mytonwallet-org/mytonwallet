package org.mytonwallet.app_air.walletcontext.cacheStorage

import android.content.Context
import android.content.SharedPreferences
import androidx.core.content.edit

object WCacheStorage {
    private lateinit var sharedPreferences: SharedPreferences

    private const val CACHE_PREF_NAME = "airCache"
    private const val CACHE_PREF_TOKENS = "tokens"
    private const val CACHE_PREF_SWAP_ASSETS = "swapAssets"

    private const val CACHE_PREF_STAKING_DATA = "stakingData."
    private const val CACHE_PREF_NFTS = "nfts."
    private const val CACHE_PREF_NFT_COLLECTIONS = "nftCollections."
    private const val CACHE_PREF_HAS_HIDDEN_NFT = "hasHiddenNFT."
    private const val CACHE_PREF_EXPLORE = "exploreHistory."
    private const val CACHE_INITIAL_SCREEN = "initialScreen"

    fun init(context: Context) {
        sharedPreferences = context.getSharedPreferences(CACHE_PREF_NAME, Context.MODE_PRIVATE)
    }

    fun getTokens(): String? {
        return sharedPreferences.getString(CACHE_PREF_TOKENS, null)
    }

    fun setTokens(value: String) {
        sharedPreferences.edit { putString(CACHE_PREF_TOKENS, value) }
    }

    fun getSwapAssets(): String? {
        return sharedPreferences.getString(CACHE_PREF_SWAP_ASSETS, null)
    }

    fun setSwapAssets(value: String) {
        sharedPreferences.edit { putString(CACHE_PREF_SWAP_ASSETS, value) }
    }

    fun getStakingData(accountId: String): String? {
        return sharedPreferences.getString(CACHE_PREF_STAKING_DATA + accountId, null)
    }

    fun setStakingData(accountId: String, value: String?) {
        if (value == null) {
            sharedPreferences.edit { remove(CACHE_PREF_STAKING_DATA + accountId) }
            return
        }
        sharedPreferences.edit { putString(CACHE_PREF_STAKING_DATA + accountId, value) }
    }

    fun getNfts(accountId: String): String? {
        return sharedPreferences.getString(CACHE_PREF_NFTS + accountId, null)
    }

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

    fun getNftCollections(accountId: String): String? {
        return sharedPreferences.getString(CACHE_PREF_NFT_COLLECTIONS + accountId, null)
    }

    fun setNftCollections(accountId: String, value: String?) {
        sharedPreferences.edit {
            value?.let {
                putString(CACHE_PREF_NFT_COLLECTIONS + accountId, value)
            } ?: run {
                remove(CACHE_PREF_NFT_COLLECTIONS + accountId)
            }
        }
    }

    fun getExploreHistory(accountId: String): String? {
        return sharedPreferences.getString(CACHE_PREF_EXPLORE + accountId, null)
    }

    fun setExploreHistory(accountId: String, value: String?) {
        sharedPreferences.edit {
            value?.let {
                putString(CACHE_PREF_EXPLORE + accountId, value)
            } ?: run {
                remove(CACHE_PREF_EXPLORE + accountId)
            }
        }
    }

    enum class InitialScreen(val value: Int) {
        INTRO(0),
        HOME(1),
        LOCK(2);
    }

    private var cachedInitialScreen: Int? = null
    fun getInitialScreen(): InitialScreen? {
        cachedInitialScreen = sharedPreferences.getInt(CACHE_INITIAL_SCREEN, 0)
        return InitialScreen.entries.firstOrNull {
            it.value == cachedInitialScreen
        }
    }

    fun setInitialScreen(initialScreen: InitialScreen) {
        if (initialScreen.value == cachedInitialScreen)
            return
        sharedPreferences.edit {
            putInt(CACHE_INITIAL_SCREEN, initialScreen.value)
        }
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
    }
}
