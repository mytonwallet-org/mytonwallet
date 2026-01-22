package org.mytonwallet.app_air.uisettings.viewControllers.settings.models

data class SettingsSection(
    val section: Section,
    val title: String,
    var children: List<SettingsItem>
) {
    enum class Section {
        ACCOUNTS,
        SETTINGS,
        HELP,
        ABOUT
    }
}
