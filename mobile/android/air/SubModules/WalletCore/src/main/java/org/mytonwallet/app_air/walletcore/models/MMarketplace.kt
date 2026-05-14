package org.mytonwallet.app_air.walletcore.models

import android.net.Uri
import org.mytonwallet.app_air.walletcontext.models.MBlockchainNetwork

sealed class MMarketplace(
    val title: String,
) {
    abstract fun homeUrl(network: MBlockchainNetwork = MBlockchainNetwork.MAINNET): String

    object Fragment : MMarketplace(
        title = "Fragment",
    ), GiftsMarket {
        override fun homeUrl(network: MBlockchainNetwork): String = "https://fragment.com/"

        override fun giftsUrl(network: MBlockchainNetwork): String = "${homeUrl(network)}gifts"

        fun numberUrl(number: String): String = "${homeUrl()}number/$number"

        fun usernameUrl(username: String): String = "${homeUrl()}username/${Uri.encode(username)}"
    }

    object Getgems : MMarketplace(
        title = "Getgems",
    ), GiftsMarket, CollectionMarket, NftMarket {
        override fun homeUrl(network: MBlockchainNetwork): String {
            return if (network.isMainnet) {
                "https://getgems.io/"
            } else {
                "https://testnet.getgems.io/"
            }
        }

        override fun giftsUrl(network: MBlockchainNetwork): String = "${homeUrl(network)}top-gifts"

        override fun collectionUrl(
            collectionAddress: String,
            network: MBlockchainNetwork
        ): String = "${homeUrl(network)}collection/$collectionAddress"

        override fun nftUrl(
            collectionAddress: String,
            nftAddress: String,
            network: MBlockchainNetwork
        ): String = "${collectionUrl(collectionAddress, network)}/$nftAddress"
    }

    object OpenSea : MMarketplace(
        title = "OpenSea",
    ) {
        override fun homeUrl(network: MBlockchainNetwork): String = "https://opensea.io/"
    }

    companion object {
        fun defaultForEmptyAssets(account: MAccount, isGramWallet: Boolean): MMarketplace {
            return if (!isGramWallet && account.isMultichain) OpenSea else Fragment
        }
    }
}

interface GiftsMarket {
    fun giftsUrl(network: MBlockchainNetwork = MBlockchainNetwork.MAINNET): String
}

interface CollectionMarket {
    fun collectionUrl(
        collectionAddress: String,
        network: MBlockchainNetwork = MBlockchainNetwork.MAINNET
    ): String
}

interface NftMarket {
    fun nftUrl(
        collectionAddress: String,
        nftAddress: String,
        network: MBlockchainNetwork = MBlockchainNetwork.MAINNET
    ): String
}
