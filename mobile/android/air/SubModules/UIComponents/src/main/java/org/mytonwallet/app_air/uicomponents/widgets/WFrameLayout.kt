package org.mytonwallet.app_air.uicomponents.widgets

import android.content.Context
import android.widget.FrameLayout

open class WFrameLayout(context: Context) : FrameLayout(context) {
    init {
        id = generateViewId()
    }
}
