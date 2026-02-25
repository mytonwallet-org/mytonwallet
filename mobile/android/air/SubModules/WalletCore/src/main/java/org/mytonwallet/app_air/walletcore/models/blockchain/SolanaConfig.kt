package org.mytonwallet.app_air.walletcore.models.blockchain

import androidx.core.graphics.toColorInt
import java.math.BigDecimal

object SolanaConfig : MBlockchainConfig {

    override val gas = MBlockchain.Gas(
        maxSwap = null,
        maxTransfer = BigDecimal.ZERO,
        maxTransferToken = BigDecimal.ZERO
    )

    override val symbolIcon = org.mytonwallet.app_air.icons.R.drawable.ic_symbol_sol

    override val symbolIconPadded = org.mytonwallet.app_air.icons.R.drawable.ic_symbol_sol

    override val receiveOrnamentImage = org.mytonwallet.app_air.icons.R.drawable.receive_ornament_sol_light

    override val qrGradientColors = intArrayOf(
        "#5E58BA".toColorInt(),
        "#106E73".toColorInt(),
    )

    override val feeCheckAddress = "35YT7tt9edJbroEKaC3T3XY4cLNWKtVzmyTEfW8LHPEA"

    override val isCommentSupported = true
    override val isEncryptedCommentSupported = false

    override val burnAddress = null
    override val canBuyWithCard = false

    override fun isValidAddress(address: String): Boolean =
        Regex("""^[1-9A-HJ-NP-Za-km-z]{32,44}$""").matches(address)

    override fun isValidDNS(address: String): Boolean {
        return false
    }

    override fun idToTxHash(id: String?): String? =
        id?.substringBefore(":")

    override fun transactionExplorers() =
        listOf(MBlockchainExplorer.SOLSCAN)

    override fun addressExplorers() =
        listOf(MBlockchainExplorer.SOLSCAN)

    override fun tokenExplorer() =
        MBlockchainExplorer.SOLSCAN

    override fun nftExplorer() = null
}
