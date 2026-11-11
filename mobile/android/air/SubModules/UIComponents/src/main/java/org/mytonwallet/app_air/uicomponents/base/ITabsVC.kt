package org.mytonwallet.app_air.uicomponents.base

import android.net.Uri
import android.view.ViewGroup
import org.mytonwallet.app_air.uicomponents.widgets.WSearchEditText
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2EntryPoint
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadSummary

interface ITabsVC :
    ISearchOverlayHost,
    IChromeOverlapHost {
    val mainNavigationController: WNavigationController?
    val activeNavigationController: WNavigationController?
    val minimizedBlurRootView: ViewGroup? get() = null
    fun setSearchText(text: String)

    /** Selects the first tab in the user's order, returning false when it is already selected */
    fun switchToFirstTab(): Boolean

    /** Selects the Wallet tab, returning false when it is already selected */
    fun switchToWallet(): Boolean

    fun hideTabBar()
    fun showTabBar()

    val isOnHomeScreen: Boolean
    fun switchToExplore(targetUri: Uri? = null)
    fun switchToMarket()
    fun switchToFutures()
    fun switchToAgent(
        prompt: String? = null,
        entryPoint: AgentV2EntryPoint = AgentV2EntryPoint(),
        thread: AgentV2ThreadSummary? = null
    ): Boolean
    fun switchToSettings(pushVC: WViewController? = null)

    /** Whether [openAgentSearch] can open the global search over the Agent tab */
    val isAgentSearchSupported: Boolean get() = false

    /**
     * Opens the global search over the Agent tab, whose own bar gives way to the search field until [onClose].
     * Returns false when the search can't open now.
     */
    fun openAgentSearch(onClose: () -> Unit): Boolean = false
    fun navStackUpdated(nav: WNavigationController) {}
    fun rootTopAccessoryWidthsChanged() {}

    /**
     * Stack that hosts the global search screen above the tab chrome, created on demand. Null when
     * the host has no such layer and search should be pushed into the active stack instead.
     */
    val searchOverlayNavigationController: WNavigationController? get() = null

    fun searchExplore(
        query: String?,
        focused: Boolean,
        targetNavigationController: WNavigationController
    ) {}

    fun submitExploreSearch(field: WSearchEditText) {}
}
