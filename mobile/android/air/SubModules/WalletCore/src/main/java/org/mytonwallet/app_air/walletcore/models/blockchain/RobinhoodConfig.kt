package org.mytonwallet.app_air.walletcore.models.blockchain

import androidx.core.graphics.toColorInt
import java.math.BigDecimal
import org.mytonwallet.app_air.walletcontext.models.MBlockchainNetwork

object RobinhoodConfig : MBlockchainConfig {

    override val gas = MBlockchain.Gas(
        maxSwap = null,
        maxTransfer = BigDecimal.ZERO,
        maxTransferToken = BigDecimal.ZERO
    )

    override val symbolIcon = org.mytonwallet.app_air.icons.R.drawable.ic_symbol_robinhood
    override val symbolIconPadded = org.mytonwallet.app_air.icons.R.drawable.ic_symbol_robinhood_15
    override val receiveOrnamentImage =
        org.mytonwallet.app_air.icons.R.drawable.receive_ornament_robinhood_light

    override val qrIcon = null
    override val displayColor = "#CCFF00".toColorInt()
    override val qrGradientColors = intArrayOf(
        "#485011".toColorInt(),
        "#000000".toColorInt()
    )

    override val feeCheckAddress = "0x0000000000000000000000000000000000000000"

    override val isCommentSupported = false
    override val isEncryptedCommentSupported = false

    override val burnAddress = null
    override val multiWalletSupport = MultiWalletSupport.PATH

    override val chainStandard = "ethereum"
    override val defaultDerivationPath = "m/44'/60'/0'/0/{index}"
    override val walletConnectChainIds = mapOf(
        MBlockchainNetwork.MAINNET to 4663,
        MBlockchainNetwork.TESTNET to 46630
    )

    override fun isValidAddress(address: String): Boolean =
        Regex("""^0x[a-fA-F0-9]{40}$""").matches(address)

    override fun idToTxHash(id: String?): String? = id?.substringBefore(":")

    override fun transactionExplorers() = listOf(MBlockchainExplorer.ROBINSCAN)

    override fun addressExplorers() = listOf(MBlockchainExplorer.ROBINSCAN)

    override fun tokenExplorer() = MBlockchainExplorer.ROBINSCAN

    override fun nftExplorer() = null
}
