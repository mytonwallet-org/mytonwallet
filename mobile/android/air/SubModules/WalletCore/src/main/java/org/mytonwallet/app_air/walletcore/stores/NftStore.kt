package org.mytonwallet.app_air.walletcore.stores

import android.os.Handler
import android.os.Looper
import org.json.JSONArray
import org.json.JSONObject
import org.mytonwallet.app_air.walletcontext.WalletContextManager
import org.mytonwallet.app_air.walletcontext.cacheStorage.WCacheStorage
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.models.MCollectionTab
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.models.MCollectionTabToShow
import org.mytonwallet.app_air.walletcore.models.NftCollection
import org.mytonwallet.app_air.walletcore.models.blockchain.MBlockchain
import org.mytonwallet.app_air.walletcore.moshi.ApiNft
import org.mytonwallet.app_air.walletcore.moshi.api.ApiMethod
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors

object NftStore : IStore {
    private var cacheExecutor = Executors.newSingleThreadExecutor()

    private val cachedNftCollections = ConcurrentHashMap<String, List<MCollectionTabToShow>>()
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

    private enum class NftsMergeMode {
        PREPEND,
        APPEND
    }

    private data class StreamPruneContext(
        val chain: MBlockchain,
        val addresses: Set<String>
    )

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
                        chain = null,
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
        val nftData = this.nftData ?: return
        with(nftData) {
            whitelistedNftAddresses = WGlobalStorage.getWhitelistedNftAddresses(accountId)
            blacklistedNftAddresses = WGlobalStorage.getBlacklistedNftAddresses(accountId)
        }
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
        chain: MBlockchain?,
        nfts: List<ApiNft>?,
        accountId: String,
        notifyObservers: Boolean,
        isReorder: Boolean,
        shouldAppend: Boolean = false,
        preserveExistingOnConflict: Boolean = shouldAppend,
        streamedAddresses: Set<String>? = null
    ) {
        val streamPruneContext =
            if (chain != null && streamedAddresses != null) StreamPruneContext(chain, streamedAddresses) else null
        val incomingNfts = if (streamPruneContext == null) nfts.orEmpty() else emptyList()
        val mergeMode = if (shouldAppend) NftsMergeMode.APPEND else NftsMergeMode.PREPEND

        cacheExecutor.execute {
            val currentData = nftData
            val isActiveAccount = accountId == currentData?.accountId
            val existingNfts = resolveExistingNftsForSetNfts(accountId, currentData)
            val allNfts = resolveMergedNfts(
                chain = chain,
                nfts = nfts,
                existingNfts = existingNfts,
                incomingNfts = incomingNfts,
                isReorder = isReorder,
                mergeMode = mergeMode,
                preserveExistingOnConflict = preserveExistingOnConflict,
                streamPruneContext = streamPruneContext
            )

            if (!isActiveAccount) {
                updateDerivedCache(accountId, allNfts)
                return@execute
            }

            currentData ?: return@execute
            currentData.cachedNfts = allNfts?.toMutableList()
            writeToCache()

            if (notifyObservers) {
                WalletCore.notifyEvent(if (isReorder) WalletEvent.NftsReordered else WalletEvent.NftsUpdated)
            }
            if (!WGlobalStorage.getWasTelegramGiftsAutoAdded(accountId) &&
                currentData.cachedNfts.hasTelegramGifts()
            ) {
                val homeNftCollections =
                    WGlobalStorage.getHomeNftCollections(accountId)
                if (!homeNftCollections.any { it.address == NftCollection.TELEGRAM_GIFTS_SUPER_COLLECTION }) {
                    homeNftCollections.add(
                        MCollectionTab(
                            MBlockchain.ton.name,
                            NftCollection.TELEGRAM_GIFTS_SUPER_COLLECTION
                        )
                    )
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

    private fun resolveExistingNftsForSetNfts(
        accountId: String,
        currentData: NftData?
    ): List<ApiNft> {
        return if (accountId == currentData?.accountId) {
            currentData.cachedNfts ?: fetchCachedNfts(accountId).orEmpty()
        } else {
            fetchCachedNfts(accountId).orEmpty()
        }
    }

    private fun resolveMergedNfts(
        chain: MBlockchain?,
        nfts: List<ApiNft>?,
        existingNfts: List<ApiNft>,
        incomingNfts: List<ApiNft>,
        isReorder: Boolean,
        mergeMode: NftsMergeMode,
        preserveExistingOnConflict: Boolean,
        streamPruneContext: StreamPruneContext?
    ): List<ApiNft>? {
        return when {
            isReorder || chain == null -> nfts
            else -> mergeNfts(
                existingNfts = existingNfts,
                incomingNfts = incomingNfts,
                mergeMode = mergeMode,
                preferExistingOnConflict = preserveExistingOnConflict,
                streamPruneContext = streamPruneContext
            )
        }
    }

    private fun mergeNfts(
        existingNfts: List<ApiNft>,
        incomingNfts: List<ApiNft>,
        mergeMode: NftsMergeMode,
        preferExistingOnConflict: Boolean,
        streamPruneContext: StreamPruneContext?
    ): List<ApiNft> {
        val existingByAddress = linkedMapOf<String, ApiNft>()
        existingNfts.forEach { existingByAddress[it.address] = it }
        val existingOrderedAddresses = existingNfts.distinctBy { it.address }.map { it.address }

        if (streamPruneContext != null) {
            val byAddress = existingByAddress.filterValues { nft ->
                (nft.chain ?: MBlockchain.ton) != streamPruneContext.chain ||
                    streamPruneContext.addresses.contains(nft.address)
            }
            val orderedAddresses = existingOrderedAddresses.filter { address ->
                val nft = existingByAddress[address] ?: return@filter false
                (nft.chain ?: MBlockchain.ton) != streamPruneContext.chain ||
                    streamPruneContext.addresses.contains(address)
            }
            return orderedAddresses.mapNotNull { byAddress[it] }
        }

        val incomingByAddress = linkedMapOf<String, ApiNft>()
        incomingNfts.forEach { incomingByAddress[it.address] = it }
        val incomingOrderedAddresses = incomingNfts.distinctBy { it.address }.map { it.address }

        val byAddress = when {
            mergeMode == NftsMergeMode.APPEND && preferExistingOnConflict -> {
                linkedMapOf<String, ApiNft>().apply {
                    putAll(incomingByAddress)
                    putAll(existingByAddress)
                }
            }

            else -> {
                linkedMapOf<String, ApiNft>().apply {
                    putAll(existingByAddress)
                    putAll(incomingByAddress)
                }
            }
        }

        val orderedAddresses = when (mergeMode) {
            NftsMergeMode.PREPEND -> {
                (incomingOrderedAddresses + existingOrderedAddresses).distinct()
            }

            NftsMergeMode.APPEND -> {
                (existingOrderedAddresses + incomingOrderedAddresses).distinct()
            }
        }

        return orderedAddresses.mapNotNull { byAddress[it] }
    }

    private fun updateDerivedCache(accountId: String, nfts: List<ApiNft>?) {
        if (!nfts.isNullOrEmpty()) {
            val collections = getCollectionsFromNfts(nfts)
            writeCollectionsToCache(accountId, collections)
            val hasHiddenNft = nfts.any { it.isHidden == true }
            WCacheStorage.setHasHiddenNft(accountId, hasHiddenNft)
            cachedHasHiddenNfts[accountId] = hasHiddenNft
        } else {
            WCacheStorage.setNftCollections(accountId, null)
            cachedNftCollections.remove(accountId)
            WCacheStorage.setHasHiddenNft(accountId, null)
            cachedHasHiddenNfts.remove(accountId)
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

    fun add(accountId: String, nft: ApiNft) {
        cacheExecutor.execute {
            if (nftData?.accountId != accountId)
                return@execute
            val index = nftData?.cachedNfts?.indexOfFirst { it.address == nft.address } ?: -1
            if (index > -1) {
                nftData?.cachedNfts?.set(index, nft)
            } else {
                if (nftData?.cachedNfts == null)
                    nftData?.cachedNfts = mutableListOf(nft)
                else
                    nftData?.cachedNfts?.add(0, nft)
            }
            writeToCache()
            WalletCore.notifyEvent(WalletEvent.ReceivedNewNFT)
        }
    }

    fun removeByAddress(accountId: String, nftAddress: String) {
        cacheExecutor.execute {
            if (nftData?.accountId != accountId)
                return@execute
            nftData?.cachedNfts =
                nftData?.cachedNfts?.filter { it.address != nftAddress }?.toMutableList()
            writeToCache()
            WalletCore.notifyEvent(WalletEvent.NftsUpdated)
        }
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
                    val hasHiddenNft = cachedNfts.hasHiddenNfts()
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
                    chain = MBlockchain.ton.name,
                    accountId = accountId,
                    nftAddress = installedNft.address
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
                    chain = MBlockchain.ton.name,
                    accountId = accountId,
                    nftAddress = installedPaletteNft.address
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

    fun getCollections(): List<MCollectionTabToShow> {
        return getCollectionsFromNfts(nftData?.cachedNfts ?: emptyList())
    }

    fun getCollectionsFromNfts(nfts: List<ApiNft>): List<MCollectionTabToShow> {
        val uniqueCollections = linkedSetOf<MCollectionTabToShow>()

        for (nft in nfts) {
            if (!nft.shouldHide() && !nft.isStandalone()) {
                nft.collectionAddress?.let {
                    nft.collectionName?.let {
                        uniqueCollections.add(
                            MCollectionTabToShow(
                                chain = (nft.chain ?: MBlockchain.ton).name,
                                address = nft.collectionAddress,
                                name = nft.collectionName
                            )
                        )
                    }
                }
            }
        }

        return uniqueCollections.toList().sortedWith(compareBy { it.name })
    }

    fun getCollections(accountId: String): List<MCollectionTabToShow> {
        // Try to read from local cache, for some reason shared preferences may return slowly.
        cachedNftCollections[accountId]?.let {
            return it
        }
        // Try to read from cache
        WCacheStorage.getNftCollections(accountId)?.let {
            val nftCollectionsJSONArray = JSONArray(it)
            val nftCollectionsArray = ArrayList<MCollectionTabToShow>()
            for (i in 0 until nftCollectionsJSONArray.length()) {
                val nftJson = nftCollectionsJSONArray.get(i) as JSONObject
                MCollectionTabToShow.fromJson(nftJson)?.let { nftCollection ->
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
        val collections = getCollectionsFromNfts(nfts ?: emptyList())
        cacheExecutor.execute {
            writeCollectionsToCache(accountId, collections)
        }
        val hasHiddenNft = nfts.hasHiddenNfts()
        WCacheStorage.setHasHiddenNft(accountId, hasHiddenNft)
        cachedHasHiddenNfts[accountId] = hasHiddenNft
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
        val hasHiddenNft = nfts.hasHiddenNfts()
        WCacheStorage.setHasHiddenNft(accountId, hasHiddenNft)
        cachedHasHiddenNfts[accountId] = hasHiddenNft
        cacheExecutor.execute {
            writeCollectionsToCache(
                accountId,
                getCollectionsFromNfts(nfts ?: emptyList())
            )
        }
        return hasHiddenNft
    }

    private fun writeCollectionsToCache(accountId: String, collections: List<MCollectionTabToShow>) {
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

    private fun List<ApiNft>?.hasHiddenNfts(): Boolean {
        return this?.any { it.isHidden == true } == true
    }

    private fun List<ApiNft>?.hasTelegramGifts(): Boolean {
        return this?.any { it.isTelegramGift == true } == true
    }
}
