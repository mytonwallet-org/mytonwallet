package org.mytonwallet.app_air.walletcontext.models

enum class MBlockchainNetwork(val value: String) {
    MAINNET("mainnet"),
    TESTNET("testnet");

    companion object {
        fun ofAccountId(accountId: String): MBlockchainNetwork {
            val networkValue =
                accountId.substringAfterLast("-", MAINNET.value)
            return if (networkValue == TESTNET.value) TESTNET else MAINNET
        }
    }

    val localizedIdentifier: String
        get() {
            return when (this) {
                TESTNET -> " (Testnet)"
                else -> ""
            }
        }
}
