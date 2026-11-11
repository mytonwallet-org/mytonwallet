package org.mytonwallet.uihome.tabs

import org.mytonwallet.app_air.icons.R
import org.mytonwallet.app_air.uicomponents.R as UIComponentsR
import org.mytonwallet.app_air.walletcontext.PerpsAvailability
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent

object AppTabsManager {

    data class AppTab(
        val id: String,
        val intId: Int,
        val iconRes: Int,
        val filledIconRes: Int,
        val labelKey: String,
        val isRequired: Boolean,
        // Stable resource id of the phone top tab, for UI automation
        val testViewId: Int? = null
    )

    const val ID_HOME = 1
    const val ID_AGENT = 2
    const val ID_EXPLORE = 3
    const val ID_SETTINGS = 4
    const val ID_PORTFOLIO = 5
    const val ID_MARKET = 6
    const val ID_FUTURES = 7

    const val TAB_WALLET = "wallet"
    const val TAB_MARKET = "market"
    const val TAB_FUTURES = "futures"
    const val TAB_AGENT = "agent"
    const val TAB_EXPLORE = "explore"
    const val TAB_SETTINGS = "settings"
    const val TAB_PORTFOLIO = "portfolio"

    val registeredTabs = listOf(
        AppTab(
            TAB_WALLET,
            ID_HOME,
            R.drawable.ic_home_thin,
            R.drawable.ic_home_filled,
            "Wallet",
            isRequired = true,
            testViewId = UIComponentsR.id.tab_wallet
        ),
        AppTab(
            TAB_MARKET,
            ID_MARKET,
            R.drawable.ic_market_thin,
            R.drawable.ic_market_filled,
            "Market",
            isRequired = false,
            testViewId = UIComponentsR.id.tab_market
        ),
        AppTab(
            TAB_FUTURES,
            ID_FUTURES,
            R.drawable.ic_futures_thin,
            R.drawable.ic_futures_filled,
            "Futures",
            isRequired = false
        ),
        AppTab(
            TAB_AGENT,
            ID_AGENT,
            R.drawable.ic_agent_thin,
            R.drawable.ic_agent_filled,
            "Agent",
            isRequired = false,
            testViewId = UIComponentsR.id.tab_agent
        ),
        AppTab(
            TAB_EXPLORE,
            ID_EXPLORE,
            R.drawable.ic_explore_thin,
            R.drawable.ic_explore_filled,
            "Apps",
            isRequired = false,
            testViewId = UIComponentsR.id.tab_explore
        ),
        AppTab(
            TAB_SETTINGS,
            ID_SETTINGS,
            R.drawable.ic_settings_thin,
            R.drawable.ic_settings_filled,
            "Settings",
            isRequired = true
        ),
        AppTab(
            TAB_PORTFOLIO,
            ID_PORTFOLIO,
            R.drawable.ic_portfolio_thin,
            R.drawable.ic_portfolio_filled,
            "Portfolio",
            isRequired = false,
            testViewId = UIComponentsR.id.tab_portfolio
        )
    ).filter { it.id != TAB_FUTURES || PerpsAvailability.isAvailable() }

    val defaultTabIds =
        listOf(TAB_WALLET, TAB_MARKET, TAB_FUTURES, TAB_AGENT, TAB_EXPLORE, TAB_SETTINGS)
            .filter { tabFor(it) != null }

    private val legacyDefaultTabIds = listOf(TAB_WALLET, TAB_AGENT, TAB_EXPLORE, TAB_SETTINGS)

    private var _orderedTabIds: List<String>? = null
    val orderedTabIds: List<String>
        get() = _orderedTabIds
            ?: validatedTabOrder(WGlobalStorage.getAppTabOrder()).also { _orderedTabIds = it }

    val orderedTabs: List<AppTab>
        get() = orderedTabIds.mapNotNull(::tabFor)

    val isCustomized: Boolean
        get() = orderedTabIds != defaultTabIds

    fun tabFor(id: String): AppTab? = registeredTabs.firstOrNull { it.id == id }

    fun contains(intId: Int): Boolean = orderedTabs.any { it.intId == intId }

    fun setTabIds(ids: List<String>) {
        val validated = validatedTabOrder(ids)
        if (validated == orderedTabIds) return
        _orderedTabIds = validated
        WGlobalStorage.setAppTabOrder(validated)
        WalletCore.notifyEvent(WalletEvent.AppTabsChanged)
    }

    /**
     * Puts [ids] in their new order on the places they take, keeping every other tab where it is,
     * so a list that shows only some of the tabs can reorder them
     */
    fun reorderTabs(ids: List<String>) {
        val movedIds = ids.toSet()
        if (movedIds.size != ids.size || !orderedTabIds.containsAll(movedIds)) return
        val remainingIds = ArrayDeque(ids)
        setTabIds(orderedTabIds.map { if (it in movedIds) remainingIds.removeFirst() else it })
    }

    // Drops unknown/duplicate ids and re-appends missing required tabs, so a stale or foreign
    // stored order can never leave the app without the wallet/settings tabs.
    private fun validatedTabOrder(raw: List<String>?): List<String> {
        if (raw.isNullOrEmpty()) return defaultTabIds
        if (raw == legacyDefaultTabIds) return defaultTabIds
        val result = LinkedHashSet<String>()
        raw.forEach { id ->
            if (tabFor(id) != null) result.add(id)
        }
        registeredTabs.forEach { tab ->
            if (tab.isRequired) result.add(tab.id)
        }
        return result.toList()
    }
}
