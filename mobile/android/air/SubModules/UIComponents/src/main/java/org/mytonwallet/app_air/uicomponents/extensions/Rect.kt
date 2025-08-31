package org.mytonwallet.app_air.uicomponents.extensions

import android.graphics.Rect
import android.view.View

fun Rect.setView(v: View) {
    this.set(v.left, v.top, v.right, v.bottom)
}
