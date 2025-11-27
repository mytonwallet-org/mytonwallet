package org.mytonwallet.app_air.uicomponents.commonViews

import android.content.Context
import android.widget.FrameLayout
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants

public open class BaseReversedCornerView(context: Context) : FrameLayout(context) {
    var pathDirty = true

    var horizontalPadding = ViewConstants.HORIZONTAL_PADDINGS.dp.toFloat()
        private set

    fun setHorizontalPadding(padding: Float) {
        if (horizontalPadding == padding)
            return
        horizontalPadding = padding
        pathDirty = true
        invalidate()
    }

}
