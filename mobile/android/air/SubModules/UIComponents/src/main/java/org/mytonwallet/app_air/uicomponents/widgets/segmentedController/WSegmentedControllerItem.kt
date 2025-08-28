package org.mytonwallet.app_air.uicomponents.widgets.segmentedController

import android.view.View
import org.mytonwallet.app_air.uicomponents.base.WViewController

data class WSegmentedControllerItem(
    val viewController: WViewController,
    val identifier: String? = null,
    var onClick: ((v: View) -> Unit)? = null
)
