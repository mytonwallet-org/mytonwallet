package org.mytonwallet.app_air.walletcore.models.blockchain

import androidx.core.graphics.toColorInt
import java.math.BigDecimal

object PolygonConfig : MBlockchainConfig {

    override val gas = MBlockchain.Gas(
        maxSwap = null,
        maxTransfer = BigDecimal.ZERO,
        maxTransferToken = BigDecimal.ZERO
    )

    override val symbolIcon = org.mytonwallet.app_air.icons.R.drawable.ic_symbol_polygon
    override val symbolIconPadded = org.mytonwallet.app_air.icons.R.drawable.ic_symbol_polygon
    override val receiveOrnamentImage =
        org.mytonwallet.app_air.icons.R.drawable.receive_ornament_polygon_light

    override val qrIcon = null
    override val qrGradientColors = intArrayOf(
        "#76479B".toColorInt(),
        "#5D2998".toColorInt(),
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
        listOf(MBlockchainExplorer.POLYGONSCAN)

    override fun addressExplorers() =
        listOf(MBlockchainExplorer.POLYGONSCAN)

    override fun tokenExplorer() =
        MBlockchainExplorer.POLYGONSCAN

    override fun nftExplorer() =
        MBlockchainExplorer.POLYGONSCAN
}
