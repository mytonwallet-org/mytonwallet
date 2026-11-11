package org.mytonwallet.app_air.walletcore.models.blockchain

import org.mytonwallet.app_air.walletcontext.models.MBlockchainNetwork

private val STABLECOIN_SLUGS_BY_NETWORK = MBlockchainNetwork.entries.associateWith { network ->
    MBlockchain.entries.flatMap { chain ->
        listOfNotNull(chain.config?.usdtSlug?.get(network), chain.config?.usdcSlug?.get(network))
    }.filter { it.isNotEmpty() }.toSet()
}

private val STABLECOIN_SLUGS = STABLECOIN_SLUGS_BY_NETWORK.values.flatten().toSet()

fun getStablecoinSlugs(network: MBlockchainNetwork? = null): Set<String> =
    network?.let { STABLECOIN_SLUGS_BY_NETWORK.getValue(it) } ?: STABLECOIN_SLUGS

interface MBlockchainConfig {
    val gas: MBlockchain.Gas?
    val nativeIcon: Int?
        get() = null
    val symbolIcon: Int?
    val symbolIconPadded: Int?
    val receiveOrnamentImage: Int?
    val qrIcon: Int?
    val qrGradientColors: IntArray?

    val displayColor: Int
    val feeCheckAddress: String?
    val isCommentSupported: Boolean
    val isEncryptedCommentSupported: Boolean
    val burnAddress: String?
    val isOnRampSupported: Boolean get() = true
    val isOffRampSupported: Boolean get() = true
    val isOnchainSwapSupported: Boolean get() = false
    val canSwapByBuyAmount: Boolean get() = false
    val canTransferFullNativeBalance: Boolean get() = false
    val multiWalletSupport: MultiWalletSupport?

    val usdtSlug: Map<MBlockchainNetwork, String> get() = emptyMap()
    val usdcSlug: Map<MBlockchainNetwork, String> get() = emptyMap()
    val chainStandard: String? get() = null
    val defaultDerivationPath: String? get() = null
    val walletConnectChainIds: Map<MBlockchainNetwork, Int> get() = emptyMap()

    fun isValidAddress(address: String): Boolean
    fun normalizeAddress(address: String): String = address
    fun isValidDNS(address: String): Boolean = false
    fun idToTxHash(id: String?): String? = null

    fun transactionExplorers(): List<MBlockchainExplorer>
    fun addressExplorers(): List<MBlockchainExplorer>
    fun tokenExplorer(): MBlockchainExplorer?
    fun nftExplorer(): MBlockchainExplorer?
}
