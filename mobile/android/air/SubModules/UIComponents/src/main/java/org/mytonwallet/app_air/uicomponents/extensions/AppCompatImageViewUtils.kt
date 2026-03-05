package org.mytonwallet.app_air.uicomponents.extensions

import android.graphics.drawable.Drawable
import androidx.appcompat.widget.AppCompatImageView
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.widgets.fadeIn
import org.mytonwallet.app_air.uicomponents.widgets.fadeOut

fun AppCompatImageView.crossFadeImage(newDrawable: Drawable) {
    animate().cancel()
    fadeOut(if (drawable == null) 0 else AnimationConstants.VERY_QUICK_ANIMATION / 2) {
        setImageDrawable(newDrawable)
        fadeIn(AnimationConstants.VERY_QUICK_ANIMATION / 2)
    }
}
