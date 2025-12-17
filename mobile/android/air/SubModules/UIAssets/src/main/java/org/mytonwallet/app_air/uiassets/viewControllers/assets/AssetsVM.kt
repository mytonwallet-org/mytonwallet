package org.mytonwallet.app_air.uiassets.viewControllers.assets

import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.models.MScreenMode
import org.mytonwallet.app_air.walletcore.moshi.ApiNft
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import org.mytonwallet.app_air.walletcore.stores.NftStore
import java.lang.ref.WeakReference

class AssetsVM(
    val collectionMode: AssetsVC.CollectionMode?,
    private val screenMode: MScreenMode,
    delegate: Delegate
) :
    WalletCore.EventObserver {
    interface Delegate {
        fun updateEmptyView()
        fun nftsUpdated()
    }

    private val delegate: WeakReference<Delegate> = WeakReference(delegate)

    internal var nfts: MutableList<ApiNft>? = null
    var isInDragMode = false

    fun delegateIsReady() {
        WalletCore.registerObserver(this)
        updateNftsArray()
    }

    private fun updateNfts() {
        when (screenMode) {
            MScreenMode.Default -> {
                if (AccountStore.isPushedTemporary)
                    return
            }

            is MScreenMode.SingleWallet -> {
                if (AccountStore.activeAccountId != screenMode.accountId)
                    return
            }
        }

        val oldNftsAddresses = nfts?.map { it.address }
        updateNftsArray()
        val newNftsAddresses = nfts?.map { it.address }

        if (oldNftsAddresses != newNftsAddresses) {
            delegate.get()?.updateEmptyView()
            delegate.get()?.nftsUpdated()
        }
    }

    fun updateNftsArray(keepOrder: Boolean = true): Boolean {
        val oldNfts = nfts?.toList()

        if (keepOrder && isInDragMode && cachedNftsToSave != null) {
            val oldOrder =
                cachedNftsToSave!!.mapIndexed { index, nft -> nft.address to index }.toMap()

            val updated = NftStore.nftData?.cachedNfts?.filter {
                !it.shouldHide() && when (collectionMode) {
                    is AssetsVC.CollectionMode.SingleCollection -> {
                        it.collectionAddress == collectionMode.collection.address
                    }

                    is AssetsVC.CollectionMode.TelegramGifts -> {
                        it.isTelegramGift == true
                    }

                    else -> true
                }
            } ?: emptyList()

            cachedNftsToSave = NftStore.nftData?.cachedNfts?.sortedWith(
                compareBy { oldOrder[it.address] ?: Int.MAX_VALUE }
            )?.toMutableList()
            nfts = updated.sortedWith(
                compareBy { oldOrder[it.address] ?: Int.MAX_VALUE }
            ).toMutableList()
        } else {
            nfts = NftStore.nftData?.cachedNfts?.filter {
                !it.shouldHide() && when (collectionMode) {
                    is AssetsVC.CollectionMode.SingleCollection -> {
                        it.collectionAddress == collectionMode.collection.address
                    }

                    is AssetsVC.CollectionMode.TelegramGifts -> {
                        it.isTelegramGift == true
                    }

                    else -> {
                        true
                    }
                }
            }?.toMutableList()
            cachedNftsToSave = null
        }

        return oldNfts != nfts
    }

    override fun onWalletEvent(walletEvent: WalletEvent) {
        when (walletEvent) {
            WalletEvent.NftsUpdated, WalletEvent.ReceivedNewNFT, WalletEvent.NftsReordered -> {
                updateNfts()
            }

            is WalletEvent.AccountChanged -> {
                updateNfts()
            }

            else -> {}
        }
    }

    var cachedNftsToSave: MutableList<ApiNft>? = null
    fun moveItem(fromPosition: Int, toPosition: Int, shouldSave: Boolean) {
        nfts?.let { nftList ->
            if (fromPosition < nftList.size && toPosition < nftList.size) {
                if (cachedNftsToSave == null)
                    cachedNftsToSave = NftStore.nftData?.cachedNfts?.toMutableList() ?: return

                val mainFromPos =
                    cachedNftsToSave!!.indexOfFirst { it.address == nftList[fromPosition].address }
                val mainToPos =
                    cachedNftsToSave!!.indexOfFirst { it.address == nftList[toPosition].address }

                val item = nftList.removeAt(fromPosition)
                nftList.add(toPosition, item)

                val mainItem = cachedNftsToSave!!.removeAt(mainFromPos)
                cachedNftsToSave?.add(mainToPos, mainItem)
                if (shouldSave) {
                    saveList()
                }
            }
        }
    }

    fun saveList() {
        cachedNftsToSave?.let {
            NftStore.setNfts(
                cachedNftsToSave,
                accountId = AccountStore.activeAccountId!!,
                notifyObservers = true,
                isReorder = true
            )
            cachedNftsToSave = null
        }
    }
}
