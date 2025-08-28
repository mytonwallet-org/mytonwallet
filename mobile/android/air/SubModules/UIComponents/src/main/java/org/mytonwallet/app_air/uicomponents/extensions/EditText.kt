package org.mytonwallet.app_air.uicomponents.extensions

import android.widget.EditText

fun EditText.setTextIfDiffer(text: String?, selectionToEnd: Boolean = true) {
    if (this.text?.toString() == text) {
        return
    }

    this.setText(text)
    if (selectionToEnd) {
        try {
            text?.let { setSelection(it.length) }
        } catch (_: Throwable) {
        }
    }
}
