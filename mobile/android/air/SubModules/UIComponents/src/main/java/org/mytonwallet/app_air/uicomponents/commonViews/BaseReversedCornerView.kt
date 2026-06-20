package org.mytonwallet.app_air.uicomponents.commonViews

import android.content.Context
import android.widget.FrameLayout
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants

public open class BaseReversedCornerView(context: Context) : FrameLayout(context) {
    var pathDirty = true

    var startHorizontalPadding = ViewConstants.HORIZONTAL_PADDINGS.dp.toFloat()
        private set
    var endHorizontalPadding = ViewConstants.HORIZONTAL_PADDINGS.dp.toFloat()
        private set

    fun setHorizontalPadding(padding: Float) {
        setHorizontalPadding(padding, padding)
    }

    fun setHorizontalPadding(start: Float, end: Float) {
        if (startHorizontalPadding == start && endHorizontalPadding == end)
            return
        startHorizontalPadding = start
        endHorizontalPadding = end
        pathDirty = true
        invalidate()
    }

    var startInset = 0f
        private set
    var endInset = 0f
        private set

    fun setSideInsets(start: Float, end: Float) {
        if (startInset == start && endInset == end)
            return
        startInset = start
        endInset = end
        pathDirty = true
        invalidate()
    }

    var maxContentWidth = 0f
        private set

    fun setMaxContentWidth(width: Float) {
        if (maxContentWidth == width)
            return
        maxContentWidth = width
        pathDirty = true
        invalidate()
    }

    protected fun cutoutStart(width: Float, tabletPadding: Float): Float {
        val capped = maxContentWidth
        val available = width - startInset - endInset
        val centeringOffset =
            if (capped > 0f && available > capped) (available - capped) / 2f else 0f
        return startInset + centeringOffset + startHorizontalPadding + tabletPadding
    }

    protected fun cutoutEnd(width: Float): Float {
        val capped = maxContentWidth
        val available = width - startInset - endInset
        val centeringOffset =
            if (capped > 0f && available > capped) (available - capped) / 2f else 0f
        return width - endInset - centeringOffset - endHorizontalPadding
    }

}
