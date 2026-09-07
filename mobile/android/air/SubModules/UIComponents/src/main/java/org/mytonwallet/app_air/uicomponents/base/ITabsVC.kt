package org.mytonwallet.app_air.uicomponents.base

import android.net.Uri
import android.view.ViewGroup
import android.widget.FrameLayout

interface ITabsVC {
    val mainNavigationController: WNavigationController?
    val activeNavigationController: WNavigationController?
    val bottomNavigationView: FrameLayout?
    val minimizedBlurRootView: ViewGroup? get() = null
    fun getBottomNavigationHeight(): Int
    fun minimize(
        nav: WNavigationController,
        onProgress: (progress: Float) -> Unit,
        onMaximizeProgress: (progress: Float) -> Unit
    )

    fun maximize()
    fun dismissMinimized(animated: Boolean = true)
    fun scrollingUp()
    fun scrollingDown()
    fun setSearchText(text: String)
    fun clearSearchFocus()
    fun switchToFirstTab(): Boolean

    fun hideTabBar()
    fun showTabBar()

    val isOnHomeScreen: Boolean
    fun switchToExplore(targetUri: Uri? = null)
    fun switchToMarket()
    fun switchToAgent(prompt: String? = null, pinnedMessageId: String? = null): Boolean
    fun switchToSettings(pushVC: WViewController? = null)
    fun navStackUpdated(nav: WNavigationController) {}

    /**
     * Stack that hosts the global search screen above the tab chrome, created on demand. Null when
     * the host has no such layer and search should be pushed into the active stack instead.
     */
    val searchOverlayNavigationController: WNavigationController? get() = null

    /** Fades the search overlay in, taking the top tabs and avatar out with it. */
    fun revealSearchOverlay() {}

    /** Fades the search overlay out and brings the top tabs and avatar back. */
    fun hideSearchOverlay() {}
}
