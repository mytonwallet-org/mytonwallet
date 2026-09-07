package org.mytonwallet.app_air.uicomponents.widgets

import android.content.Context
import android.graphics.Canvas
import android.view.View
import android.widget.FrameLayout
import org.mytonwallet.app_air.uicomponents.glass.GlassCaptureHost

open class WFrameLayout(context: Context) :
    FrameLayout(context),
    GlassCaptureHost {

    override fun glassDrawChild(canvas: Canvas, child: View, drawingTime: Long): Boolean =
        drawChild(canvas, child, drawingTime)
    init {
        id = generateViewId()
    }
}
