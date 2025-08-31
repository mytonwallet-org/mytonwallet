package org.mytonwallet.app_air.uisettings.viewControllers.settings.models

data class SettingsSection(
    val section: Section,
    var children: List<SettingsItem>
) {
    enum class Section {
        ACCOUNTS,
        WALLET_CONFIG,
        WALLET_DATA,
        NOT_IDENTIFIED
    }
}
