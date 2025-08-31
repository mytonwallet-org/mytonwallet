package org.mytonwallet.app_air.walletcore.helpers

import org.mytonwallet.app_air.walletcore.MAIN_NETWORK

class ExplorerHelpers {
    companion object {
        fun tonScanUrl(network: String): String {
            return if (network == MAIN_NETWORK) {
                "https://tonscan.org/"
            } else {
                "https://testnet.tonscan.org/"
            }
        }

        fun tronScanUrl(network: String): String {
            return if (network == MAIN_NETWORK) {
                "https://tronscan.org/#/"
            } else {
                "https://shasta.tronscan.org/#/"
            }
        }
    }
}
