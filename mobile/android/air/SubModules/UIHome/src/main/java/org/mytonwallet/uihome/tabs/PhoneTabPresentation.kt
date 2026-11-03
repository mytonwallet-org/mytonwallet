package org.mytonwallet.uihome.tabs

internal val PHONE_PUSHED_TAB_IDS = setOf(AppTabsManager.ID_SETTINGS)

internal fun shouldShowPhoneSearch(tabId: Int): Boolean = tabId != AppTabsManager.ID_AGENT

internal fun shouldShowPhoneTopTabs(tabId: Int, stackDepth: Int): Boolean =
    tabId != AppTabsManager.ID_SETTINGS &&
        (tabId != AppTabsManager.ID_AGENT || stackDepth <= 1)
