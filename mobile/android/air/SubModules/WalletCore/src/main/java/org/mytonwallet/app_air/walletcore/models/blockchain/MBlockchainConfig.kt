package org.mytonwallet.app_air.walletcore.models.blockchain

import org.mytonwallet.app_air.walletcontext.models.MBlockchainNetwork

interface MBlockchainConfig {
    val gas: MBlockchain.Gas?
    val symbolIcon: Int?
    val symbolIconPadded: Int?
    val receiveOrnamentImage: Int?
    val qrIcon: Int?
    val qrGradientColors: IntArray?
    val feeCheckAddress: String?
    val isCommentSupported: Boolean
    val isEncryptedCommentSupported: Boolean
    val burnAddress: String?
    val isOnRampSupported: Boolean get() = true
    val isOffRampSupported: Boolean get() = true
    val multiWalletSupport: MultiWalletSupport?

    val chainStandard: String? get() = null
    val defaultDerivationPath: String? get() = null
    val walletConnectChainIds: Map<MBlockchainNetwork, Int> get() = emptyMap()

    fun isValidAddress(address: String): Boolean
    fun isValidDNS(address: String): Boolean = false
    fun idToTxHash(id: String?): String? = null

    fun transactionExplorers(): List<MBlockchainExplorer>
    fun addressExplorers(): List<MBlockchainExplorer>
    fun tokenExplorer(): MBlockchainExplorer?
    fun nftExplorer(): MBlockchainExplorer?
}
