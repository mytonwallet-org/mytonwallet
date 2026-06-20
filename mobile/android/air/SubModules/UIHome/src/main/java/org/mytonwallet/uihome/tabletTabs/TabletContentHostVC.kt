package org.mytonwallet.uihome.tabletTabs

import android.annotation.SuppressLint
import android.content.Context
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import org.mytonwallet.app_air.uicomponents.base.WNavigationController
import org.mytonwallet.app_air.uicomponents.base.WViewController

/**
 * Root view controller of the tablet content-panel navigation controller. It simply hosts the
 * active per-tab navigation stack's view, so that full-screen VCs pushed over the tablet's main
 * navigation controller stack above the tab content (mirroring the phone, where such pushes sit
 * above the tab container in the window nav).
 */
@SuppressLint("ViewConstructor")
class TabletContentHostVC(context: Context) : WViewController(context) {
    override val TAG = "TabletContentHost"
    override val shouldDisplayTopBar = false
    override val isSwipeBackAllowed = false

    val contentParent: ViewGroup get() = view
    private var contentNav: WNavigationController? = null

    /** Mount the given per-tab nav as the visible content. */
    fun setContent(nav: WNavigationController) {
        if (nav.parent === view) {
            contentNav = nav
            return
        }
        (nav.parent as? ViewGroup)?.removeView(nav)
        view.removeAllViews()
        view.addView(nav, ViewGroup.LayoutParams(MATCH_PARENT, MATCH_PARENT))
        contentNav = nav
    }

    fun detachContent() {
        view.removeAllViews()
        contentNav = null
    }

    // Forward lifecycle to the mounted per-tab nav so its top VC appears/disappears with this host.
    override fun viewWillAppear() {
        super.viewWillAppear()
        contentNav?.viewWillAppear()
    }

    override fun viewDidAppear() {
        super.viewDidAppear()
        contentNav?.viewDidAppear()
    }

    override fun viewWillDisappear() {
        super.viewWillDisappear()
        contentNav?.viewWillDisappear()
    }
}
