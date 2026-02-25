package org.mytonwallet.app_air.walletcore.models.blockchain

import java.math.BigDecimal
import androidx.core.graphics.toColorInt

object TronConfig : MBlockchainConfig {

    override val gas = MBlockchain.Gas(
        maxSwap = null,
        maxTransfer = BigDecimal("1"),
        maxTransferToken = BigDecimal("30")
    )

    override val symbolIcon = org.mytonwallet.app_air.icons.R.drawable.ic_symbol_tron

    override val symbolIconPadded = org.mytonwallet.app_air.icons.R.drawable.ic_symbol_tron_15

    override val receiveOrnamentImage = org.mytonwallet.app_air.icons.R.drawable.receive_ornament_tron_light

    override val qrGradientColors = intArrayOf(
        "#A32F22".toColorInt(),
        "#9A184A".toColorInt(),
    )

    override val feeCheckAddress = "TW2LXSebZ7Br1zHaiA2W1zRojDkDwjGmpw"

    override val isCommentSupported = false
    override val isEncryptedCommentSupported = false

    override val burnAddress = null
    override val canBuyWithCard = true

    override fun isValidAddress(address: String): Boolean =
        Regex("""^T[1-9A-HJ-NP-Za-km-z]{33}$""").matches(address)

    override fun idToTxHash(id: String?): String? =
        id?.substringBefore(":")

    override fun transactionExplorers() =
        listOf(MBlockchainExplorer.TRONSCAN)

    override fun addressExplorers() =
        listOf(MBlockchainExplorer.TRONSCAN)

    override fun tokenExplorer() =
        MBlockchainExplorer.TRONSCAN

    override fun nftExplorer() = null
}
