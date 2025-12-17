package org.mytonwallet.app_air.uicomponents.widgets.segmentedController

import android.content.Context
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import androidx.core.view.isNotEmpty
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.widgets.WCell

class WSegmentedControllerPageCell(
    context: Context,
) : WCell(context, LayoutParams(MATCH_PARENT, MATCH_PARENT)) {

    fun configure(viewController: WViewController, isFullyVisible: Boolean) {
        if (viewController.view.parent == this)
            return

        if (viewController.view.parent != null)
            (viewController.view.parent as ViewGroup).removeView(viewController.view)
        if (isNotEmpty())
            removeAllViews()
        addView(viewController.view, LayoutParams(MATCH_PARENT, MATCH_PARENT))
        if (isFullyVisible) {
            (viewController as? WSegmentedControllerItemVC)?.onFullyVisible()
        } else {
            (viewController as? WSegmentedControllerItemVC)?.onPartiallyVisible()
        }
    }

}
