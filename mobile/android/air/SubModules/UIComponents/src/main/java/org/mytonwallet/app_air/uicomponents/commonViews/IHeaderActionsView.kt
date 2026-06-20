package org.mytonwallet.app_air.uicomponents.commonViews

import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.walletcore.models.MAccount

interface IHeaderActionsView {
    var fadeInPercent: Float
    val asCell: WCell get() = this as WCell

    // True while the actions row is being dragged or settling. Only the tablet
    // (horizontally scrollable) variant can scroll; phone returns false.
    val isScrolling: Boolean get() = false

    val horizontalScrollOffset: Int get() = 0

    fun updateActions(account: MAccount?, tokenSlug: String? = null)
    fun insetsUpdated()
    fun updateTheme()
    fun onDestroy()
}
