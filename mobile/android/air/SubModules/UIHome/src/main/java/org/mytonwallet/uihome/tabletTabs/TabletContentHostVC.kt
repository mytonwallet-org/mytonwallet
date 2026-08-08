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
    @Suppress("PropertyName")
    override val TAG = "TabletContentHost"
    override val shouldDisplayTopBar = false
    override val isSwipeBackAllowed = false

    val contentParent: ViewGroup get() = view
    private var contentNav: WNavigationController? = null
    private var isAppearanceComplete = false

    /** Mount the given per-tab nav as the visible content. */
    fun setContent(nav: WNavigationController) {
        if (nav.parent === view) {
            contentNav = nav
            return
        }
        if (!isDisappeared) contentNav?.viewWillDisappear()
        (nav.parent as? ViewGroup)?.removeView(nav)
        view.removeAllViews()
        view.addView(nav, ViewGroup.LayoutParams(MATCH_PARENT, MATCH_PARENT))
        contentNav = nav
        if (!isDisappeared) {
            nav.viewWillAppear()
            if (isAppearanceComplete) nav.viewDidAppear()
        }
    }

    fun detachContent() {
        if (!isDisappeared) contentNav?.viewWillDisappear()
        view.removeAllViews()
        contentNav = null
    }

    // Forward lifecycle to the mounted per-tab nav so its top VC appears/disappears with this host.
    override fun viewWillAppear() {
        if (!isDisappeared) return
        super.viewWillAppear()
        isAppearanceComplete = false
        contentNav?.viewWillAppear()
    }

    override fun viewDidAppear() {
        if (isDisappeared) return
        super.viewDidAppear()
        isAppearanceComplete = true
        contentNav?.viewDidAppear()
    }

    override fun viewWillDisappear() {
        if (isDisappeared) return
        super.viewWillDisappear()
        isAppearanceComplete = false
        contentNav?.viewWillDisappear()
    }
}
