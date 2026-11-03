package org.mytonwallet.app_air.uicomponents.widgets

import android.content.Context
import org.mytonwallet.app_air.uicomponents.extensions.dp

open class WBottomFadingFrameLayout(context: Context) : WFrameLayout(context) {
    var bottomFadeStrength = 0f
        set(value) {
            if (field == value) return
            field = value
            invalidate()
        }

    init {
        setWillNotDraw(false)
        isVerticalFadingEdgeEnabled = true
        setFadingEdgeLength(24.dp)
    }

    override fun getTopFadingEdgeStrength() = 0f

    override fun getBottomFadingEdgeStrength() = bottomFadeStrength
}
