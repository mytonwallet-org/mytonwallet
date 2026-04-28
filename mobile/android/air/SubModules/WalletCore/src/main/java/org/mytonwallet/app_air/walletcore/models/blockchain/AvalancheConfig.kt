package org.mytonwallet.app_air.walletcore.models.blockchain

import androidx.core.graphics.toColorInt
import java.math.BigDecimal

object AvalancheConfig : MBlockchainConfig {

    override val gas = MBlockchain.Gas(
        maxSwap = null,
        maxTransfer = BigDecimal.ZERO,
        maxTransferToken = BigDecimal.ZERO
    )

    override val symbolIcon = org.mytonwallet.app_air.icons.R.drawable.ic_symbol_avalanche
    override val symbolIconPadded = org.mytonwallet.app_air.icons.R.drawable.ic_symbol_avalanche
    override val receiveOrnamentImage =
        org.mytonwallet.app_air.icons.R.drawable.receive_ornament_avalanche_light

    override val qrIcon = null
    override val qrGradientColors = intArrayOf(
        "#A32F22".toColorInt(),
        "#9A184A".toColorInt(),
    )

    override val feeCheckAddress = "0x0000000000000000000000000000000000000000"

    override val isCommentSupported = false
    override val isEncryptedCommentSupported = false

    override val burnAddress = null
    override val multiWalletSupport = MultiWalletSupport.PATH

    override val chainStandard = "ethereum"
    override val defaultDerivationPath = "m/44'/60'/0'/0/{index}"

    override fun isValidAddress(address: String): Boolean =
        Regex("""^0x[a-fA-F0-9]{40}$""").matches(address)

    override fun idToTxHash(id: String?): String? =
        id?.substringBefore(":")

    override fun transactionExplorers() =
        listOf(MBlockchainExplorer.SNOWTRACE)

    override fun addressExplorers() =
        listOf(MBlockchainExplorer.SNOWTRACE)

    override fun tokenExplorer() =
        MBlockchainExplorer.SNOWTRACE

    override fun nftExplorer() =
        MBlockchainExplorer.SNOWTRACE
}
