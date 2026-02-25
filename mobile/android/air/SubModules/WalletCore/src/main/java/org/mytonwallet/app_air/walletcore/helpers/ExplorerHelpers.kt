package org.mytonwallet.app_air.walletcore.helpers

import android.net.Uri
import androidx.core.net.toUri
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.models.MBlockchainNetwork
import org.mytonwallet.app_air.walletcore.MTW_CARDS_COLLECTION
import org.mytonwallet.app_air.walletcore.models.IInAppBrowser
import org.mytonwallet.app_air.walletcore.models.InAppBrowserConfig
import org.mytonwallet.app_air.walletcore.models.blockchain.MBlockchain

class ExplorerHelpers {
    companion object {

        fun createAddressExplorerConfig(
            chain: MBlockchain,
            network: MBlockchainNetwork,
            address: String
        ): InAppBrowserConfig? {
            val explorers = chain.addressExplorers()
            val preferredExplorer = WGlobalStorage.getPreferredExplorer(chain.name)
            val selectedExplorer = explorers.firstOrNull { it.identifier == preferredExplorer }
                ?: explorers.firstOrNull() ?: return null
            val explorerOptions = explorers.map {
                InAppBrowserConfig.Option(
                    identifier = it.identifier,
                    title = it.title,
                    subtitle = it.addressUrl(network, address).toUri().host,
                    onClick = { vc ->
                        (vc.get() as? IInAppBrowser)?.navigate(it.addressUrl(network, address))
                        WGlobalStorage.setPreferredExplorer(chain.name, it.identifier)
                    }
                )
            }
            return InAppBrowserConfig(
                url = selectedExplorer.addressUrl(network, address),
                injectDappConnect = true,
                options = if (explorerOptions.size > 1) explorerOptions else null,
                selectedOption = selectedExplorer.identifier,
                optionsOnTitle = true
            )
        }

        fun createTransactionExplorerConfig(
            chain: MBlockchain,
            network: MBlockchainNetwork,
            txHash: String
        ): InAppBrowserConfig? {
            val explorers = chain.transactionExplorers()
            val preferredExplorer = WGlobalStorage.getPreferredExplorer(chain.name)
            val selectedExplorer = explorers.firstOrNull { it.identifier == preferredExplorer }
                ?: explorers.firstOrNull() ?: return null
            val explorerOptions = explorers.map {
                InAppBrowserConfig.Option(
                    identifier = it.identifier,
                    title = it.title,
                    subtitle = it.transactionUrl(network, txHash).toUri().host,
                    onClick = { vc ->
                        (vc.get() as? IInAppBrowser)?.navigate(it.transactionUrl(network, txHash))
                        WGlobalStorage.setPreferredExplorer(chain.name, it.identifier)
                    }
                )
            }
            return InAppBrowserConfig(
                url = selectedExplorer.transactionUrl(network, txHash),
                injectDappConnect = true,
                options = if (explorerOptions.size > 1) explorerOptions else null,
                selectedOption = selectedExplorer.identifier,
                optionsOnTitle = true
            )
        }

        fun mtwScanUrl(network: MBlockchainNetwork, uriBuilder: Uri.Builder): String {
            uriBuilder
                .scheme("https")
                .authority("my.tt")
            if (network == MBlockchainNetwork.TESTNET) {
                uriBuilder.appendQueryParameter("testnet", "true")
            }
            return uriBuilder.build().toString()
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
