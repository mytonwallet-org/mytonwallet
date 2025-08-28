package org.mytonwallet.app_air.walletcontext.utils

import android.content.Context
import android.util.DisplayMetrics

fun Context.density(): Float {
    return resources.displayMetrics.densityDpi.toFloat() / DisplayMetrics.DENSITY_DEFAULT
}
