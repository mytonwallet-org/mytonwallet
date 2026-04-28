package org.mytonwallet.uihome.tabs.views

import android.content.Context
import android.view.View
import android.widget.FrameLayout
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView

abstract class IBottomNavigationView(context: Context) : FrameLayout(context), WThemedView {

    companion object {
        const val ID_HOME = 1
        const val ID_AGENT = 2
        const val ID_EXPLORE = 3
        const val ID_SETTINGS = 4
    }

    interface Listener {
        /**
         * Called when a tab is selected. Return true to accept, false to reject.
         * [isReselect] is true when the already-selected tab is tapped again.
         */
        fun onTabSelected(itemId: Int, isReselect: Boolean): Boolean
    }

    abstract var listener: Listener?

    abstract var selectedItemId: Int

    abstract fun insetsUpdated(bottomInset: Int)

    abstract fun setTabsEnabled(enabled: Boolean)

    open fun getSettingsItemView(): View? = null

    open fun getMinimizedWidth(): Int? = null

    open fun pauseBlurring() {}
    open fun resumeBlurring() {}
    open val pausedBlurViews: Boolean get() = false
}
