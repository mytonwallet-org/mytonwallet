package org.mytonwallet.app_air.uisettings.viewControllers.settings.models

import org.mytonwallet.app_air.walletcore.models.MAccount

data class SettingsItem(
    val identifier: Identifier,
    val icon: Int? = null,
    val title: String,
    val value: String? = null,
    val hasTintColor: Boolean,
    val account: MAccount? = null
) {
    enum class Identifier {
        ACCOUNT,
        ADD_ACCOUNT,
        NOTIFICATION_SETTINGS,
        APPEARANCE,
        ASSETS_AND_ACTIVITY,
        CONNECTED_APPS,
        LANGUAGE,
        SECURITY,
        WALLET_VERSIONS,
        QUESTION_AND_ANSWERS,
        TERMS,
        SWITCH_TO_LEGACY,
        NONE,
    }

    override fun equals(other: Any?): Boolean {
        if (this == other) return true
        if (other !is SettingsItem) return false
        return identifier == other.identifier
    }

    override fun hashCode(): Int {
        return (identifier.toString() + '_' + account?.accountId).hashCode()
    }
}
