package org.mytonwallet.app_air.walletcore.models.blockchain

import com.squareup.moshi.JsonClass
import org.mytonwallet.app_air.icons.R
import java.math.BigDecimal

@Suppress("EnumEntryName")
@JsonClass(generateAdapter = false)
enum class MBlockchain(
    val icon: Int,
    val nativeSlug: String,
    val displayName: String,
    internal val config: MBlockchainConfig? = null,
    val isSupported: Boolean = false
) {

    ton(
        R.drawable.ic_blockchain_ton_128,
        "toncoin",
        "TON",
        TonConfig,
        isSupported = true
    ),

    tron(
        R.drawable.ic_blockchain_tron_40,
        "trx",
        "TRON",
        TronConfig,
        isSupported = true
    ),

    solana(
        R.drawable.ic_blockchain_solana_40,
        "sol",
        "Solana",
        SolanaConfig,
        isSupported = true
    ),

    // unsupported examples (data only, no config yet)
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
    cardano(R.drawable.ic_blockchain_cardano_128, "ada", "Cardano"),
    bitcoin(R.drawable.ic_blockchain_bitcoin_40, "btc", "Bitcoin"),
    eos(R.drawable.ic_blockchain_eos_128, "eos", "EOS"),
    bitcoin_cash(R.drawable.ic_blockchain_bitcoin_cash_128, "bch", "Bitcoin Cash"),
    doge(R.drawable.ic_blockchain_doge_128, "doge", "DOGE"),
    stellar(R.drawable.ic_blockchain_stellar_128, "xlm", "Stellar"),
    binance_dex(R.drawable.ic_blockchain_bnb_128, "bnb", "Binance Dex");

    data class Gas(
        val maxSwap: BigDecimal?,
        val maxTransfer: BigDecimal,
        val maxTransferToken: BigDecimal
    )

    val gas get() = config?.gas
    val symbolIcon get() = config?.symbolIcon
    val symbolIconPadded get() = config?.symbolIconPadded
    val receiveOrnamentImage get() = config?.receiveOrnamentImage
    val qrGradientColors get() = config?.qrGradientColors
    val feeCheckAddress get() = config?.feeCheckAddress
    val isCommentSupported get() = config?.isCommentSupported
    val isEncryptedCommentSupported get() = config?.isEncryptedCommentSupported

    fun isValidAddress(address: String) =
        config?.isValidAddress(address) ?: false

    fun isValidDNS(address: String) =
        config?.isValidDNS(address) ?: false

    fun idToTxHash(id: String?) =
        config?.idToTxHash(id)

    fun transactionExplorers() =
        config?.transactionExplorers() ?: emptyList()

    fun addressExplorers() =
        config?.addressExplorers() ?: emptyList()

    fun tokenExplorer() =
        config?.tokenExplorer()

    fun nftExplorer() =
        config?.nftExplorer()

    val canBuyWithCard get() = config?.canBuyWithCard ?: true

    val burnAddress: String
        get() {
            return config?.burnAddress ?: ""
        }

    companion object {

        val supportedChains = entries.filter { it.isSupported }
        val supportedChainValues = supportedChains.map { it.name }
        val supportedChainIndexes =
            supportedChains.mapIndexed { index, chain -> chain.name to index }.toMap()

        fun isValidAddressOnAnyChain(address: String): Boolean =
            supportedChains.any { it.isValidAddress(address) }

        fun valueOfOrNull(name: String): MBlockchain? =
            entries.firstOrNull { it.name == name }

        val POPULAR_TOKEN_ORDER = listOf(
            "TON", "USD₮", "USDT", "BTC", "ETH", "jUSDT", "jWBTC"
        )

        val POPULAR_TOKEN_ORDER_MAP =
            POPULAR_TOKEN_ORDER.mapIndexed { i, s -> s to i }.toMap()
    }
}
