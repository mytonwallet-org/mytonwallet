package org.mytonwallet.app_air.uicomponents.extensions

import android.graphics.RectF
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController

fun RectF.setLocalized(start: Float, top: Float, end: Float, bottom: Float, containerWidth: Float) {
    set(
        if (LocaleController.isRTL) containerWidth - end else start,
        top,
        if (LocaleController.isRTL) containerWidth - start else end,
        bottom
    )
}
