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
import java.util.concurrent.Executors

object NftStore {
    private var cacheExecutor = Executors.newSingleThreadExecutor()

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
        clean()
        nftData = NftData(
            accountId = accountId,
        )
        resetWhitelistAndBlacklist()
        Executors.newSingleThreadExecutor().execute {
            val nftsString = WCacheStorage.getNfts(accountId) ?: run {
                if (AccountStore.activeAccount?.tonAddress == null)
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

        if (accountId != nftData?.accountId)
            return
        if (!isReorder &&
            nftData.cachedNfts != null &&
            nfts != null &&
            nftData.cachedNfts?.size == nfts.size &&
            nftData.cachedNfts?.all { cached -> nfts.any { new -> cached.isSame(new) } } == true
        ) {
            return
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

    fun clean() {
        nftData = null
        cacheExecutor.shutdownNow()
        cacheExecutor = Executors.newSingleThreadExecutor()
    }

    private fun writeToCache() {
        val nftData = nftData ?: return
        cacheExecutor.execute {
            nftData.accountId.let { accountId ->
                nftData.cachedNfts?.let {
                    val arr = JSONArray()
                    for (it in nftData.cachedNfts) {
                        arr.put(it.toDictionary())
                    }
                    WCacheStorage.setNfts(accountId, arr.toString())
                } ?: run {
                    WCacheStorage.setNfts(accountId, null)
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
        val uniqueCollections = linkedSetOf<NftCollection>()

        val nfts = nftData?.cachedNfts ?: emptyList()
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
}
