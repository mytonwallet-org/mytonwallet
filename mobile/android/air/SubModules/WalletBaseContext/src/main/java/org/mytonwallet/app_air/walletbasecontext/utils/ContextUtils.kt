package org.mytonwallet.app_air.walletbasecontext.utils

import android.content.Context
import android.graphics.drawable.Drawable
import android.util.DisplayMetrics
import androidx.annotation.DrawableRes
import androidx.appcompat.content.res.AppCompatResources

fun Context.density(): Float {
    return resources.displayMetrics.densityDpi.toFloat() / DisplayMetrics.DENSITY_DEFAULT
}

fun Context.getDrawableCompat(@DrawableRes resId: Int): Drawable? {
    return AppCompatResources.getDrawable(this, resId)
}

fun Context.requireDrawableCompat(@DrawableRes resId: Int): Drawable {
    return requireNotNull(getDrawableCompat(resId)) { "Drawable $resId not found" }
}
