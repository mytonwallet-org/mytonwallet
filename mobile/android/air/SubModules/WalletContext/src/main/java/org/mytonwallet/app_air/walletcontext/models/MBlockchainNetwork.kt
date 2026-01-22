package org.mytonwallet.app_air.walletcontext.models

enum class MBlockchainNetwork(val value: String) {
    MAINNET("mainnet"),
    TESTNET("testnet");

    companion object {
        fun ofAccountId(accountId: String): MBlockchainNetwork {
            return if (accountId.split("-")[1] == "mainnet") MAINNET else TESTNET
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
