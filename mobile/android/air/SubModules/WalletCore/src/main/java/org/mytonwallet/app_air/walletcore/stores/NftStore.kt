package org.mytonwallet.app_air.walletcore.stores

import android.os.Handler
import android.os.Looper
import org.json.JSONArray
import org.json.JSONObject
import org.mytonwallet.app_air.walletcontext.WalletContextManager
import org.mytonwallet.app_air.walletcontext.cacheStorage.WCacheStorage
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.models.NftCollection
import org.mytonwallet.app_air.walletcore.moshi.ApiNft
import org.mytonwallet.app_air.walletcore.moshi.api.ApiMethod
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors

object NftStore : IStore {
    private var cacheExecutor = Executors.newSingleThreadExecutor()

    private val cachedNftCollections = ConcurrentHashMap<String, List<NftCollection>>()
    private val cachedHasHiddenNfts = ConcurrentHashMap<String, Boolean>()

    data class NftData(
        val accountId: String,
        var cachedNfts: MutableList<ApiNft>? = null,
        var whitelistedNftAddresses: MutableList<String> = mutableListOf(),
        var blacklistedNftAddresses: MutableList<String> = mutableListOf(),
        var expirationByAddress: HashMap<String, Long>? = null,
        var linkedAddressByAddress: HashMap<String, String>? = null,
    ) {
        val telegramGiftCollectionAddresses: Set<String>
            get() {
                return cachedNfts
                    ?.filter { it.isTelegramGift == true }
                    ?.mapNotNull { it.collectionAddress }
                    ?.toSet() ?: emptySet()
            }
    }

    @Volatile
    var nftData: NftData? = null
        private set

    fun loadCachedNfts(accountId: String) {
        clearActiveNftData()
        nftData = NftData(
            accountId = accountId,
        )
        cacheExecutor.execute {
            resetWhitelistAndBlacklist()
            fetchCachedNfts(accountId)?.let { nftsArray ->
                Handler(Looper.getMainLooper()).post {
                    if (AccountStore.activeAccountId != accountId)
                        return@post
                    setNfts(
                        nftsArray,
                        accountId = accountId,
                        notifyObservers = true,
                        isReorder = false
                    )
                }
            }
        }
    }

    fun resetWhitelistAndBlacklist() {
        nftData?.whitelistedNftAddresses =
            WGlobalStorage.getWhitelistedNftAddresses(nftData!!.accountId)
        nftData?.blacklistedNftAddresses =
            WGlobalStorage.getBlacklistedNftAddresses(nftData!!.accountId)
    }

    fun showNft(nft: ApiNft) {
        val nftData = nftData ?: return
        if (nft.isHidden == true) {
            if (!nftData.whitelistedNftAddresses.contains(nft.address)) {
                nftData.whitelistedNftAddresses.add(nft.address)
                WGlobalStorage.setWhitelistedNftAddresses(
                    nftData.accountId,
                    nftData.whitelistedNftAddresses
                )
            }
        } // else: it's shown by default
        // To make sure it's not in blacklist (maybe nft was not hidden before and added to blacklist manually)
        nftData.blacklistedNftAddresses.remove(nft.address)
        WGlobalStorage.setBlacklistedNftAddresses(
            nftData.accountId,
            nftData.blacklistedNftAddresses
        )
        WalletCore.notifyEvent(WalletEvent.NftsUpdated)
    }

    fun hideNft(nft: ApiNft) {
        val nftData = nftData ?: return
        if (nft.isHidden != true) {
            if (!nftData.blacklistedNftAddresses.contains(nft.address)) {
                nftData.blacklistedNftAddresses.add(nft.address)
                WGlobalStorage.setBlacklistedNftAddresses(
                    nftData.accountId,
                    nftData.blacklistedNftAddresses
                )
            }
        } // else: it's hidden by default
        // Make sure it's not in whitelist (maybe nft was hidden before and added to whitelist, so do it in all conditions)
        nftData.whitelistedNftAddresses.remove(nft.address)
        WGlobalStorage.setWhitelistedNftAddresses(
            nftData.accountId,
            nftData.whitelistedNftAddresses
        )
        WalletCore.notifyEvent(WalletEvent.NftsUpdated)
    }

    fun setNfts(
        nfts: List<ApiNft>?,
        accountId: String,
        notifyObservers: Boolean,
        isReorder: Boolean
    ) {
        val nftData = nftData

        if (accountId != nftData?.accountId) {
            // Update cached values for not-active account
            cacheExecutor.execute {
                nfts?.let { nfts ->
                    val collections = getCollectionsFromNfts(nfts)
                    writeCollectionsToCache(accountId, collections)
                    val hasHiddenNft = nfts.find { it.isHidden == true } != null
                    WCacheStorage.setHasHiddenNft(accountId, hasHiddenNft)
                    cachedHasHiddenNfts[accountId] = hasHiddenNft
                } ?: run {
                    WCacheStorage.setNftCollections(accountId, null)
                    cachedNftCollections.remove(accountId)
                    WCacheStorage.setHasHiddenNft(accountId, null)
                    cachedHasHiddenNfts.remove(accountId)
                }
            }
            return
        }

        cacheExecutor.execute {
            if (!isReorder &&
                nftData.cachedNfts != null &&
                nfts != null &&
                nftData.cachedNfts?.size == nfts.size &&
                nftData.cachedNfts?.all { cached -> nfts.any { new -> cached.isSame(new) } } == true
            ) {
                return@execute
            }

            nftData.cachedNfts = when {
                isReorder || nfts.isNullOrEmpty() || nftData.cachedNfts.isNullOrEmpty() -> nfts
                else -> {
                    val nftMap = nfts.associateBy { it.address }
                    val cachedAddresses =
                        nftData.cachedNfts?.mapTo(mutableSetOf()) { it.address } ?: emptyList()

                    val newNfts = nfts.filterNot { it.address in cachedAddresses }

                    val updatedCachedNfts = nftData.cachedNfts?.mapNotNull { cached ->
                        nftMap[cached.address]
                    }

                    newNfts + (updatedCachedNfts ?: emptyList())
                }
            }?.toMutableList()
            writeToCache()

            if (notifyObservers)
                WalletCore.notifyEvent(if (isReorder) WalletEvent.NftsReordered else WalletEvent.NftsUpdated)
            if (!WGlobalStorage.getWasTelegramGiftsAutoAdded(accountId) &&
                nftData.cachedNfts?.any {
                    it.isTelegramGift == true
                } == true
            ) {
                val homeNftCollections =
                    WGlobalStorage.getHomeNftCollections(accountId)
                if (!homeNftCollections.contains(NftCollection.TELEGRAM_GIFTS_SUPER_COLLECTION)) {
                    homeNftCollections.add(NftCollection.TELEGRAM_GIFTS_SUPER_COLLECTION)
                    WGlobalStorage.setWasTelegramGiftsAutoAdded(
                        accountId,
                        true
                    )
                    WGlobalStorage.setHomeNftCollections(
                        accountId,
                        homeNftCollections
                    )
                    WalletCore.notifyEvent(WalletEvent.HomeNftCollectionsUpdated)
                }
            }
        }
    }

    fun setExpirationByAddress(accountId: String, expirationByAddress: HashMap<String, Long>?) {
        if (nftData?.accountId != accountId)
            return
        nftData?.expirationByAddress = expirationByAddress
    }

    fun setLinkedAddressByAddress(
        accountId: String,
        linkedAddressByAddress: HashMap<String, String>?
    ) {
        if (nftData?.accountId != accountId)
            return
        nftData?.linkedAddressByAddress = linkedAddressByAddress
    }

    fun add(nft: ApiNft) {
        val index = nftData?.cachedNfts?.indexOfFirst { it.address == nft.address }
        if ((index ?: -1) > -1) {
            nftData?.cachedNfts?.set(index!!, nft)
        } else {
            if (nftData?.cachedNfts == null)
                nftData?.cachedNfts = mutableListOf(nft)
            else
                nftData?.cachedNfts?.add(0, nft)
        }
        writeToCache()
        WalletCore.notifyEvent(WalletEvent.ReceivedNewNFT)
    }

    fun removeByAddress(nftAddress: String) {
        nftData?.cachedNfts =
            nftData?.cachedNfts?.filter { it.address != nftAddress }?.toMutableList()
        writeToCache()
        WalletCore.notifyEvent(WalletEvent.NftsUpdated)
    }

    override fun wipeData() {
        clearCache()
    }

    override fun clearCache() {
        clearActiveNftData()
        cachedNftCollections.clear()
        cachedHasHiddenNfts.clear()
    }

    private fun clearActiveNftData() {
        nftData = null
        cacheExecutor.shutdownNow()
        cacheExecutor = Executors.newSingleThreadExecutor()
    }

    private fun writeToCache() {
        val nftData = nftData ?: return
        cacheExecutor.execute {
            nftData.accountId.let { accountId ->
                nftData.cachedNfts?.let { cachedNfts ->
                    val arr = JSONArray()
                    for (it in cachedNfts) {
                        arr.put(it.toDictionary())
                    }
                    WCacheStorage.setNfts(accountId, arr.toString())
                    val collections = getCollectionsFromNfts(cachedNfts)
                    writeCollectionsToCache(accountId, collections)
                    val hasHiddenNft = cachedNfts.find { it.isHidden == true } != null
                    WCacheStorage.setHasHiddenNft(accountId, hasHiddenNft)
                    cachedHasHiddenNfts[accountId] = hasHiddenNft
                }
            }
        }
    }

    fun checkCardNftOwnership(accountId: String) {
        val installedCard = WGlobalStorage.getCardBackgroundNft(accountId)
        installedCard?.let {
            val installedNft = ApiNft.fromJson(installedCard)!!
            WalletCore.call(
                ApiMethod.Nft.CheckNftOwnership(
                    accountId,
                    installedNft.address
                )
            ) { res, err ->
                if (err != null)
                    return@call
                if (res == false) {
                    WGlobalStorage.setCardBackgroundNft(
                        accountId,
                        null
                    )
                    if (AccountStore.activeAccountId == accountId)
                        WalletCore.notifyEvent(WalletEvent.NftCardUpdated)
                }
            }
        }
        val installedPalette = WGlobalStorage.getAccentColorNft(accountId)
        installedPalette?.let {
            val installedPaletteNft = ApiNft.fromJson(installedPalette)!!
            WalletCore.call(
                ApiMethod.Nft.CheckNftOwnership(
                    accountId,
                    installedPaletteNft.address
                )
            ) { res, err ->
                if (err != null)
                    return@call
                if (res == false) {
                    WGlobalStorage.setNftAccentColor(
                        accountId,
                        null,
                        null
                    )
                    if (AccountStore.activeAccountId == accountId)
                        WalletContextManager.delegate?.themeChanged()
                }
            }
        }
    }

    fun getCollections(): List<NftCollection> {
        return getCollectionsFromNfts(nftData?.cachedNfts ?: emptyList())
    }

    fun getCollectionsFromNfts(nfts: List<ApiNft>): List<NftCollection> {
        val uniqueCollections = linkedSetOf<NftCollection>()

        for (nft in nfts) {
            if (!nft.shouldHide() && !nft.isStandalone()) {
                nft.collectionAddress?.let {
                    nft.collectionName?.let {
                        uniqueCollections.add(
                            NftCollection(nft.collectionAddress, nft.collectionName)
                        )
                    }
                }
            }
        }

        return uniqueCollections.toList().sortedWith(compareBy { it.name })
    }

    fun getCollections(accountId: String): List<NftCollection> {
        // Try to read from local cache, for some reason shared preferences may return slowly.
        cachedNftCollections[accountId]?.let {
            return it
        }
        // Try to read from cache
        WCacheStorage.getNftCollections(accountId)?.let {
            val nftCollectionsJSONArray = JSONArray(it)
            val nftCollectionsArray = ArrayList<NftCollection>()
            for (i in 0 until nftCollectionsJSONArray.length()) {
                val nftJson = nftCollectionsJSONArray.get(i) as JSONObject
                NftCollection.fromJson(nftJson)?.let { nftCollection ->
                    nftCollectionsArray.add(nftCollection)
                }
            }
            return nftCollectionsArray
        }
        // Cache not found, extract them and write to cache
        val nfts = if (nftData?.accountId == accountId) {
            nftData?.cachedNfts
        } else {
            fetchCachedNfts(accountId)
        }
        cacheExecutor.execute {
            writeCollectionsToCache(accountId, getCollectionsFromNfts(nfts ?: emptyList()))
        }
        val hasHiddenNft = nfts?.find { it.isHidden == true } != null
        WCacheStorage.setHasHiddenNft(accountId, hasHiddenNft)
        cachedHasHiddenNfts[accountId] = hasHiddenNft
        val collections = getCollectionsFromNfts(nfts ?: emptyList())
        cachedNftCollections[accountId] = collections
        return collections
    }

    fun getHasHiddenNft(accountId: String): Boolean {
        // Try to read from local cache, for some reason shared preferences may return slowly.
        cachedHasHiddenNfts[accountId]?.let {
            return it
        }
        // Try to read from cache
        WCacheStorage.getHasHiddenNft(accountId)?.let {
            return it
        }
        // Cache not found, extract them
        val nfts = if (nftData?.accountId == accountId) {
            nftData?.cachedNfts
        } else {
            fetchCachedNfts(accountId)
        }
        val hasHiddenNft = nfts?.find { it.isHidden == true } != null
        WCacheStorage.setHasHiddenNft(accountId, hasHiddenNft)
        cachedHasHiddenNfts[accountId] = hasHiddenNft
        cacheExecutor.execute {
            writeCollectionsToCache(accountId, getCollectionsFromNfts(nfts ?: emptyList()))
        }
        return hasHiddenNft
    }

    private fun writeCollectionsToCache(accountId: String, collections: List<NftCollection>) {
        val arrCollections = JSONArray()
        for (it in collections) {
            arrCollections.put(it.toDictionary())
        }
        WCacheStorage.setNftCollections(
            accountId,
            arrCollections.toString()
        )
        cachedNftCollections[accountId] = collections
    }

    fun fetchCachedNfts(accountId: String): List<ApiNft>? {
        val nftsString = WCacheStorage.getNfts(accountId) ?: run {
            if (WGlobalStorage.getAccountTonAddress(accountId) == null)
                "[]"
            else
                null
        }
        if (nftsString != null) {
            val nftsJSONArray = JSONArray(nftsString)
            val nftsArray = ArrayList<ApiNft>()
            for (i in 0 until nftsJSONArray.length()) {
                val nftJson = nftsJSONArray.get(i) as JSONObject
                ApiNft.fromJson(nftJson)?.let { nft ->
                    nftsArray.add(nft)
                }
            }
            return nftsArray
        }
        return null
    }
}
