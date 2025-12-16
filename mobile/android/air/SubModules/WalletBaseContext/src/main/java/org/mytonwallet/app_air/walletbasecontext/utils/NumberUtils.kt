package org.mytonwallet.app_air.walletbasecontext.utils

import kotlin.math.ceil
import kotlin.math.roundToInt

fun Number.ceilToInt(): Int {
    return when (this) {
        is Float -> ceil(this).roundToInt()
        is Double -> ceil(this).roundToInt()
        else -> ceil(toDouble()).roundToInt()
    }
}
