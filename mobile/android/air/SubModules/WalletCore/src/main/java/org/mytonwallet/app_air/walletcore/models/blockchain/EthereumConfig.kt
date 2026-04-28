package org.mytonwallet.app_air.walletcore.models.blockchain

import androidx.core.graphics.toColorInt
import org.mytonwallet.app_air.walletcontext.models.MBlockchainNetwork
import java.math.BigDecimal

object EthereumConfig : MBlockchainConfig {

    override val gas = MBlockchain.Gas(
        maxSwap = null,
        maxTransfer = BigDecimal.ZERO,
        maxTransferToken = BigDecimal.ZERO
    )

    override val symbolIcon = org.mytonwallet.app_air.icons.R.drawable.ic_symbol_eth
    override val symbolIconPadded = org.mytonwallet.app_air.icons.R.drawable.ic_symbol_eth
    override val receiveOrnamentImage =
        org.mytonwallet.app_air.icons.R.drawable.receive_ornament_eth_light

    override val qrIcon = org.mytonwallet.app_air.icons.R.drawable.ic_blockchain_ethereum_128_qr
    override val qrGradientColors = intArrayOf(
        "#535B77".toColorInt(),
        "#534865".toColorInt(),
    )

    override val feeCheckAddress = "0x0000000000000000000000000000000000000000"

    override val isCommentSupported = false
    override val isEncryptedCommentSupported = false

    override val burnAddress = null
    override val multiWalletSupport = MultiWalletSupport.PATH

    override val chainStandard = "ethereum"
    override val defaultDerivationPath = "m/44'/60'/0'/0/{index}"
    override val walletConnectChainIds = mapOf(
        MBlockchainNetwork.MAINNET to 1,
        MBlockchainNetwork.TESTNET to 5,
    )

    override fun isValidAddress(address: String): Boolean =
        Regex("""^0x[a-fA-F0-9]{40}$""").matches(address)

    override fun idToTxHash(id: String?): String? =
        id?.substringBefore(":")

    override fun transactionExplorers() =
        listOf(MBlockchainExplorer.ETHERSCAN)

    override fun addressExplorers() =
        listOf(MBlockchainExplorer.ETHERSCAN)

    override fun tokenExplorer() =
        MBlockchainExplorer.ETHERSCAN

    override fun nftExplorer() =
        MBlockchainExplorer.ETHERSCAN
}
