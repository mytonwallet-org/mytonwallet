package org.mytonwallet.app_air.walletcore.models

import android.net.Uri
import com.squareup.moshi.JsonClass
import org.mytonwallet.app_air.walletcontext.models.MBlockchainNetwork

@JsonClass(generateAdapter = false)
enum class MBlockchainExplorer(val identifier: String) {
    TONSCAN("tonscan"),
    TONVIEWER("tonviewer"),
    TRONSCAN("tronscan");

    val title: String
        get() {
            return when (this) {
                TONSCAN -> "Tonscan"
                TONVIEWER -> "Tonviewer"
                TRONSCAN -> "Tronscan"
            }
        }

    private fun baseUrlBuilder(network: MBlockchainNetwork): Uri.Builder {
        return when (this) {
            TONSCAN -> Uri.Builder()
                .scheme("https")
                .authority(if (network == MBlockchainNetwork.MAINNET) "tonscan.org" else "testnet.tonscan.org")

            TONVIEWER -> Uri.Builder()
                .scheme("https")
                .authority(if (network == MBlockchainNetwork.MAINNET) "tonviewer.com" else "testnet.tonviewer.com")

            TRONSCAN -> Uri.Builder()
                .scheme("https")
                .authority(if (network == MBlockchainNetwork.MAINNET) "tronscan.org" else "shasta.tronscan.org")
        }
    }

    fun transactionUrl(network: MBlockchainNetwork, txHash: String): String {
        return when (this) {
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
        }
    }

    fun addressUrl(network: MBlockchainNetwork, address: String): String {
        return when (this) {
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
        }
    }

    fun tokenUrl(network: MBlockchainNetwork, tokenAddress: String): String? {
        return when (this) {
            TONSCAN -> baseUrlBuilder(network)
                .appendPath("jetton")
                .appendPath(tokenAddress)
                .build().toString()

            TRONSCAN -> baseUrlBuilder(network)
                .appendEncodedPath("#/token20")
                .appendPath(tokenAddress)
                .build().toString()

            else -> null
        }
    }
}
