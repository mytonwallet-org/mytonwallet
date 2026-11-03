package org.mytonwallet.app_air.uicomponents.base

interface ISearchOverlayHost {
    fun getBottomNavigationHeight(): Int
    fun clearSearchFocus()

    /** Matches the header the search screen fades in over. */
    val searchNavigationBarHeight: Int get() = WNavigationBar.DEFAULT_HEIGHT
    val searchNavigationBarContentMarginTop: Int get() = 0

    /** Stack that full-screen search results are pushed onto. */
    val searchResultNavigationController: WNavigationController? get() = null

    fun revealSearchOverlay() {}

    fun hideSearchOverlay() {}
}
