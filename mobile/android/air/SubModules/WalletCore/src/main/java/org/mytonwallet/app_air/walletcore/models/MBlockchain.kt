package org.mytonwallet.app_air.walletcore.models

import android.graphics.Color
import com.squareup.moshi.JsonClass
import org.mytonwallet.app_air.icons.R
import org.mytonwallet.app_air.walletcontext.models.MBlockchainNetwork
import org.mytonwallet.app_air.walletcore.helpers.ExplorerHelpers
import java.math.BigDecimal

@JsonClass(generateAdapter = false)
enum class MBlockchain(
    val icon: Int,
    val nativeSlug: String,
    val displayName: String
) {
    ton(R.drawable.ic_blockchain_ton_128, "toncoin", "TON"),
    ethereum(R.drawable.ic_blockchain_ethereum_128, "eth", "Ethereum"),
    polkadot(R.drawable.ic_blockchain_polkadot_128, "dot", "Polkadot"),
    zcash(R.drawable.ic_blockchain_zcash_128, "zec", "Zcash"),
    internet_computer(R.drawable.ic_blockchain_internet_computer_40, "icp", "Internet Computer"),
    avalanche(R.drawable.ic_blockchain_avalanche_128, "avax", "Avalanche"),
    litecoin(R.drawable.ic_blockchain_litecoin_128, "ltc", "Litecoin"),
    cosmos(R.drawable.ic_blockchain_cosmos_128, "atom", "Cosmos"),
    ripple(R.drawable.ic_blockchain_ripple_128, "xrp", "Ripple"),
    ethereum_classic(R.drawable.ic_blockchain_ethereum_classic_128, "etc", "Ethereum Classic"),
    binance_smart_chain(R.drawable.ic_blockchain_bnb_128, "bsc", "Binance Smart Chain"),
    dash(R.drawable.ic_blockchain_dash_128, "dash", "Dash"),
    monero(R.drawable.ic_blockchain_monero_128, "xmr", "Monero"),
    tron(R.drawable.ic_blockchain_tron_40, "trx", "TRON"),
    cardano(R.drawable.ic_blockchain_cardano_128, "ada", "Cardano"),
    bitcoin(R.drawable.ic_blockchain_bitcoin_40, "btc", "Bitcoin"),
    eos(R.drawable.ic_blockchain_eos_128, "eos", "EOS"),
    bitcoin_cash(R.drawable.ic_blockchain_bitcoin_cash_128, "bch", "Bitcoin Cash"),
    solana(R.drawable.ic_blockchain_solana_40, "sol", "Solana"),
    doge(R.drawable.ic_blockchain_doge_128, "doge", "DOGE"),
    stellar(R.drawable.ic_blockchain_stellar_128, "xlm", "Stellar"),
    binance_dex(R.drawable.ic_blockchain_bnb_128, "bnb", "Binance Dex");

    data class Gas(
        val maxSwap: BigDecimal?,
        val maxTransfer: BigDecimal,
        val maxTransferToken: BigDecimal
    )

    val gas: Gas?
        get() = when (this) {
            ton -> Gas(
                maxSwap = BigDecimal("0.4"),
                maxTransfer = BigDecimal("0.015"),
                maxTransferToken = BigDecimal("0.06")
            )

            tron -> Gas(
                maxSwap = null,
                maxTransfer = BigDecimal("1"),
                maxTransferToken = BigDecimal("30")
            )

            else -> null
        }


    val symbolIcon: Int?
        get() {
            return when (this) {
                ton ->
                    return R.drawable.ic_symbol_ton

                tron ->
                    return R.drawable.ic_symbol_tron

                else ->
                    null
            }
        }

    val gradientColors: IntArray?
        get() {
            return when (this) {
                ton ->
                    return intArrayOf(
                        Color.parseColor("#2C95A9"),
                        Color.parseColor("#2A5BA5")
                    )

                tron ->
                    return intArrayOf(
                        Color.parseColor("#AC4338"),
                        Color.parseColor("#A42F5C")
                    )

                else ->
                    null
            }
        }

    val isCommentSupported: Boolean
        get() {
            return this == ton
        }

    fun explorerUrl(network: MBlockchainNetwork, address: String): String {
        val str: String
        when (this) {
            ton -> {
                val domain = ExplorerHelpers.tonScanUrl(network)
                str = "${domain}address/$address"
            }

            tron -> {
                val domain = ExplorerHelpers.tronScanUrl(network)
                str = "${domain}address/$address"
            }

            else -> {
                str = ""
            }
        }
        return str
    }

    fun isValidAddress(address: String): Boolean {
        return when (this) {
            ton -> Regex("""^([-\w_]{48}|0:[\da-fA-F]{64})$""").matches(address)
            tron -> Regex("""^T[1-9A-HJ-NP-Za-km-z]{33}$""").matches(address)

            else -> false
        }
    }

    fun isValidDNS(address: String): Boolean {
        return when (this) {
            ton -> {
                val dnsZones = listOf(
                    DnsZone(
                        suffixes = listOf("ton"),
                        baseFormat = Regex(
                            """^([-\da-z]+\.){0,2}[-\da-z]{4,126}$""",
                            RegexOption.IGNORE_CASE
                        )
                    ),
                    DnsZone(
                        suffixes = listOf("t.me"),
                        baseFormat = Regex(
                            """^([-\da-z]+\.){0,2}[-_\da-z]{4,32}$""",
                            RegexOption.IGNORE_CASE
                        )
                    ),
                    DnsZone(
                        suffixes = listOf("vip", "ton.vip", "vip.ton"),
                        baseFormat = Regex(
                            """^([-\da-z]+\.){0,2}[\da-z]{1,24}$""",
                            RegexOption.IGNORE_CASE
                        )
                    ),
                    DnsZone(
                        suffixes = listOf("gram"),
                        baseFormat = Regex(
                            """^([-\da-z]+\.){0,2}[-\da-z]{1,127}$""",
                            RegexOption.IGNORE_CASE
                        )
                    )
                )

                dnsZones.any { zone ->
                    zone.suffixes.reversed().any { suffix ->
                        if (!address.endsWith(".$suffix")) {
                            return@any false
                        }
                        val base = address.dropLast(suffix.length + 1)
                        zone.baseFormat.matches(base)
                    }
                }
            }

            else -> false
        }
    }

    fun idToTxHash(id: String?): String? {
        return when (this) {
            ton, tron -> {
                id?.split(":")?.firstOrNull()
            }

            else -> {
                null
            }
        }
    }

    private data class DnsZone(
        val suffixes: List<String>,
        val baseFormat: Regex
    )

    companion object {
        val supportedChains = listOf(ton, tron)
        val supportedChainValues = listOf("ton", "tron")

        fun isValidAddressOnAnyChain(address: String): Boolean {
            return supportedChains.any {
                it.isValidAddress(address)
            }
        }

        // Popular token order matching the TypeScript implementation
        val POPULAR_TOKEN_ORDER = listOf(
            "TON",
            "USD₮",
            "USDT",
            "BTC",
            "ETH",
            "jUSDT",
            "jWBTC"
        )

        val POPULAR_TOKEN_ORDER_MAP = POPULAR_TOKEN_ORDER.mapIndexed { index, symbol ->
            symbol to index
        }.toMap()
    }
}
