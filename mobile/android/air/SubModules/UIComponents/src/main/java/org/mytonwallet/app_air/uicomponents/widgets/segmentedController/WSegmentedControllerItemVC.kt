package org.mytonwallet.app_air.uicomponents.widgets.segmentedController

interface WSegmentedControllerItemVC {
    var segmentedController: WSegmentedController?
    var badge: String?

    fun onFullyVisible()
    fun onPartiallyVisible()
}
