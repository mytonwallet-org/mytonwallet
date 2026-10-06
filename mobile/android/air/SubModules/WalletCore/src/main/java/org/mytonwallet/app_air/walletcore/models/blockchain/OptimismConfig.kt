package org.mytonwallet.app_air.walletcore.models.blockchain

import java.math.BigDecimal
import org.mytonwallet.app_air.walletcontext.models.MBlockchainNetwork

object OptimismConfig : MBlockchainConfig {

    override val gas = MBlockchain.Gas(
        maxSwap = null,
        maxTransfer = BigDecimal.ZERO,
        maxTransferToken = BigDecimal.ZERO
    )

    override val symbolIcon = org.mytonwallet.app_air.icons.R.drawable.ic_symbol_optimism
    override val symbolIconPadded = org.mytonwallet.app_air.icons.R.drawable.ic_symbol_optimism
    override val receiveOrnamentImage =
        org.mytonwallet.app_air.icons.R.drawable.receive_ornament_optimism_light

    override val qrIcon = null
    override val displayColor = "#FF4F4F".hexToColorInt()
    override val qrGradientColors = intArrayOf(
        "#FF9EA8".hexToColorInt(),
        "#2D0A0E".hexToColorInt()
    )

    override val feeCheckAddress = EVM_FEE_CHECK_ADDRESS

    override val isOnchainSwapSupported = true

    override val isCommentSupported = false
    override val isEncryptedCommentSupported = false

    override val burnAddress = null
    override val multiWalletSupport = MultiWalletSupport.PATH

    override val chainStandard = "ethereum"
    override val defaultDerivationPath = "m/44'/60'/0'/0/{index}"
    override val walletConnectChainIds = mapOf(
        MBlockchainNetwork.MAINNET to 10,
        MBlockchainNetwork.TESTNET to 11155420
    )

    override fun isValidAddress(address: String): Boolean =
        Regex("""^0x[a-fA-F0-9]{40}$""").matches(address)

    override fun idToTxHash(id: String?): String? = id?.substringBefore(":")

    override fun transactionExplorers() = listOf(MBlockchainExplorer.OPTIMISMSCAN)

    override fun addressExplorers() = listOf(MBlockchainExplorer.OPTIMISMSCAN)

    override fun tokenExplorer() = MBlockchainExplorer.OPTIMISMSCAN

    override fun nftExplorer() = MBlockchainExplorer.OPTIMISMSCAN
}
