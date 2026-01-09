package org.mytonwallet.app_air.uicomponents.widgets

import org.mytonwallet.app_air.uicomponents.widgets.menu.WMenuPopupView

interface INavigationPopup : IPopup {
    fun push(
        nextPopupView: WMenuPopupView,
        animated: Boolean = true,
        onCompletion: (() -> Unit)? = null
    )

    fun pop(
        animated: Boolean = true,
        onCompletion: (() -> Unit)? = null
    )
}
