package org.mytonwallet.app_air.walletcontext.models

import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController

enum class MWalletCardTopLine(val value: String, val maxAddressesByBalance: Int?) {
    WALLET_NAME("wallet-name", null),
    HIGHEST_BALANCE_ADDRESS("top-address", 1),
    THREE_HIGHEST_BALANCE_ADDRESSES("top-3-addresses", 3);

    companion object {
        val DEFAULT = WALLET_NAME

        fun fromValue(value: String?): MWalletCardTopLine =
            entries.firstOrNull { it.value == value } ?: DEFAULT
    }

    val displayName: String
        get() = when (this) {
            WALLET_NAME -> LocaleController.getString("Wallet Name")
            HIGHEST_BALANCE_ADDRESS -> LocaleController.getString("Top Address")
            THREE_HIGHEST_BALANCE_ADDRESSES -> LocaleController.getString("3 Top Addresses")
        }

    val menuTitle: String
        get() = when (this) {
            WALLET_NAME -> displayName

            HIGHEST_BALANCE_ADDRESS -> LocaleController.getString("Highest-Balance Address")

            THREE_HIGHEST_BALANCE_ADDRESSES ->
                LocaleController.getString("3 Highest-Balance Addresses")
        }
}
