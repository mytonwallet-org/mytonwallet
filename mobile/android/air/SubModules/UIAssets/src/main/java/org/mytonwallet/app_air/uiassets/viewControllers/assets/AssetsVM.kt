package org.mytonwallet.app_air.uiassets.viewControllers.assets

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.asCoroutineDispatcher
import kotlinx.coroutines.cancel
import kotlinx.coroutines.cancelChildren
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.mytonwallet.app_air.uiassets.models.ExpiringDomainsData
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.moshi.ApiNft
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import org.mytonwallet.app_air.walletcore.stores.NftStore
import java.lang.ref.WeakReference
import java.util.concurrent.Executors
import kotlin.math.ceil
import kotlin.time.Duration.Companion.days

class AssetsVM(
    private val viewMode: AssetsVC.ViewMode,
    val collectionMode: AssetsVC.CollectionMode?,
    var showingAccountId: String,
    delegate: Delegate
) : WalletCore.EventObserver {

    private companion object {
        const val NFT_DOMAIN_BADGE_DAYS_THRESHOLD = 30
        const val EXPIRING_DOMAINS_DAYS_THRESHOLD = 14
    }

    enum class InteractionMode { NORMAL, DRAG, SELECTION }

    interface Delegate {
        fun updateEmptyView()
        fun nftsUpdated(isFirstLoad: Boolean)
        fun nftsShown()
        fun checkExpiringDomainsWarning(animated: Boolean): Boolean
    }

    private val delegate: WeakReference<Delegate> = WeakReference(delegate)
    private val queueDispatcher =
        Executors.newSingleThreadExecutor().asCoroutineDispatcher()
    private val scope = CoroutineScope(SupervisorJob() + queueDispatcher)

    internal var nfts: MutableList<ApiNft>? = null
    var assetRows: List<AssetRow> = emptyList()
        private set
    var expiringDomainsData: ExpiringDomainsData? = null
        private set
    var interactionMode: InteractionMode = InteractionMode.NORMAL
        private set
    var cachedNftsToSave: MutableList<ApiNft>? = null
    var nftsShown = false
        private set
    var isViewOnlyAccount = AccountStore.accountById(showingAccountId)?.isViewOnly == true
        private set
    private val selectedAssets: MutableSet<String> = LinkedHashSet()
    private var animationsPaused: Boolean? = null
    private var expiringDomains: List<ApiNft> = emptyList()
    private var expiringDomainsRefreshJob: Job? = null

    val hasLoadedNfts: Boolean
        get() = nfts != null

    val isEmpty: Boolean
        get() = nfts?.isEmpty() == true

    val nftsCount: Int
        get() = nfts?.size ?: 0

    val thereAreMoreToShow: Boolean
        get() = nftsCount > 6

    fun configure(accountId: String) {
        scope.coroutineContext.cancelChildren()
        showingAccountId = accountId
        nftsShown = false
        nfts = null
        isViewOnlyAccount = AccountStore.accountById(accountId)?.isViewOnly == true
        assetRows = emptyList()
        expiringDomains = emptyList()
        expiringDomainsData = null
        expiringDomainsRefreshJob?.cancel()
        expiringDomainsRefreshJob = null
        interactionMode = InteractionMode.NORMAL
        selectedAssets.clear()
        cachedNftsToSave = null
        updateNfts(forceLoadNewAccount = true)
    }

    fun delegateIsReady() {
        WalletCore.registerObserver(this)
        updateNfts(forceLoadNewAccount = false)
    }

    fun onDestroy() {
        WalletCore.unregisterObserver(this)
        scope.cancel()
        queueDispatcher.close()
    }

    private fun updateNfts(forceLoadNewAccount: Boolean) {
        if (!forceLoadNewAccount && AccountStore.activeAccountId != showingAccountId)
            return

        val oldAddresses = nfts?.map { it.address }

        loadCachedNftsAsync(keepOrder = !forceLoadNewAccount) { isChanged ->
            if (isChanged) {
                delegate.get()?.updateEmptyView()
                delegate.get()?.nftsUpdated(isFirstLoad = oldAddresses == null)
            }
        }
    }

    fun loadCachedNftsAsync(
        keepOrder: Boolean,
        onFinished: ((Boolean) -> Unit)? = null
    ) {
        scope.launch {
            val nftData = NftStore.nftData
            val cachedNfts =
                if (nftData?.accountId == showingAccountId && nftData.cachedNfts != null)
                    nftData.cachedNfts
                else
                    NftStore.fetchCachedNfts(showingAccountId)
            val isChanged = applyCachedNfts(cachedNfts, keepOrder)

            withContext(Dispatchers.Main) {
                onFinished?.invoke(isChanged)
                if (!nftsShown) {
                    nftsShown = true
                    delegate.get()?.nftsShown()
                }
            }
        }
    }

    private fun applyCachedNfts(
        cachedNfts: List<ApiNft>?,
        keepOrder: Boolean
    ): Boolean {
        val oldNfts = nfts?.toList()

        if (keepOrder && interactionMode == InteractionMode.DRAG && cachedNftsToSave != null) {
            val oldOrder =
                cachedNftsToSave!!.mapIndexed { index, nft -> nft.address to index }.toMap()

            val updated = cachedNfts
                ?.filter {
                    !it.shouldHide() && when (collectionMode) {
                        is AssetsVC.CollectionMode.SingleCollection ->
                            it.collectionAddress == collectionMode.collection.address

                        is AssetsVC.CollectionMode.TelegramGifts ->
                            it.isTelegramGift == true

                        else -> true
                    }
                }
                ?: emptyList()

            cachedNftsToSave = cachedNfts
                ?.sortedWith(compareBy { oldOrder[it.address] ?: Int.MAX_VALUE })
                ?.toMutableList()

            nfts = updated
                .sortedWith(compareBy { oldOrder[it.address] ?: Int.MAX_VALUE })
                .toMutableList()
        } else {
            nfts = cachedNfts
                ?.filter {
                    !it.shouldHide() && when (collectionMode) {
                        is AssetsVC.CollectionMode.SingleCollection ->
                            it.collectionAddress == collectionMode.collection.address

                        is AssetsVC.CollectionMode.TelegramGifts ->
                            it.isTelegramGift == true

                        else -> true
                    }
                }
                ?.toMutableList()

            cachedNftsToSave = null
        }

        filterSelectedAssets()
        rebuildAssetRows()
        refreshExpiringDomainsData()

        return oldNfts != nfts
    }

    private fun rebuildAssetRows() {
        val visibleNfts = when (viewMode) {
            AssetsVC.ViewMode.COMPLETE -> nfts.orEmpty()
            AssetsVC.ViewMode.THUMB -> nfts.orEmpty().take(6)
        }
        val areAnimationsPaused = animationsPaused == false
        val expirationByAddress = NftStore.nftData?.expirationByAddress
        val nowMs = System.currentTimeMillis()
        val dayMs = 1.days.inWholeMilliseconds
        val expiryThresholdMs = nowMs + NFT_DOMAIN_BADGE_DAYS_THRESHOLD * dayMs
        assetRows = visibleNfts.map { nft ->
            val expMs = expirationByAddress?.get(nft.address)
            val daysUntilExpiration = if (expMs != null && expMs <= expiryThresholdMs) {
                ceil((expMs - nowMs).toDouble() / dayMs).toInt()
            } else null
            AssetRow(
                nft = nft,
                interactionMode = interactionMode,
                animationsPaused = areAnimationsPaused,
                isSelected = selectedAssets.contains(nft.address),
                daysUntilExpiration = daysUntilExpiration
            )
        }
    }

    private fun rebuildExpiringDomainsData(expirationByAddress: Map<String, Long>?) {
        if (isViewOnlyAccount || expirationByAddress == null) {
            expiringDomains = emptyList()
            expiringDomainsData = null
            return
        }

        val ignoredAddresses = NftStore.getIgnoredExpiringAddresses(showingAccountId)
        val nowMs = System.currentTimeMillis()
        val dayMs = 1.days.inWholeMilliseconds
        val thresholdMs = nowMs +
            EXPIRING_DOMAINS_DAYS_THRESHOLD.days.inWholeMilliseconds

        expiringDomains = nfts.orEmpty().filter { nft ->
            val expMs = expirationByAddress[nft.address] ?: return@filter false
            expMs <= thresholdMs && nft.address !in ignoredAddresses
        }

        expiringDomainsData = expiringDomains.takeIf { it.isNotEmpty() }?.let { domains ->
            ExpiringDomainsData(
                domainNfts = domains.take(3),
                count = domains.size,
                minDays = domains
                    .mapNotNull { nft -> expirationByAddress[nft.address] }
                    .minOfOrNull { expMs -> ceil((expMs - nowMs).toDouble() / dayMs).toInt() } ?: 0
            )
        }
    }

    private fun refreshExpiringDomainsData() {
        rebuildExpiringDomainsData(NftStore.nftData?.expirationByAddress)
    }

    private fun filterSelectedAssets() {
        val availableAddresses = nfts.orEmpty().mapTo(hashSetOf()) { it.address }
        selectedAssets.retainAll(availableAddresses)
    }

    private fun refreshExpiringDomainsWarningAsync() {
        expiringDomainsRefreshJob?.cancel()
        expiringDomainsRefreshJob = scope.launch {
            refreshExpiringDomainsData()
            withContext(Dispatchers.Main) {
                delegate.get()?.checkExpiringDomainsWarning(animated = true)
            }
        }
    }

    override fun onWalletEvent(walletEvent: WalletEvent) {
        when (walletEvent) {
            WalletEvent.NftsUpdated,
            WalletEvent.ReceivedNewNFT,
            WalletEvent.NftsReordered -> {
                updateNfts(forceLoadNewAccount = false)
            }

            WalletEvent.NftDomainDataUpdated -> {
                refreshExpiringDomainsWarningAsync()
            }

            is WalletEvent.NftDomainExpirationDismissed -> {
                if (walletEvent.accountId == showingAccountId) {
                    refreshExpiringDomainsWarningAsync()
                }
            }

            else -> {}
        }
    }

    fun moveItem(fromPosition: Int, toPosition: Int, shouldSave: Boolean) {
        nfts?.let { nftList ->
            if (fromPosition < nftList.size && toPosition < nftList.size) {

                if (cachedNftsToSave == null)
                    cachedNftsToSave =
                        NftStore.nftData?.cachedNfts?.toMutableList() ?: return

                val mainFromPos =
                    cachedNftsToSave!!
                        .indexOfFirst { it.address == nftList[fromPosition].address }
                val mainToPos =
                    cachedNftsToSave!!
                        .indexOfFirst { it.address == nftList[toPosition].address }

                val item = nftList.removeAt(fromPosition)
                nftList.add(toPosition, item)

                val mainItem = cachedNftsToSave!!.removeAt(mainFromPos)
                cachedNftsToSave!!.add(mainToPos, mainItem)

                rebuildAssetRows()

                if (shouldSave) saveList()
            }
        }
    }

    fun saveList() {
        if (AccountStore.activeAccountId != showingAccountId) return

        cachedNftsToSave?.let {
            NftStore.setNfts(
                chain = null,
                nfts = it,
                accountId = AccountStore.activeAccountId!!,
                notifyObservers = true,
                isReorder = true
            )
            cachedNftsToSave = null
        }
    }

    fun setAnimationsPaused(paused: Boolean): Boolean {
        if (animationsPaused == paused) {
            return false
        }
        animationsPaused = paused
        rebuildAssetRows()
        return true
    }

    fun startSorting() {
        if (interactionMode == InteractionMode.DRAG) return
        interactionMode = InteractionMode.DRAG
        rebuildAssetRows()
    }

    fun endSorting() {
        if (interactionMode != InteractionMode.DRAG) return
        interactionMode = InteractionMode.NORMAL
        rebuildAssetRows()
    }

    fun enterSelectionMode() {
        if (interactionMode == InteractionMode.SELECTION) return
        interactionMode = InteractionMode.SELECTION
        rebuildAssetRows()
    }

    fun exitSelectionMode() {
        interactionMode = InteractionMode.NORMAL
        clearSelection()
    }

    fun clearSelection() {
        selectedAssets.clear()
        rebuildAssetRows()
    }

    fun toggleSelection(address: String): Boolean {
        val isSelected = if (selectedAssets.contains(address)) {
            selectedAssets.remove(address)
            false
        } else {
            selectedAssets.add(address)
            true
        }
        rebuildAssetRows()
        return isSelected
    }

    fun selectAllVisible() {
        selectedAssets.addAll(assetRows.map { it.nft.address })
        rebuildAssetRows()
    }

    fun hasSelectedAssets(): Boolean {
        return selectedAssets.isNotEmpty()
    }

    fun selectedCount(): Int {
        return selectedAssets.size
    }

    fun getSelectedNfts(): List<ApiNft> {
        return nfts.orEmpty().filter { selectedAssets.contains(it.address) }
    }

    fun getSelectedAddresses(): Set<String> {
        return LinkedHashSet(selectedAssets)
    }

    fun setSelectedAddresses(addresses: Collection<String>) {
        selectedAssets.clear()
        selectedAssets.addAll(addresses)
        filterSelectedAssets()
        rebuildAssetRows()
    }

    fun getAllNfts(): MutableList<ApiNft>? {
        return nfts
    }

    fun firstExpiringDomain(): ApiNft? {
        return expiringDomains.firstOrNull()
    }

    fun ignoredExpiringDomainAddresses(): List<String> {
        return expiringDomains.map { it.address }
    }
}
