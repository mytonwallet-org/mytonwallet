package org.mytonwallet.app_air.walletcore.models.blockchain

private class UtxoConfig(
    override val symbolIcon: Int,
    override val symbolIconPadded: Int,
    override val receiveOrnamentImage: Int,
    displayColor: String,
    override val feeCheckAddress: String,
    override val defaultDerivationPath: String,
    private val addressRegex: Regex,
    private val explorer: MBlockchainExplorer
) : MBlockchainConfig {

    override val gas = null
    override val qrIcon = null
    override val qrGradientColors = null
    override val displayColor = displayColor.hexToColorInt()

    override val isCommentSupported = false
    override val isEncryptedCommentSupported = false

    override val burnAddress = null
    override val multiWalletSupport = MultiWalletSupport.PATH

    override fun isValidAddress(address: String) = addressRegex.matches(address)

    override fun idToTxHash(id: String?) = id?.substringBefore(":")

    override fun transactionExplorers() = listOf(explorer)

    override fun addressExplorers() = listOf(explorer)

    override fun tokenExplorer() = explorer

    override fun nftExplorer() = null
}

object BitcoinConfig : MBlockchainConfig by UtxoConfig(
    symbolIcon = org.mytonwallet.app_air.icons.R.drawable.ic_symbol_bitcoin,
    symbolIconPadded = org.mytonwallet.app_air.icons.R.drawable.ic_symbol_bitcoin_15,
    receiveOrnamentImage =
        org.mytonwallet.app_air.icons.R.drawable.receive_ornament_bitcoin_light,
    displayColor = "#F7931A",
    feeCheckAddress = "bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq",
    defaultDerivationPath = "m/86'/0'/0'/0/{index}",
    addressRegex =
        Regex("""^(?:bc1|tb1)[a-z0-9]{25,62}$|^[13][a-km-zA-HJ-NP-Z1-9]{25,34}$"""),
    explorer = MBlockchainExplorer.MEMPOOL
)

object LitecoinConfig : MBlockchainConfig by UtxoConfig(
    symbolIcon = org.mytonwallet.app_air.icons.R.drawable.ic_symbol_litecoin,
    symbolIconPadded = org.mytonwallet.app_air.icons.R.drawable.ic_symbol_litecoin_15,
    receiveOrnamentImage =
        org.mytonwallet.app_air.icons.R.drawable.receive_ornament_litecoin_light,
    displayColor = "#345D9D",
    feeCheckAddress = "ltc1qw508d6qejxtdg4y5r3zarvary0c5xw7kgmn4n9",
    defaultDerivationPath = "m/84'/2'/0'/0/{index}",
    addressRegex =
        Regex("""^(?:ltc1|tltc1)[a-z0-9]{25,62}$|^[LM2lm][a-km-zA-HJ-NP-Z1-9]{26,33}$"""),
    explorer = MBlockchainExplorer.BLOCKCHAIR_LITECOIN
)

object BitcoinCashConfig : MBlockchainConfig by UtxoConfig(
    symbolIcon = org.mytonwallet.app_air.icons.R.drawable.ic_symbol_bitcoincash,
    symbolIconPadded = org.mytonwallet.app_air.icons.R.drawable.ic_symbol_bitcoincash_15,
    receiveOrnamentImage =
        org.mytonwallet.app_air.icons.R.drawable.receive_ornament_bitcoincash_light,
    displayColor = "#0AC18E",
    feeCheckAddress = "qrny4xkwvwvsxertkd2nue70wmc5s98kru7m2q7vk6",
    defaultDerivationPath = "m/44'/145'/0'/0/{index}",
    addressRegex = Regex(
        """^(?:bitcoincash:|bchtest:)?[qp][a-z0-9]{41}$|^[13][a-km-zA-HJ-NP-Z1-9]{25,34}$""",
        RegexOption.IGNORE_CASE
    ),
    explorer = MBlockchainExplorer.BLOCKCHAIR_BITCOINCASH
) {
    override fun normalizeAddress(address: String): String {
        val trimmed = address.trim()
        val separator = trimmed.indexOf(':')
        if (separator <= 0) return trimmed

        val prefix = trimmed.substring(0, separator).lowercase()
        if (prefix != "bitcoincash" && prefix != "bchtest") return trimmed

        return trimmed.substring(separator + 1)
    }
}

object DogecoinConfig : MBlockchainConfig by UtxoConfig(
    symbolIcon = org.mytonwallet.app_air.icons.R.drawable.ic_symbol_dogecoin,
    symbolIconPadded = org.mytonwallet.app_air.icons.R.drawable.ic_symbol_dogecoin_15,
    receiveOrnamentImage =
        org.mytonwallet.app_air.icons.R.drawable.receive_ornament_dogecoin_light,
    displayColor = "#C2A633",
    feeCheckAddress = "D596YFweJQuHY1BbjazZYmAbt8jJPbKehC",
    defaultDerivationPath = "m/44'/3'/0'/0/{index}",
    addressRegex = Regex("""^D[5-9A-HJ-NP-U][1-9A-HJ-NP-Za-km-z]{32}$"""),
    explorer = MBlockchainExplorer.BLOCKCHAIR_DOGECOIN
)
