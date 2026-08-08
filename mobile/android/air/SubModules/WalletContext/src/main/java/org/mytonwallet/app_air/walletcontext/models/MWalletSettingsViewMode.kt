package org.mytonwallet.app_air.walletcontext.models

enum class MWalletSettingsViewMode(val value: String) {
    GRID("cards"),
    LIST("list");

    companion object {
        fun fromValue(value: String?): MWalletSettingsViewMode? =
            entries.firstOrNull { it.value == value }
    }
}
