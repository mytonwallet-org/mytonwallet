package org.mytonwallet.app_air.walletcore.models.blockchain

interface MBlockchainConfig {
    val gas: MBlockchain.Gas?
    val symbolIcon: Int?
    val symbolIconPadded: Int?
    val receiveOrnamentImage: Int?
    val qrGradientColors: IntArray?
    val feeCheckAddress: String?
    val isCommentSupported: Boolean
    val isEncryptedCommentSupported: Boolean
    val burnAddress: String?
    val canBuyWithCard: Boolean?

    fun isValidAddress(address: String): Boolean
    fun isValidDNS(address: String): Boolean = false
    fun idToTxHash(id: String?): String? = null

    fun transactionExplorers(): List<MBlockchainExplorer>
    fun addressExplorers(): List<MBlockchainExplorer>
    fun tokenExplorer(): MBlockchainExplorer?
    fun nftExplorer(): MBlockchainExplorer?
}
