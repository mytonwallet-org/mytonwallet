package org.mytonwallet.app_air.walletcore.deeplink

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import org.mytonwallet.app_air.walletcontext.helpers.AddressHelpers
import org.mytonwallet.app_air.walletcontext.models.MBlockchainNetwork
import org.mytonwallet.app_air.walletcore.TRON_USDT_SLUG
import org.mytonwallet.app_air.walletcore.models.InAppBrowserConfig
import org.mytonwallet.app_air.walletcore.models.blockchain.MBlockchain
import java.net.URLDecoder

sealed class Deeplink {
    abstract val accountAddress: String?

    data class TonConnect2(override val accountAddress: String?, val requestUri: Uri) : Deeplink() {
        val isConnectRequest: Boolean
            get() {
                return !requestUri.getQueryParameter("r").isNullOrBlank()
            }
    }

    data class Invoice(
        override val accountAddress: String?,
        val address: String,
        val amount: String?,
        val binary: String?,
        val expiry: Long?,
        val init: String?,
        val jetton: String?,
        val comment: String?,
        val token: String?,
        val hasUnsupportedParams: Boolean
    ) : Deeplink()

    data class Swap(
        override val accountAddress: String?,
        val from: String?,
        val to: String?,
        val amountIn: Double?
    ) : Deeplink()

    data class Receive(override val accountAddress: String?) : Deeplink()
    data class BuyWithCard(override val accountAddress: String?) : Deeplink()
    data class Offramp(
        override val accountAddress: String?,
        val transactionId: String?,
        val baseCurrencyCode: String?,
        val baseCurrencyAmount: String?,
        val depositWalletAddress: String?,
        val depositWalletAddressTag: String?
    ) : Deeplink()

    data class Stake(override val accountAddress: String?) : Deeplink()
    data class Explore(
        override val accountAddress: String?,
        val targetUri: Uri?
    ) : Deeplink()

    data class Url(
        override val accountAddress: String?,
        val config: InAppBrowserConfig
    ) : Deeplink()

    data class Transaction(
        override val accountAddress: String?,
        val chain: String?,
        val txId: String?,
        val txHash: String?,
        val isPushNotification: Boolean
    ) : Deeplink()

    data class TokenBySlug(override val accountAddress: String?, val slug: String) : Deeplink()
    data class TokenByAddress(
        override val accountAddress: String?,
        val chain: String,
        val address: String
    ) : Deeplink()

    data class StakeTx(override val accountAddress: String?) : Deeplink()
    data class ExpiringDns(override val accountAddress: String?, val domainAddress: String) :
        Deeplink()

    data class WalletConnect(override val accountAddress: String?, val requestUri: Uri) : Deeplink()
    data class SwitchToLegacy(override val accountAddress: String?) : Deeplink()
    data class View(
        override val accountAddress: String?,
        val network: MBlockchainNetwork,
        val addressByChain: Map<String, String>
    ) : Deeplink()

    data class Nft(
        override val accountAddress: String?,
        val network: MBlockchainNetwork,
        val nftAddress: String
    ) : Deeplink()
}

interface DeeplinkNavigator {
    fun handle(deeplink: Deeplink)
}

class DeeplinkParser {

    companion object {
        fun parse(intent: Intent): Deeplink? {
            /*Logger.d(Logger.LogTag.DEEPLINK, "Data ${intent.data}")
            intent.extras?.keySet()?.forEach { key ->
                Logger.d(Logger.LogTag.DEEPLINK, "Extra $key: ${intent.extras?.getString(key, "")}")
            }*/
            return parse(intent.data) ?: parse(intent.extras)
        }

        fun parse(uri: Uri?): Deeplink? {
            if (uri == null)
                return null
            return when (uri.scheme) {
                "ton" -> handleTonInvoice(uri)
                "tc", "mytonwallet-tc" -> handleTonConnect(uri)
                "wc" -> handleWalletConnect(uri)
                "mtw" -> handleMTW(uri)
                "https" -> handleHttpsDeeplinks(uri)
                else -> {
                    null
                }
            }
        }

        private fun parse(bundle: Bundle?): Deeplink? {
            if (bundle == null)
                return null
            val address = bundle.getString("address") ?: return null
            return when (bundle.getString("action")) {
                "openUrl" -> {
                    val url = bundle.getString("url") ?: return null
                    Deeplink.Url(
                        address, InAppBrowserConfig(
                            url = url,
                            title = bundle.getString("title"),
                            injectDappConnect = true
                        )
                    )
                }

                "nativeTx", "swap", "jettonTx" -> {
                    val txId = bundle.getString("txId") ?: return null
                    val chain = bundle.getString("chain") ?: MBlockchain.ton.name
                    return Deeplink.Transaction(
                        accountAddress = address,
                        chain = chain,
                        txId = txId,
                        txHash = null,
                        isPushNotification = true
                    )
                }

                "staking" -> {
                    return Deeplink.StakeTx(accountAddress = address)
                }

                "expiringDns" -> {
                    val domainAddress = bundle.getString("domainAddress") ?: return null
                    return Deeplink.ExpiringDns(
                        accountAddress = address,
                        domainAddress = domainAddress
                    )
                }

                else -> {
                    return null
                }
            }
        }

        private fun handleTonConnect(uri: Uri): Deeplink {
            return Deeplink.TonConnect2(accountAddress = null, requestUri = uri)
        }

        private fun handleWalletConnect(uri: Uri): Deeplink {
            return Deeplink.WalletConnect(accountAddress = null, requestUri = uri)
        }

        private fun handleTonInvoice(uri: Uri): Deeplink? {
            val parsedWalletURL = parseWalletUrl(uri) ?: return null
            return Deeplink.Invoice(
                accountAddress = null,
                address = parsedWalletURL.address,
                amount = parsedWalletURL.amount,
                binary = parsedWalletURL.binary,
                comment = parsedWalletURL.comment,
                expiry = parsedWalletURL.expiry,
                init = parsedWalletURL.init,
                jetton = parsedWalletURL.jetton,
                token = parsedWalletURL.token,
                hasUnsupportedParams = parsedWalletURL.hasUnsupportedParams,
            )
        }

        private fun handleHttpsDeeplinks(uri: Uri): Deeplink? {
            when (uri.host) {
                "my.tt", "go.mytonwallet.org" -> {
                    val path = uri.path?.trimStart('/') ?: ""
                    val pathSegments = path.split('/')

                    val mtwUri = Uri.Builder()
                        .scheme("mtw")
                        .authority(pathSegments.firstOrNull() ?: "")
                        .apply {
                            if (pathSegments.size > 1) {
                                pathSegments.drop(1).forEach { segment ->
                                    appendPath(segment)
                                }
                            }
                        }
                        .encodedQuery(uri.encodedQuery)
                        .build()
                    return handleMTW(mtwUri)
                }

                "connect.mytonwallet.org" -> {
                    return handleTonConnect(uri)
                }

                "walletconnect.com" -> {
                    if (uri.path == "/wc") return handleWalletConnect(uri)
                }
            }
            return null
        }

        private fun handleMTW(uri: Uri): Deeplink? {
            return when (uri.host) {
                "swap", "buy-with-crypto" -> {
                    var from: String? = null
                    var to: String? = null
                    var amountIn: Double? = null

                    uri.query?.let { query ->
                        val components = URLDecoder.decode(query, "UTF-8").split("&").mapNotNull {
                            it.split("=")
                                .let { parts -> if (parts.size == 2) parts[0] to parts[1] else null }
                        }.toMap()

                        components["amountIn"]?.toDoubleOrNull()?.let { amountIn = it }
                        components["in"]?.let { from = it }
                        components["out"]?.let { to = it }
                    }

                    if (uri.host == "buy-with-crypto") {
                        if (to == null && from != "toncoin") to = "toncoin"
                        if (from == null) from = TRON_USDT_SLUG
                    }

                    Deeplink.Swap(accountAddress = null, from = from, to = to, amountIn = amountIn)
                }

                "transfer" -> handleTonInvoice(uri)
                "receive" -> Deeplink.Receive(accountAddress = null)
                "buy-with-card" -> Deeplink.BuyWithCard(accountAddress = null)
                "offramp" -> Deeplink.Offramp(
                    accountAddress = null,
                    transactionId = uri.getQueryParameter("transactionId"),
                    baseCurrencyCode = uri.getQueryParameter("baseCurrencyCode"),
                    baseCurrencyAmount = uri.getQueryParameter("baseCurrencyAmount"),
                    depositWalletAddress = uri.getQueryParameter("depositWalletAddress"),
                    depositWalletAddressTag = uri.getQueryParameter("depositWalletAddressTag")
                )

                "stake" -> Deeplink.Stake(accountAddress = null)
                "explore" -> Deeplink.Explore(
                    accountAddress = null,
                    targetUri = uri.extractSubUri()
                )

                "giveaway" -> {
                    val giveawayId = extractId(uri.toString(), "giveaway/([^/]+)")
                    val urlString =
                        "https://giveaway.mytonwallet.io/" + if (giveawayId != null) "?giveawayId=$giveawayId" else ""
                    val config = InAppBrowserConfig(
                        url = urlString,
                        title = "Giveaway",
                        injectDappConnect = true
                    )
                    Deeplink.Url(accountAddress = null, config)
                }

                "r" -> {
                    val rId = extractId(uri.toString(), "r/([^/]+)")
                    val urlString =
                        "https://checkin.mytonwallet.org/" + if (rId != null) "?r=$rId" else ""
                    val config = InAppBrowserConfig(
                        url = urlString,
                        title = "Checkin",
                        injectDappConnect = true
                    )
                    Deeplink.Url(accountAddress = null, config)
                }

                "classic" -> {
                    Deeplink.SwitchToLegacy(null)
                }

                "token" -> {
                    val pathParts = uri.pathSegments

                    if (pathParts.size > 1) {
                        val chain = pathParts[0]
                        val tokenAddress = pathParts[1]
                        return Deeplink.TokenByAddress(null, chain, tokenAddress)
                    } else {
                        pathParts.firstOrNull()?.let { tokenSlug ->
                            return Deeplink.TokenBySlug(null, tokenSlug)
                        }
                    }
                }

                "tx" -> {
                    val pathParts = uri.pathSegments

                    if (pathParts.size > 1) {
                        val chain = pathParts[0]
                        val txId = pathParts.drop(1).joinToString("/")
                        return Deeplink.Transaction(
                            accountAddress = null,
                            chain = chain,
                            txId = txId,
                            txHash = null,
                            isPushNotification = false,
                        )
                    } else {
                        return null
                    }
                }

                "view" -> {
                    val addressByChain = mutableMapOf<String, String>()
                    MBlockchain.supportedChainValues.forEach { chain ->
                        val address = uri.getQueryParameter(chain)
                        if (!address.isNullOrBlank()) {
                            val blockchain = MBlockchain.valueOf(chain)
                            if (blockchain.isValidAddress(address) || blockchain.isValidDNS(address)) {
                                addressByChain[chain] = address
                            }
                        }
                    }
                    val network =
                        if (uri.getQueryParameter("testnet") == "true") MBlockchainNetwork.TESTNET else MBlockchainNetwork.MAINNET
                    return Deeplink.View(
                        accountAddress = null,
                        network = network,
                        addressByChain = addressByChain
                    )
                }

                "nft" -> {
                    val nftAddress = uri.pathSegments.firstOrNull()?.takeIf { it.isNotBlank() } ?: return null
                    val network =
                        if (uri.getQueryParameter("testnet") == "true") MBlockchainNetwork.TESTNET else MBlockchainNetwork.MAINNET
                    return Deeplink.Nft(accountAddress = null, network = network, nftAddress = nftAddress)
                }

                else -> {
                    return null
                }
            }
        }

        private fun extractId(pathname: String, pattern: String): String? {
            val regex = Regex(pattern)
            val match = regex.find(pathname)
            return match?.groups?.get(1)?.value
        }
    }
}

fun Uri.extractSubUri(): Uri? {
    // use only host for now
    val targetHost = pathSegments.firstOrNull() ?: return null
    return Uri.Builder()
        .scheme("https")
        .authority(targetHost)
        .build()
}

fun parseWalletUrl(uri: Uri): ParsedWalletUrl? {
    if ((uri.scheme != "ton" && uri.scheme != "mtw") || uri.host != "transfer") {
        return null
    }

    val updatedUrl =
        uri.buildUpon().encodedPath(uri.encodedPath).encodedQuery(uri.encodedQuery).build()

    var address: String? = null
    val path = updatedUrl.path?.trim('/') ?: ""
    if (AddressHelpers.isValidAddress(path)) {
        address = path
    }

    var amount: String? = null
    var binary: String? = null
    var comment: String? = null
    var expiry: Long? = null
    var init: String? = null
    var jetton: String? = null
    var token: String? = null

    var hasUnsupportedParams = false

    updatedUrl.queryParameterNames.forEach { paramName ->
        val value = updatedUrl.getQueryParameter(paramName)
        if (!value.isNullOrEmpty()) {
            when (paramName) {
                "amount" -> amount = value
                "bin" -> binary = value
                "exp" -> try {
                    expiry = value.toLong()
                } catch (e: NumberFormatException) {
                    // Handle invalid amount format
                }

                "init" -> init = value
                "jetton" -> jetton = value
                "text" -> comment = value
                "token" -> token = value
                else -> hasUnsupportedParams = true
            }
        }
    }

    return ParsedWalletUrl(
        address = address ?: "",
        amount = amount,
        binary = binary,
        comment = comment,
        expiry = expiry,
        init = init,
        jetton = jetton,
        token = token,
        hasUnsupportedParams = hasUnsupportedParams
    )
}

data class ParsedWalletUrl(
    val address: String,
    val amount: String?,
    val binary: String?,
    val comment: String?,
    val expiry: Long?,
    val init: String?,
    val jetton: String?,
    val token: String?,
    val hasUnsupportedParams: Boolean
)
