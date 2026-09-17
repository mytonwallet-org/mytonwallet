package org.mytonwallet.app_air.walletcore.models.blockchain

import android.net.Uri
import com.squareup.moshi.JsonClass
import org.mytonwallet.app_air.walletcontext.models.MBlockchainNetwork

@JsonClass(generateAdapter = false)
enum class MBlockchainExplorer(val identifier: String) {
    TONSCAN("tonscan"),
    TONVIEWER("tonviewer"),
    TRONSCAN("tronscan"),
    SOLSCAN("solscan"),
    MEMPOOL("mempool"),
    BLOCKCHAIR_LITECOIN("blockchair"),
    BLOCKCHAIR_BITCOINCASH("blockchair"),
    BLOCKCHAIR_DOGECOIN("blockchair"),
    ETHERSCAN("etherscan"),
    BASESCAN("basescan"),
    BSCTRACE("bsctrace"),
    POLYGONSCAN("polygonscan"),
    ARBISCAN("arbiscan"),
    MONADSCAN("monadscan"),
    SNOWTRACE("snowtrace"),
    HYPEREVMSCAN("hyperevmscan"),
    ROBINSCAN("robinscan"),
    ARCSCAN("arcscan");

    val title: String
        get() {
            return when (this) {
                TONSCAN -> "Tonscan"

                TONVIEWER -> "Tonviewer"

                TRONSCAN -> "Tronscan"

                SOLSCAN -> "Solscan"

                MEMPOOL -> "Mempool"

                BLOCKCHAIR_LITECOIN, BLOCKCHAIR_BITCOINCASH, BLOCKCHAIR_DOGECOIN ->
                    "Blockchair"

                ETHERSCAN -> "Etherscan"

                BASESCAN -> "BaseScan"

                BSCTRACE -> "BSCTrace"

                POLYGONSCAN -> "Polygonscan"

                ARBISCAN -> "Arbiscan"

                MONADSCAN -> "Monadscan"

                SNOWTRACE -> "Snowtrace"

                HYPEREVMSCAN -> "Hyperevmscan"

                ROBINSCAN -> "Robinscan"

                ARCSCAN -> "Arcscan"
            }
        }

    private val isEvm: Boolean
        get() = this in setOf(
            ETHERSCAN, BASESCAN, BSCTRACE, POLYGONSCAN, ARBISCAN, MONADSCAN, SNOWTRACE,
            HYPEREVMSCAN, ROBINSCAN, ARCSCAN
        )

    private val isUtxo: Boolean
        get() = this in setOf(
            MEMPOOL,
            BLOCKCHAIR_LITECOIN,
            BLOCKCHAIR_BITCOINCASH,
            BLOCKCHAIR_DOGECOIN
        )

    private fun blockchairBaseUrlBuilder(network: MBlockchainNetwork, chainPath: String) =
        Uri.Builder()
            .scheme("https")
            .authority("blockchair.com")
            .appendPath(chainPath)
            .apply {
                if (network.isTestnet) {
                    appendPath("testnet")
                }
            }

    private fun baseUrlBuilder(network: MBlockchainNetwork): Uri.Builder = when (this) {
        TONSCAN -> Uri.Builder()
            .scheme("https")
            .authority(if (network.isMainnet) "tonscan.org" else "testnet.tonscan.org")

        TONVIEWER -> Uri.Builder()
            .scheme("https")
            .authority(if (network.isMainnet) "tonviewer.com" else "testnet.tonviewer.com")

        TRONSCAN -> Uri.Builder()
            .scheme("https")
            .authority(if (network.isMainnet) "tronscan.org" else "shasta.tronscan.org")

        SOLSCAN -> Uri.Builder()
            .scheme("https")
            .authority("solscan.io").apply {
                if (!network.isMainnet) appendQueryParameter("cluster", "devnet")
            }

        MEMPOOL -> Uri.Builder()
            .scheme("https")
            .authority("mempool.space").apply {
                if (network.isTestnet) {
                    appendPath("testnet")
                }
            }

        BLOCKCHAIR_LITECOIN -> blockchairBaseUrlBuilder(network, "litecoin")

        BLOCKCHAIR_BITCOINCASH -> blockchairBaseUrlBuilder(network, "bitcoin-cash")

        BLOCKCHAIR_DOGECOIN -> blockchairBaseUrlBuilder(network, "dogecoin")

        ETHERSCAN -> Uri.Builder()
            .scheme("https")
            .authority(if (network.isMainnet) "etherscan.io" else "sepolia.etherscan.io")

        BASESCAN -> Uri.Builder()
            .scheme("https")
            .authority(if (network.isMainnet) "basescan.org" else "sepolia.basescan.org")

        BSCTRACE -> Uri.Builder()
            .scheme("https")
            .authority(if (network.isMainnet) "bscscan.com" else "testnet.bscscan.com")

        POLYGONSCAN -> Uri.Builder()
            .scheme("https")
            .authority(if (network.isMainnet) "polygonscan.com" else "testnet.polygonscan.com")

        ARBISCAN -> Uri.Builder()
            .scheme("https")
            .authority(if (network.isMainnet) "arbiscan.io" else "sepolia.arbiscan.io")

        MONADSCAN -> Uri.Builder()
            .scheme("https")
            .authority(if (network.isMainnet) "monadscan.com" else "testnet.monadscan.com")

        SNOWTRACE -> Uri.Builder()
            .scheme("https")
            .authority(if (network.isMainnet) "snowtrace.io" else "testnet.snowtrace.io")

        HYPEREVMSCAN -> Uri.Builder()
            .scheme("https")
            .authority("hyperevmscan.io")

        ROBINSCAN -> Uri.Builder()
            .scheme("https")
            .authority("robinscan.io")

        ARCSCAN -> Uri.Builder()
            .scheme("https")
            .authority(if (network.isMainnet) "arc-scan.org" else "testnet.arc-scan.org")
    }

    fun transactionUrl(network: MBlockchainNetwork, txHash: String): String = when (this) {
        TONSCAN -> baseUrlBuilder(network)
            .appendPath("tx")
            .appendPath(txHash)
            .build().toString()

        TONVIEWER -> baseUrlBuilder(network)
            .appendPath("transaction")
            .appendPath(txHash)
            .build().toString()

        TRONSCAN -> baseUrlBuilder(network)
            .appendEncodedPath("#/transaction")
            .appendPath(txHash)
            .build().toString()

        SOLSCAN -> baseUrlBuilder(network)
            .appendPath("tx")
            .appendPath(txHash)
            .build().toString()

        BLOCKCHAIR_LITECOIN, BLOCKCHAIR_BITCOINCASH, BLOCKCHAIR_DOGECOIN ->
            baseUrlBuilder(network)
                .appendPath("transaction")
                .appendPath(txHash)
                .build().toString()

        else -> baseUrlBuilder(network)
            .appendPath("tx")
            .appendPath(txHash)
            .build().toString()
    }

    fun addressUrl(network: MBlockchainNetwork, address: String): String = when (this) {
        TONSCAN -> baseUrlBuilder(network)
            .appendPath("address")
            .appendPath(address)
            .build().toString()

        TONVIEWER -> baseUrlBuilder(network)
            .appendPath(address)
            .build().toString()

        TRONSCAN -> baseUrlBuilder(network)
            .appendEncodedPath("#/address")
            .appendPath(address)
            .build().toString()

        SOLSCAN -> baseUrlBuilder(network)
            .appendPath("account")
            .appendPath(address)
            .build().toString()

        else -> baseUrlBuilder(network)
            .appendPath("address")
            .appendPath(address)
            .build().toString()
    }

    fun tokenUrl(network: MBlockchainNetwork, tokenAddress: String): String? = when (this) {
        TONSCAN -> baseUrlBuilder(network)
            .appendPath("jetton")
            .appendPath(tokenAddress)
            .build().toString()

        TRONSCAN -> baseUrlBuilder(network)
            .appendEncodedPath("#/token20")
            .appendPath(tokenAddress)
            .build().toString()

        SOLSCAN -> baseUrlBuilder(network)
            .appendPath("token")
            .appendPath(tokenAddress)
            .build().toString()

        else -> when {
            isEvm -> baseUrlBuilder(network)
                .appendPath("token")
                .appendPath(tokenAddress)
                .build().toString()

            isUtxo -> addressUrl(network, tokenAddress)

            else -> null
        }
    }

    fun nftUrl(network: MBlockchainNetwork, nftAddress: String): String? = when (this) {
        TONSCAN -> baseUrlBuilder(network)
            .appendPath("nft")
            .appendPath(nftAddress)
            .build().toString()

        else -> if (isEvm) {
            baseUrlBuilder(network)
                .appendPath("nft")
                .appendPath(nftAddress)
                .build().toString()
        } else {
            null
        }
    }
}
