package org.mytonwallet.app_air.uicomponents.widgets

import android.annotation.SuppressLint
import android.content.Context
import android.widget.LinearLayout

@SuppressLint("ViewConstructor")
open class WLinearLayout(context: Context, orientation: Int = VERTICAL) :
    LinearLayout(context) {
    init {
        id = generateViewId()
        this.orientation = orientation
    }
}