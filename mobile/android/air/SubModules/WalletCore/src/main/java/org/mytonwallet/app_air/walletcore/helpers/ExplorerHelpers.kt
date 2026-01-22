package org.mytonwallet.app_air.walletcore.helpers

import org.mytonwallet.app_air.walletcontext.models.MBlockchainNetwork
import org.mytonwallet.app_air.walletcore.MTW_CARDS_COLLECTION

class ExplorerHelpers {
    companion object {
        fun tonScanUrl(network: MBlockchainNetwork): String {
            return if (network == MBlockchainNetwork.MAINNET) {
                "https://tonscan.org/"
            } else {
                "https://testnet.tonscan.org/"
            }
        }

        fun tronScanUrl(network: MBlockchainNetwork): String {
            return if (network == MBlockchainNetwork.MAINNET) {
                "https://tronscan.org/#/"
            } else {
                "https://shasta.tronscan.org/#/"
            }
        }

        fun getgemsUrl(network: MBlockchainNetwork): String {
            return if (network == MBlockchainNetwork.MAINNET) {
                "https://getgems.io/"
            } else {
                "https://testnet.getgems.io/"
            }
        }

        fun getMtwCardsUrl(network: MBlockchainNetwork): String {
            return "${getgemsUrl(network)}collection/$MTW_CARDS_COLLECTION"
        }
    }
}
