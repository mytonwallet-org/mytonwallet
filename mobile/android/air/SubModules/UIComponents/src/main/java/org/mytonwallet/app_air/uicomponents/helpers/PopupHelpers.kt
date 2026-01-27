package org.mytonwallet.app_air.uicomponents.helpers

import org.mytonwallet.app_air.uicomponents.widgets.IPopup
import org.mytonwallet.app_air.uicomponents.widgets.menu.WPopupHost
import java.lang.ref.WeakReference

object PopupHelpers {

    private val popups = ArrayList<WeakReference<IPopup>>()
    private var popupHostRef: WeakReference<WPopupHost>? = null
    val popupHost: WPopupHost? get() = popupHostRef?.get()

    fun attachPopupHost(popupHost: WPopupHost) {
        this.popupHostRef = WeakReference(popupHost)
    }

    fun popupShown(popup: IPopup) {
        popups.add(WeakReference(popup))
    }

    fun popupDismissed(popup: IPopup) {
        popups.removeAll {
            it.get() == popup
        }
    }

    fun dismissAllPopups() {
        popups.forEach {
            it.get()?.dismiss()
        }
    }

    fun onBackPressed(): Boolean {
        if (popups.isEmpty())
            return false
        popups.lastOrNull()?.get()?.onBackPressed() ?: return false
        return true
    }
}
