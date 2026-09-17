package org.mytonwallet.app_air.walletcore.models.blockchain

import java.math.BigDecimal
import org.mytonwallet.app_air.walletcontext.models.MBlockchainNetwork

object ArcConfig : MBlockchainConfig {

    override val gas = MBlockchain.Gas(
        maxSwap = null,
        maxTransfer = BigDecimal.ZERO,
        maxTransferToken = BigDecimal.ZERO
    )

    override val symbolIcon = org.mytonwallet.app_air.icons.R.drawable.ic_symbol_arc
    override val symbolIconPadded = org.mytonwallet.app_air.icons.R.drawable.ic_symbol_arc_15
    override val receiveOrnamentImage =
        org.mytonwallet.app_air.icons.R.drawable.receive_ornament_arc_light

    override val qrIcon = null
    override val displayColor = "#2775CA".hexToColorInt()
    override val qrGradientColors = intArrayOf(
        "#12294A".hexToColorInt(),
        "#000000".hexToColorInt()
    )

    override val feeCheckAddress = EVM_FEE_CHECK_ADDRESS

    override val isCommentSupported = false
    override val isEncryptedCommentSupported = false

    override val burnAddress = null
    override val multiWalletSupport = MultiWalletSupport.PATH

    override val chainStandard = "ethereum"
    override val defaultDerivationPath = "m/44'/60'/0'/0/{index}"
    override val walletConnectChainIds = mapOf(
        MBlockchainNetwork.MAINNET to 5042,
        MBlockchainNetwork.TESTNET to 5042002
    )

    override fun isValidAddress(address: String): Boolean =
        Regex("""^0x[a-fA-F0-9]{40}$""").matches(address)

    override fun idToTxHash(id: String?): String? = id?.substringBefore(":")

    override fun transactionExplorers() = listOf(MBlockchainExplorer.ARCSCAN)

    override fun addressExplorers() = listOf(MBlockchainExplorer.ARCSCAN)

    override fun tokenExplorer() = MBlockchainExplorer.ARCSCAN

    override fun nftExplorer() = null
}
