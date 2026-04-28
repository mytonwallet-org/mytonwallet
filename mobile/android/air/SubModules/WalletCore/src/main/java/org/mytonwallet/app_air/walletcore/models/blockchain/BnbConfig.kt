package org.mytonwallet.app_air.walletcore.models.blockchain

import androidx.core.graphics.toColorInt
import java.math.BigDecimal

object BnbConfig : MBlockchainConfig {

    override val gas = MBlockchain.Gas(
        maxSwap = null,
        maxTransfer = BigDecimal.ZERO,
        maxTransferToken = BigDecimal.ZERO
    )

    override val symbolIcon = org.mytonwallet.app_air.icons.R.drawable.ic_symbol_bnb
    override val symbolIconPadded = org.mytonwallet.app_air.icons.R.drawable.ic_symbol_bnb
    override val receiveOrnamentImage =
        org.mytonwallet.app_air.icons.R.drawable.receive_ornament_bnb_light

    override val qrIcon = null
    override val qrGradientColors = intArrayOf(
        "#6A6218".toColorInt(),
        "#644C1A".toColorInt(),
    )

    override val feeCheckAddress = "0x0000000000000000000000000000000000000000"

    override val isCommentSupported = false
    override val isEncryptedCommentSupported = false

    override val burnAddress = null
    override val isOnRampSupported = false
    override val isOffRampSupported = false
    override val multiWalletSupport = MultiWalletSupport.PATH

    override val chainStandard = "ethereum"
    override val defaultDerivationPath = "m/44'/60'/0'/0/{index}"

    override fun isValidAddress(address: String): Boolean =
        Regex("""^0x[a-fA-F0-9]{40}$""").matches(address)

    override fun idToTxHash(id: String?): String? =
        id?.substringBefore(":")

    override fun transactionExplorers() =
        listOf(MBlockchainExplorer.BSCTRACE)

    override fun addressExplorers() =
        listOf(MBlockchainExplorer.BSCTRACE)

    override fun tokenExplorer() =
        MBlockchainExplorer.BSCTRACE

    override fun nftExplorer() =
        MBlockchainExplorer.BSCTRACE
}
