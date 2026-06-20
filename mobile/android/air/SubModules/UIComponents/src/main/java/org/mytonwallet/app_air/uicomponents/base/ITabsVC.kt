package org.mytonwallet.app_air.uicomponents.base

import android.net.Uri
import android.view.ViewGroup
import android.widget.FrameLayout

interface ITabsVC {
    val mainNavigationController: WNavigationController?
    val activeNavigationController: WNavigationController?
    val pausedBlurViews: Boolean
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
    fun pauseBlurring()
    fun resumeBlurring()
    fun setSearchText(text: String)
    fun switchToFirstTab(): Boolean

    fun hideTabBar()
    fun showTabBar()

    val isOnHomeScreen: Boolean
    fun switchToExplore(targetUri: Uri? = null)
    fun switchToAgent()
    fun switchToSettings(pushVC: WViewController? = null)
    fun navStackUpdated(nav: WNavigationController) {}
}
