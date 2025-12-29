package org.mytonwallet.app_air.uicomponents.helpers

import android.widget.PopupWindow
import org.mytonwallet.app_air.uicomponents.widgets.IPopup
import java.lang.ref.WeakReference

object PopupHelpers {
    private val popups = ArrayList<WeakReference<IPopup>>()
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
}
