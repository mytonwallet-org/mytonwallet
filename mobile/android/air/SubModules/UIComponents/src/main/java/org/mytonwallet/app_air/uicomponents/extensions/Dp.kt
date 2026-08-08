package org.mytonwallet.app_air.uicomponents.extensions

import android.util.TypedValue
import kotlin.math.roundToInt
import org.mytonwallet.app_air.walletbasecontext.utils.ApplicationContextHolder

val Int.dp get() = (this * ApplicationContextHolder.density).roundToInt()
val Float.dp get() = this * ApplicationContextHolder.density
val Float.sp
    get() = TypedValue.applyDimension(
        TypedValue.COMPLEX_UNIT_SP,
        this,
        ApplicationContextHolder.applicationContext.resources.displayMetrics
    )
