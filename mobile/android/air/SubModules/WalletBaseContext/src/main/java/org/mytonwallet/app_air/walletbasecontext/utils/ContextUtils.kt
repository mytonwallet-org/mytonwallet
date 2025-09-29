package org.mytonwallet.app_air.walletbasecontext.utils

import android.content.Context
import android.util.DisplayMetrics

fun Context.density(): Float {
    return resources.displayMetrics.densityDpi.toFloat() / DisplayMetrics.DENSITY_DEFAULT
}
