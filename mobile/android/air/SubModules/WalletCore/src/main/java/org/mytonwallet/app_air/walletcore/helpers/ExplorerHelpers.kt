package org.mytonwallet.app_air.walletcore.helpers

import android.net.Uri
import androidx.core.net.toUri
import org.mytonwallet.app_air.walletbasecontext.utils.ApplicationContextHolder
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.models.MBlockchainNetwork
import org.mytonwallet.app_air.walletcore.MTW_CARDS_COLLECTION
import org.mytonwallet.app_air.walletcore.models.IInAppBrowser
import org.mytonwallet.app_air.walletcore.models.InAppBrowserConfig
import org.mytonwallet.app_air.walletcore.models.MAccount
import org.mytonwallet.app_air.walletcore.models.MMarketplace
import org.mytonwallet.app_air.walletcore.models.blockchain.MBlockchain
import org.mytonwallet.app_air.walletcore.models.blockchain.MBlockchainExplorer

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
            txHash: String,
            isTraceId: Boolean
        ): InAppBrowserConfig? {
            val explorers = transactionExplorers(chain, isTraceId)
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

        // A hash other than the trace ID may name the external message of a TON trace, which only some explorers find
        fun transactionExplorers(
            chain: MBlockchain,
            isTraceId: Boolean
        ): List<MBlockchainExplorer> {
            val explorers = chain.transactionExplorers()
            if (isTraceId) return explorers
            return explorers.filter { it.isMessageHashSupported }.ifEmpty { explorers }
        }

        fun mtwScanUrl(network: MBlockchainNetwork, uriBuilder: Uri.Builder): String {
            uriBuilder
                .scheme("https")
                .authority(ApplicationContextHolder.universalShortUrlHost)
            if (network.isTestnet) {
                uriBuilder.appendQueryParameter("testnet", "true")
            }
            return uriBuilder.build().toString()
        }

        fun buildAgentNewsShareUrl(eventId: Int, locale: String): String {
            val language = if (locale.startsWith("ru")) "ru" else "en"
            return "https://${ApplicationContextHolder.universalShortUrlHost}/agent" +
                "?news=$eventId&lang=$language&utm_source=pulse_share"
        }

        fun getgemsUrl(network: MBlockchainNetwork): String = MMarketplace.Getgems.homeUrl(network)

        fun getMtwCardsUrl(network: MBlockchainNetwork): String =
            "${getgemsUrl(network)}collection/$MTW_CARDS_COLLECTION"

        fun defaultNftMarketplace(account: MAccount): MMarketplace =
            MMarketplace.defaultForEmptyAssets(
                account = account,
                isGramWallet = ApplicationContextHolder.isGramApp
            )
    }
}
