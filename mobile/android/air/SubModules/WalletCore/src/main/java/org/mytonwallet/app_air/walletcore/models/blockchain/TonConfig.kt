package org.mytonwallet.app_air.walletcore.models.blockchain

import java.math.BigDecimal
import androidx.core.graphics.toColorInt

object TonConfig : MBlockchainConfig {

    override val gas = MBlockchain.Gas(
        maxSwap = BigDecimal("0.4"),
        maxTransfer = BigDecimal("0.015"),
        maxTransferToken = BigDecimal("0.06")
    )

    override val symbolIcon = org.mytonwallet.app_air.icons.R.drawable.ic_symbol_ton

    override val symbolIconPadded = org.mytonwallet.app_air.icons.R.drawable.ic_symbol_ton_15

    override val receiveOrnamentImage = org.mytonwallet.app_air.icons.R.drawable.receive_ornament_ton_light

    override val qrGradientColors = intArrayOf(
        "#158AA0".toColorInt(),
        "#13499C".toColorInt(),
    )

    override val feeCheckAddress: String? = null

    override val isCommentSupported = true
    override val isEncryptedCommentSupported = true

    override val burnAddress = "UQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAJKZ"
    override val canBuyWithCard = true

    override fun isValidAddress(address: String): Boolean =
        Regex("""^([-\w_]{48}|0:[\da-fA-F]{64})$""").matches(address)

    override fun isValidDNS(address: String): Boolean {
        val zones = listOf(
            Regex("""^([-\da-z]+\.){0,2}[-\da-z]{4,126}\.ton$""", RegexOption.IGNORE_CASE),
            Regex("""^([-\da-z]+\.){0,2}[-_\da-z]{4,32}\.t\.me$""", RegexOption.IGNORE_CASE),
            Regex("""^([-\da-z]+\.){0,2}[\da-z]{1,24}\.(vip|ton\.vip|vip\.ton)$""", RegexOption.IGNORE_CASE),
            Regex("""^([-\da-z]+\.){0,2}[-\da-z]{1,127}\.gram$""", RegexOption.IGNORE_CASE)
        )
        return zones.any { it.matches(address) }
    }

    override fun idToTxHash(id: String?): String? =
        id?.substringBefore(":")

    override fun transactionExplorers() =
        listOf(MBlockchainExplorer.TONSCAN, MBlockchainExplorer.TONVIEWER)

    override fun addressExplorers() =
        listOf(MBlockchainExplorer.TONSCAN, MBlockchainExplorer.TONVIEWER)

    override fun tokenExplorer() =
        MBlockchainExplorer.TONSCAN

    override fun nftExplorer() =
        MBlockchainExplorer.TONSCAN
}
