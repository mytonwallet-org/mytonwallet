package org.mytonwallet.app_air.uicomponents.helpers

import android.widget.PopupWindow
import java.lang.ref.WeakReference

object PopupHelpers {
    private val popups = ArrayList<WeakReference<PopupWindow>>()
    fun popupShown(popup: PopupWindow) {
        popups.add(WeakReference(popup))
    }

    fun popupDismissed(popup: PopupWindow) {
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
