package org.mytonwallet.app_air.uicomponents.widgets

import org.mytonwallet.app_air.uicomponents.widgets.menu.WMenuPopup
import org.mytonwallet.app_air.uicomponents.widgets.menu.WMenuPopupView

interface INavigationPopup : IPopup {
    fun push(
        nextPopupView: WMenuPopupView,
        animated: Boolean = true,
        onCompletion: (() -> Unit)? = null,
        transition: WMenuPopup.SubmenuTransition = WMenuPopup.SubmenuTransition.PAGE,
        sourceItemIndex: Int? = null
    )

    fun pop(animated: Boolean = true, onCompletion: (() -> Unit)? = null)
}
