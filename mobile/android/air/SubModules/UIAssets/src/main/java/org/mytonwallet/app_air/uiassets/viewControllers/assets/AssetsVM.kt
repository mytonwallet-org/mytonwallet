package org.mytonwallet.app_air.uiassets.viewControllers.assets

import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.moshi.ApiNft
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import org.mytonwallet.app_air.walletcore.stores.NftStore
import java.lang.ref.WeakReference

class AssetsVM(val collectionMode: AssetsVC.CollectionMode?, delegate: Delegate) :
    WalletCore.EventObserver {
    interface Delegate {
        fun updateEmptyView()
        fun nftsUpdated()
    }

    private val delegate: WeakReference<Delegate> = WeakReference(delegate)

    internal var nfts: MutableList<ApiNft>? = null

    fun delegateIsReady() {
        WalletCore.registerObserver(this)
        updateNftsArray()
    }

    private fun updateNfts() {
        val oldNftsAddresses = nfts?.map { it.address }
        updateNftsArray()
        val newNftsAddresses = nfts?.map { it.address }

        if (oldNftsAddresses != newNftsAddresses) {
            delegate.get()?.updateEmptyView()
            delegate.get()?.nftsUpdated()
        }
    }

    private fun updateNftsArray() {
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

    fun moveItem(fromPosition: Int, toPosition: Int) {
        nfts?.let { nftList ->
            if (fromPosition < nftList.size && toPosition < nftList.size) {
                val cachedNfts = NftStore.nftData?.cachedNfts ?: return

                val mainFromPos =
                    cachedNfts.indexOfFirst { it.address == nftList[fromPosition].address }
                val mainToPos =
                    cachedNfts.indexOfFirst { it.address == nftList[toPosition].address }

                val item = nftList.removeAt(fromPosition)
                nftList.add(toPosition, item)

                val mainItem = cachedNfts.removeAt(mainFromPos)
                cachedNfts.add(mainToPos, mainItem)
                NftStore.setNfts(
                    cachedNfts,
                    accountId = AccountStore.activeAccountId!!,
                    notifyObservers = true,
                    isReorder = true
                )
            }
        }
    }
}
