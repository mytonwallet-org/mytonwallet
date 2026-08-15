package org.mytonwallet.app_air.walletcore.stores

import android.os.Handler
import android.os.Looper
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import org.json.JSONArray
import org.json.JSONObject
import org.mytonwallet.app_air.walletbasecontext.logger.Logger
import org.mytonwallet.app_air.walletcontext.WalletContextManager
import org.mytonwallet.app_air.walletcontext.cacheStorage.WCacheStorage
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.models.MCollectionTab
import org.mytonwallet.app_air.walletcore.MTW_CARDS_COLLECTION
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.helpers.shouldHideNft
import org.mytonwallet.app_air.walletcore.models.MCollectionTabToShow
import org.mytonwallet.app_air.walletcore.models.NftCollection
import org.mytonwallet.app_air.walletcore.models.blockchain.MBlockchain
import org.mytonwallet.app_air.walletcore.moshi.ApiNft
import org.mytonwallet.app_air.walletcore.moshi.api.ApiMethod

object NftStore : IStore {
    private var cacheExecutor = Executors.newSingleThreadExecutor()
    private var collectionsPreloadExecutor = Executors.newSingleThreadExecutor()

    private val cachedNftCollections = ConcurrentHashMap<String, List<MCollectionTabToShow>>()
    private val preloadingCollections = ConcurrentHashMap.newKeySet<String>()
    private val cachedHasHiddenNfts = ConcurrentHashMap<String, Boolean>()
    private val ignoredExpiringAddressesByAccount = ConcurrentHashMap<String, MutableSet<String>>()

    // Accumulates new MTW cards across the batches of a streamed NFT polling round.
    // Drained on the round's final batch (`streamedAddresses != null` on `setNfts`).
    private val pendingNewMtwCardsByAccount = ConcurrentHashMap<String, MutableList<ApiNft>>()

    private val mintingAccountIds = ConcurrentHashMap.newKeySet<String>()

    fun isCardMinting(accountId: String): Boolean = mintingAccountIds.contains(accountId)

    fun setCardMinting(accountId: String, isMinting: Boolean) {
        val changed = if (isMinting) {
            mintingAccountIds.add(accountId)
        } else {
            mintingAccountIds.remove(accountId)
        }
        if (changed) WalletCore.notifyEvent(WalletEvent.CardMintingStateChanged(accountId))
    }

    fun interface PaletteExtractor {
        fun extract(nft: ApiNft, onResult: (Int?) -> Unit)
    }

    @Volatile
    private var paletteExtractor: PaletteExtractor? = null

    fun init(paletteExtractor: PaletteExtractor) {
        this.paletteExtractor = paletteExtractor
    }

    data class NftData(
        val accountId: String,
        var cachedNfts: MutableList<ApiNft>? = null,
        var whitelistedNftAddresses: MutableList<String> = mutableListOf(),
        var blacklistedNftAddresses: MutableList<String> = mutableListOf(),
        var expirationByAddress: HashMap<String, Long>? = null,
        var linkedAddressByAddress: HashMap<String, String>? = null
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

    private data class StreamPruneContext(val chain: MBlockchain, val addresses: Set<String>)

    @Volatile
    var nftData: NftData? = null
        private set

    fun loadCachedNfts(accountId: String) {
        clearActiveNftData()
        nftData = NftData(
            accountId = accountId
        )
        cacheExecutor.execute {
            resetWhitelistAndBlacklist()
            fetchCachedNfts(accountId)?.let { nftsArray ->
                Handler(Looper.getMainLooper()).post {
                    if (AccountStore.activeAccountId != accountId) return@post
                    setNfts(
                        chain = null,
                        nftsArray,
                        accountId = accountId,
                        notifyObservers = true,
                        isReorder = false,
                        shouldWriteNftsToCache = false
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

    fun showNft(accountId: String, nft: ApiNft) {
        val currentData = nftData?.takeIf { it.accountId == accountId }
        val whitelistedNftAddresses = currentData?.whitelistedNftAddresses
            ?: WGlobalStorage.getWhitelistedNftAddresses(accountId)
        val blacklistedNftAddresses = currentData?.blacklistedNftAddresses
            ?: WGlobalStorage.getBlacklistedNftAddresses(accountId)

        if (nft.isHidden == true || nft.isUnverified == true) {
            if (!whitelistedNftAddresses.contains(nft.address)) {
                whitelistedNftAddresses.add(nft.address)
                WGlobalStorage.setWhitelistedNftAddresses(
                    accountId,
                    whitelistedNftAddresses
                )
            }
        }
        // To make sure it's not in blacklist (maybe nft was not hidden before and added to blacklist manually)
        if (blacklistedNftAddresses.remove(nft.address)) {
            WGlobalStorage.setBlacklistedNftAddresses(accountId, blacklistedNftAddresses)
        }
        notifyVisibilityChanged(accountId)
    }

    fun hideNft(accountId: String, nft: ApiNft) {
        hideNft(accountId, listOf(nft))
    }

    fun hideNft(accountId: String, nfts: List<ApiNft>) {
        if (nfts.isEmpty()) return
        val currentData = nftData?.takeIf { it.accountId == accountId }
        val blacklistedNftAddresses = currentData?.blacklistedNftAddresses
            ?: WGlobalStorage.getBlacklistedNftAddresses(accountId)
        val whitelistedNftAddresses = currentData?.whitelistedNftAddresses
            ?: WGlobalStorage.getWhitelistedNftAddresses(accountId)

        var shouldPersistBlacklist = false
        for (nft in nfts) {
            if (!blacklistedNftAddresses.contains(nft.address)) {
                blacklistedNftAddresses.add(nft.address)
                shouldPersistBlacklist = true
            }
        }
        if (shouldPersistBlacklist) {
            WGlobalStorage.setBlacklistedNftAddresses(accountId, blacklistedNftAddresses)
        }

        // Make sure it's not in whitelist (maybe nft was hidden before and added to whitelist, so do it in all conditions)
        val didChangeWhitelist = whitelistedNftAddresses.removeAll(nfts.map { it.address }.toSet())
        if (didChangeWhitelist) {
            WGlobalStorage.setWhitelistedNftAddresses(accountId, whitelistedNftAddresses)
        }
        notifyVisibilityChanged(accountId)
    }

    /** Returns the cached copy, which is fresher than the snapshot kept inside an activity */
    fun getCachedNft(accountId: String, nftAddress: String): ApiNft? = nftData
        ?.takeIf { it.accountId == accountId }
        ?.cachedNfts
        ?.firstOrNull { it.address == nftAddress }

    fun isHiddenByUser(accountId: String, nft: ApiNft): Boolean {
        val entries = nftData
            ?.takeIf { it.accountId == accountId }
            ?.blacklistedNftAddresses
            ?: WGlobalStorage.getBlacklistedNftAddresses(accountId)
        return entries.contains(nft.address)
    }

    fun shouldHide(accountId: String, nft: ApiNft): Boolean {
        val currentData = nftData?.takeIf { it.accountId == accountId }
        val whitelistedNftAddresses = currentData?.whitelistedNftAddresses
            ?: WGlobalStorage.getWhitelistedNftAddresses(accountId)
        return shouldHideNft(
            isHiddenByUser = isHiddenByUser(accountId, nft),
            isWhitelisted = whitelistedNftAddresses.contains(nft.address),
            isHidden = nft.isHidden == true,
            isUnverified = nft.isUnverified == true,
            areUnverifiedNftsHidden = WGlobalStorage.getAreUnverifiedNftsHidden()
        )
    }

    private fun notifyVisibilityChanged(accountId: String) {
        if (nftData?.accountId == accountId) {
            WalletCore.notifyEvent(WalletEvent.NftsUpdated)
        }
    }

    fun setNfts(
        chain: MBlockchain?,
        nfts: List<ApiNft>?,
        accountId: String,
        notifyObservers: Boolean,
        isReorder: Boolean,
        shouldAppend: Boolean = false,
        preserveExistingOnConflict: Boolean = shouldAppend,
        streamedAddresses: Set<String>? = null,
        shouldWriteNftsToCache: Boolean = true,
        onComplete: (() -> Unit)? = null
    ) {
        val streamPruneContext =
            if (chain != null && streamedAddresses != null) {
                StreamPruneContext(
                    chain,
                    streamedAddresses
                )
            } else {
                null
            }
        val incomingNfts = if (streamPruneContext == null) nfts.orEmpty() else emptyList()
        val mergeMode = if (shouldAppend) NftsMergeMode.APPEND else NftsMergeMode.PREPEND

        // Streamed NFT polling: accumulate per-batch new MTW cards, then drain on the final
        // batch (`streamedAddresses != null`) to auto-install the rarest one. Diff against
        // the persistent `ownedMtwCardAddresses` so cards the user removed are not re-installed
        // each polling round.
        if (!isReorder && chain != null && !nfts.isNullOrEmpty()) {
            val ownedSet = WGlobalStorage.getOwnedMtwCardAddresses(accountId)
            val newMtwCards = nfts.filter {
                it.collectionAddress == MTW_CARDS_COLLECTION && !ownedSet.contains(it.address)
            }
            if (newMtwCards.isNotEmpty()) {
                pendingNewMtwCardsByAccount.getOrPut(accountId) { mutableListOf() }
                    .addAll(newMtwCards)
            }
        }

        cacheExecutor.execute {
            val currentData = nftData
            val isActiveAccount = accountId == currentData?.accountId
            val existingNfts = if (chain == null && !isReorder) {
                emptyList()
            } else {
                resolveExistingNftsForSetNfts(accountId, currentData)
            }
            val nftsToApply = if (isReorder) {
                val requestedOrder = nfts.orEmpty()
                    .mapIndexed { index, nft -> nft.address to index }
                    .toMap()
                existingNfts.sortedWith(
                    compareBy { requestedOrder[it.address] ?: Int.MAX_VALUE }
                )
            } else {
                nfts
            }
            val allNfts = resolveMergedNfts(
                chain = chain,
                nfts = nftsToApply,
                existingNfts = existingNfts,
                incomingNfts = incomingNfts,
                isReorder = isReorder,
                mergeMode = mergeMode,
                preserveExistingOnConflict = preserveExistingOnConflict,
                streamPruneContext = streamPruneContext
            )

            if (!isActiveAccount) {
                updateDerivedCache(accountId, allNfts)
                onComplete?.invoke()
                return@execute
            }

            if (currentData == null) {
                onComplete?.invoke()
                return@execute
            }
            currentData.cachedNfts = allNfts?.toMutableList()

            if (notifyObservers) {
                WalletCore.notifyEvent(
                    if (isReorder) WalletEvent.NftsReordered else WalletEvent.NftsUpdated
                )
            }
            if (!WGlobalStorage.getWasTelegramGiftsAutoAdded(accountId) &&
                currentData.cachedNfts.hasTelegramGifts()
            ) {
                val homeNftCollections =
                    WGlobalStorage.getHomeNftCollections(accountId)
                if (!homeNftCollections.any {
                        it.address ==
                            NftCollection.TELEGRAM_GIFTS_SUPER_COLLECTION
                    }
                ) {
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
            writeToCache(shouldWriteNftsToCache)

            if (streamedAddresses != null) {
                drainPendingMtwCardsOnStreamComplete(accountId, currentData.cachedNfts.orEmpty())
            }
            onComplete?.invoke()
        }
    }

    // On the final batch of a streamed NFT round: sync the ownership snapshot from the
    // authoritative cached list and auto-install the rarest just-arrived card if the
    // account has none set. "Rarest" = lowest `mtwCardId` (earlier mints are typically rarer).
    private fun drainPendingMtwCardsOnStreamComplete(accountId: String, currentNfts: List<ApiNft>) {
        val candidates = pendingNewMtwCardsByAccount.remove(accountId).orEmpty()

        syncOwnedMtwCardAddresses(accountId, currentNfts)

        if (candidates.isEmpty()) return
        if (WGlobalStorage.getCardBackgroundNft(accountId) != null) return

        val rarest = candidates.minByOrNull { it.metadata?.mtwCardId ?: Int.MAX_VALUE } ?: return
        installMtwCard(accountId, rarest)
    }

    private fun resolveExistingNftsForSetNfts(
        accountId: String,
        currentData: NftData?
    ): List<ApiNft> = if (accountId == currentData?.accountId) {
        currentData.cachedNfts ?: fetchCachedNfts(accountId).orEmpty()
    } else {
        fetchCachedNfts(accountId).orEmpty()
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
    ): List<ApiNft>? = when {
        isReorder || chain == null -> nfts

        else -> mergeNfts(
            existingNfts = existingNfts,
            incomingNfts = incomingNfts,
            mergeMode = mergeMode,
            preferExistingOnConflict = preserveExistingOnConflict,
            streamPruneContext = streamPruneContext
        )
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
                    putAll(existingByAddress)
                    putAll(incomingByAddress)
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
        if (nftData?.accountId != accountId) return
        nftData?.expirationByAddress = expirationByAddress
    }

    fun setLinkedAddressByAddress(
        accountId: String,
        linkedAddressByAddress: HashMap<String, String>?
    ) {
        if (nftData?.accountId != accountId) return
        nftData?.linkedAddressByAddress = linkedAddressByAddress
    }

    fun getIgnoredExpiringAddresses(accountId: String): Set<String> =
        ignoredExpiringAddressesByAccount[accountId] ?: emptySet()

    fun addIgnoredExpiringAddresses(accountId: String, addresses: Collection<String>) {
        ignoredExpiringAddressesByAccount
            .getOrPut(accountId) { mutableSetOf() }
            .addAll(addresses)
        WalletCore.notifyEvent(WalletEvent.NftDomainExpirationDismissed(accountId))
    }

    fun add(accountId: String, nft: ApiNft) {
        cacheExecutor.execute {
            if (nftData?.accountId != accountId) return@execute
            val current = nftData?.cachedNfts
            val index = current?.indexOfFirst { it.address == nft.address } ?: -1
            nftData?.cachedNfts = when {
                current == null -> mutableListOf(nft)
                index > -1 -> current.toMutableList().also { it[index] = nft }
                else -> current.toMutableList().also { it.add(0, nft) }
            }
            WalletCore.notifyEvent(WalletEvent.ReceivedNewNFT)
            writeToCache()
        }
    }

    fun removeByAddress(accountId: String, nftAddress: String) {
        cacheExecutor.execute {
            if (nftData?.accountId != accountId) return@execute
            nftData?.cachedNfts =
                nftData?.cachedNfts?.filter { it.address != nftAddress }?.toMutableList()
            WalletCore.notifyEvent(WalletEvent.NftsUpdated)
            writeToCache()
        }
    }

    // Auto-install an incoming MTW card on the target account, unless the account already
    // has one installed or has historically owned this card (see `ownedMtwCardAddresses`).
    // The `ownedMtwCardAddresses` snapshot is what prevents re-installing a card the user
    // previously removed if the activity history is replayed after a cache clear.
    fun applyIncomingMtwCard(accountId: String, nft: ApiNft) {
        if (nft.collectionAddress != MTW_CARDS_COLLECTION) return
        val owned = WGlobalStorage.getOwnedMtwCardAddresses(accountId)
        val alreadyOwned = owned.contains(nft.address)
        if (!alreadyOwned) {
            WGlobalStorage.setOwnedMtwCardAddresses(accountId, owned + nft.address)
        }
        if (alreadyOwned) return
        if (WGlobalStorage.getCardBackgroundNft(accountId) != null) return

        installMtwCard(accountId, nft)
    }

    fun syncOwnedMtwCardAddresses(accountId: String, nfts: List<ApiNft>) {
        val owned = nfts
            .filter { it.collectionAddress == MTW_CARDS_COLLECTION }
            .map { it.address }
        WGlobalStorage.setOwnedMtwCardAddresses(accountId, owned)
    }

    fun pruneOwnedMtwCardAddress(accountId: String, nftAddress: String) {
        val owned = WGlobalStorage.getOwnedMtwCardAddresses(accountId)
        if (!owned.contains(nftAddress)) return
        WGlobalStorage.setOwnedMtwCardAddresses(accountId, owned - nftAddress)
    }

    fun removeAccount(accountId: String) {
        pendingNewMtwCardsByAccount.remove(accountId)
        mintingAccountIds.remove(accountId)
        synchronized(checkOwnershipAccountIds) { checkOwnershipAccountIds.remove(accountId) }
    }

    private fun installMtwCard(accountId: String, nft: ApiNft) {
        WGlobalStorage.setCardBackgroundNft(accountId, nft.toDictionary())
        val extractor = paletteExtractor
        if (extractor != null) {
            extractor.extract(nft) { colorIndex ->
                if (WGlobalStorage.getCardBackgroundNftAddress(accountId) != nft.address) {
                    return@extract
                }
                if (colorIndex != null) {
                    WGlobalStorage.setNftAccentColor(accountId, colorIndex, nft.toDictionary())
                }
                if (AccountStore.activeAccountId == accountId) {
                    WalletContextManager.delegate?.get()?.themeChanged()
                }
                WalletCore.notifyEvent(WalletEvent.NftCardUpdated)
            }
        } else {
            WalletCore.notifyEvent(WalletEvent.NftCardUpdated)
        }
    }

    override fun wipeData() {
        clearCache()
    }

    override fun clearCache() {
        clearActiveNftData()
        collectionsPreloadExecutor.shutdownNow()
        collectionsPreloadExecutor = Executors.newSingleThreadExecutor()
        preloadingCollections.clear()
        cachedNftCollections.clear()
        cachedHasHiddenNfts.clear()
        ignoredExpiringAddressesByAccount.clear()
        pendingNewMtwCardsByAccount.clear()
        mintingAccountIds.clear()
        checkOwnershipHandler.removeCallbacks(checkOwnershipRunnable)
        synchronized(checkOwnershipAccountIds) { checkOwnershipAccountIds.clear() }
        paletteExtractor = null
    }

    private fun clearActiveNftData() {
        nftData = null
        cacheExecutor.shutdownNow()
        cacheExecutor = Executors.newSingleThreadExecutor()
    }

    private fun writeToCache(shouldWriteNfts: Boolean = true) {
        val nftData = nftData ?: return
        nftData.accountId.let { accountId ->
            nftData.cachedNfts?.let { cachedNfts ->
                if (shouldWriteNfts) {
                    val jsonString = try {
                        buildString {
                            append("[")
                            cachedNfts.forEachIndexed { index, nft ->
                                append(nft.toDictionary().toString())
                                if (index != cachedNfts.lastIndex) append(",")
                            }
                            append("]")
                        }
                    } catch (t: OutOfMemoryError) {
                        Logger.e(
                            Logger.LogTag.MEMORY,
                            "NftStore: OOM serializing nfts cache: ${t.message}"
                        )
                        WCacheStorage.setNfts(accountId, null)
                        return
                    }
                    WCacheStorage.setNfts(accountId, jsonString)
                }
                val collections = getCollectionsFromNfts(cachedNfts)
                writeCollectionsToCache(accountId, collections)
                val hasHiddenNft = cachedNfts.hasHiddenNfts()
                WCacheStorage.setHasHiddenNft(accountId, hasHiddenNft)
                cachedHasHiddenNfts[accountId] = hasHiddenNft
            }
        }
    }

    // NFT update events fire per-account/per-batch, causing a burst of ownership checks.
    // Debounced to match the web app's 3s coalescing window in `actions/api/cards.ts`.
    private const val CHECK_OWNERSHIP_DEBOUNCE_MS = 3000L
    private val checkOwnershipAccountIds = mutableSetOf<String>()
    private val checkOwnershipHandler = Handler(Looper.getMainLooper())
    private val checkOwnershipRunnable = Runnable { flushCheckCardNftOwnership() }

    fun checkCardNftOwnership(accountId: String) {
        synchronized(checkOwnershipAccountIds) {
            checkOwnershipAccountIds.add(accountId)
        }
        checkOwnershipHandler.removeCallbacks(checkOwnershipRunnable)
        checkOwnershipHandler.postDelayed(checkOwnershipRunnable, CHECK_OWNERSHIP_DEBOUNCE_MS)
    }

    private fun flushCheckCardNftOwnership() {
        val accountIds = synchronized(checkOwnershipAccountIds) {
            val snapshot = checkOwnershipAccountIds.toList()
            checkOwnershipAccountIds.clear()
            snapshot
        }
        accountIds.forEach { checkOwnershipForAccount(it) }
    }

    private fun checkOwnershipForAccount(accountId: String) {
        val installedCard = WGlobalStorage.getCardBackgroundNft(accountId)
        val installedPalette = WGlobalStorage.getAccentColorNft(accountId)
        if (installedCard == null && installedPalette == null) return

        val cardNft = installedCard?.let { ApiNft.fromJson(it) }
        val paletteNft = installedPalette?.let { ApiNft.fromJson(it) }

        cardNft?.let { nft ->
            WalletCore.call(
                ApiMethod.Nft.CheckNftOwnership(
                    chain = MBlockchain.ton.name,
                    accountId = accountId,
                    nftAddress = nft.address
                )
            ) { res, err ->
                if (err != null) return@call
                if (res == false) {
                    WGlobalStorage.setCardBackgroundNft(accountId, null)
                    if (AccountStore.activeAccountId == accountId) {
                        WalletCore.notifyEvent(WalletEvent.NftCardUpdated)
                    }
                    // If the palette NFT is the same address, the card's `res == false`
                    // already proves it's gone — clear palette without a second RPC.
                    if (paletteNft != null && paletteNft.address == nft.address) {
                        WGlobalStorage.setNftAccentColor(accountId, null, null)
                        if (AccountStore.activeAccountId == accountId) {
                            WalletContextManager.delegate?.get()?.themeChanged()
                        }
                    }
                }
            }
        }

        // Only call the palette RPC when it's a different address from the card.
        if (paletteNft != null && paletteNft.address != cardNft?.address) {
            WalletCore.call(
                ApiMethod.Nft.CheckNftOwnership(
                    chain = MBlockchain.ton.name,
                    accountId = accountId,
                    nftAddress = paletteNft.address
                )
            ) { res, err ->
                if (err != null) return@call
                if (res == false) {
                    WGlobalStorage.setNftAccentColor(accountId, null, null)
                    if (AccountStore.activeAccountId == accountId) {
                        WalletContextManager.delegate?.get()?.themeChanged()
                    }
                }
            }
        }
    }

    fun getCollections(): List<MCollectionTabToShow> =
        getCollectionsFromNfts(nftData?.cachedNfts ?: emptyList())

    fun accountOwnsCollection(
        accountId: String,
        address: String?,
        chain: MBlockchain? = null
    ): Boolean {
        if (address == null) return false
        return getCollections(accountId).any {
            it.address == address && (chain == null || it.chain == chain.name)
        }
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

    fun preloadCollections(accountId: String) {
        if (cachedNftCollections.containsKey(accountId) || !preloadingCollections.add(accountId)) {
            return
        }
        collectionsPreloadExecutor.execute {
            try {
                getCollections(accountId)
            } finally {
                preloadingCollections.remove(accountId)
            }
        }
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
            cachedNftCollections[accountId] = nftCollectionsArray
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
        if (WGlobalStorage.getAreUnverifiedNftsHidden() && getHasUnverifiedNft(accountId)) {
            return true
        }
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

    private fun getHasUnverifiedNft(accountId: String): Boolean {
        val nfts = if (nftData?.accountId == accountId) {
            nftData?.cachedNfts
        } else {
            fetchCachedNfts(accountId)
        }
        return nfts?.any { it.isUnverified == true } == true
    }

    private fun writeCollectionsToCache(
        accountId: String,
        collections: List<MCollectionTabToShow>
    ) {
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
            if (WGlobalStorage.getAccountTonAddress(accountId) == null) "[]" else null
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

    private fun List<ApiNft>?.hasHiddenNfts(): Boolean = this?.any { it.isHidden == true } == true

    private fun List<ApiNft>?.hasTelegramGifts(): Boolean = this?.any {
        it.isTelegramGift == true
    } == true
}
