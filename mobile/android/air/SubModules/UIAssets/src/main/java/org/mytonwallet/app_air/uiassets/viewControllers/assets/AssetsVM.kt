package org.mytonwallet.app_air.uiassets.viewControllers.assets

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.asCoroutineDispatcher
import kotlinx.coroutines.cancel
import kotlinx.coroutines.cancelChildren
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.moshi.ApiNft
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import org.mytonwallet.app_air.walletcore.stores.NftStore
import java.lang.ref.WeakReference
import java.util.concurrent.Executors

class AssetsVM(
    val collectionMode: AssetsVC.CollectionMode?,
    var showingAccountId: String,
    delegate: Delegate
) : WalletCore.EventObserver {

    interface Delegate {
        fun updateEmptyView()
        fun nftsUpdated()
        fun nftsShown()
    }

    private val delegate: WeakReference<Delegate> = WeakReference(delegate)
    private val queueDispatcher =
        Executors.newSingleThreadExecutor().asCoroutineDispatcher()
    private val scope = CoroutineScope(SupervisorJob() + queueDispatcher)

    internal var nfts: MutableList<ApiNft>? = null
    var isInDragMode = false
    var cachedNftsToSave: MutableList<ApiNft>? = null
    var nftsShown = false
        private set

    fun configure(accountId: String) {
        scope.coroutineContext.cancelChildren()
        showingAccountId = accountId
        nftsShown = false
        nfts = null
        updateNfts(forceLoadNewAccount = true)
    }

    fun delegateIsReady() {
        WalletCore.registerObserver(this)
        updateNfts(forceLoadNewAccount = false)
    }

    fun onDestroy() {
        scope.cancel()
        queueDispatcher.close()
    }

    private fun updateNfts(forceLoadNewAccount: Boolean) {
        if (!forceLoadNewAccount && AccountStore.activeAccountId != showingAccountId)
            return

        val oldAddresses = nfts?.map { it.address }

        loadCachedNftsAsync(keepOrder = !forceLoadNewAccount) {
            val newAddresses = nfts?.map { it.address }
            if (oldAddresses != newAddresses) {
                delegate.get()?.updateEmptyView()
                delegate.get()?.nftsUpdated()
            }
        }
    }

    fun loadCachedNftsAsync(
        keepOrder: Boolean,
        onFinished: (() -> Unit)? = null
    ) {
        scope.launch {
            val nftData = NftStore.nftData
            val cachedNfts =
                if (nftData?.accountId == showingAccountId && nftData.cachedNfts != null)
                    nftData.cachedNfts
                else
                    NftStore.fetchCachedNfts(showingAccountId)
            applyCachedNfts(cachedNfts, keepOrder)

            withContext(Dispatchers.Main) {
                onFinished?.invoke()
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

        if (keepOrder && isInDragMode && cachedNftsToSave != null) {
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

        return oldNfts != nfts
    }

    override fun onWalletEvent(walletEvent: WalletEvent) {
        when (walletEvent) {
            WalletEvent.NftsUpdated,
            WalletEvent.ReceivedNewNFT,
            WalletEvent.NftsReordered -> {
                updateNfts(forceLoadNewAccount = false)
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
}
